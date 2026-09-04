import Foundation
import SwiftUI

// LearningGoalStore.swift
// **Ziel-System (2026-08-05, Umbau 2026-08-08)** — Persistenz +
// Fortschritts-Berechnung.
//
// Rolle im System (Abgrenzung zu den Nachbar-Stores):
//   • `ProgressStore`           → XP / Level / Credits / Streak /
//     Tages-Zähler (`todayCorrectCount`) — die Zahlenbasis
//   • `DailyStatsStore`         → Tages-Feedback (wie viel heute?)
//   • `ItemLearningStatusStore` → pro Vokabel: sitzt / wackelt
//   • **`LearningGoalStore`**   → **das selbstgesetzte Ziel** und wie weit
//     der Nutzer dabei ist.
//
// **Bewusst keine eigene Lernerfolgs-Buchführung.** Der Inhalts-Fortschritt
// wird bei jedem Zugriff aus `ItemLearningStatusStore` + `VocabularyListStore`
// abgeleitet, der Tagesziel-Fortschritt aus `ProgressStore.todayCorrectCount`
// (demselben Zähler, der auch den Streak triggert). Hier wird nur der
// Plan selbst gespeichert — kein zweiter Tages-Zähler mehr.
//
// **2026-08-08** — die frühere wochenbasierte Rhythmus-Rechnung
// (`practicedDayIndices`, `weekIndex`) ist entfallen: Ein Wochenziel und
// ein Tagesziel in EINEM Store zu führen war die Doppelgleisigkeit, die
// der Umbau auflösen sollte (siehe `LearningGoalPlan.swift`-Kommentar).
@MainActor
final class LearningGoalStore: ObservableObject {
    static let shared = LearningGoalStore()

    /// Der aktive Plan. `nil` = Onboarding noch nicht durchlaufen.
    /// Nach dem Onboarding ist er immer gesetzt (Ziel ist Pflicht), damit
    /// die Fortschrittsanzeige nie einen leeren Zustand rendern muss.
    @Published private(set) var plan: LearningGoalPlan?

    /// Abgeschlossene bzw. abgelaufene Inhaltsziele. Wird für den
    /// „Wie lief's?"-Nachlauf und spätere Rückblicke aufgehoben.
    @Published private(set) var archivedContentGoals: [LearningGoalContent] = []

    /// **Ring-Schließen-Signal (2026-08-05)** — reiner UI-Zustand, NICHT
    /// persistiert. Wird gesetzt, wenn der Nutzer im Scan-Rückweg
    /// (`ImportCompletionView` → "Zu deinem Ziel hinzufügen") eine
    /// Liste zu einem wartenden Ziel hinzugefügt hat.
    /// `RootContentView` beobachtet dieses Flag und öffnet das
    /// Ziel-Onboarding-Overlay erneut, direkt beim Feier-Screen — sonst
    /// würde der Nutzer nach dem Scannen kommentarlos auf Home landen,
    /// ohne dass der Onboarding-Kreis sich je geschlossen hätte
    /// (User-Report: "ich komm da jetzt nicht mehr hin").
    @Published var pendingCelebrationRequested = false

    /// **2026-08-05** — Reiner UI-Zustand (nicht persistiert). Wird
    /// gesetzt, wenn irgendwo in der App (Übungs-Setup-Picker,
    /// „Meine Listen") eine Liste gewählt wird, die von der Zielliste
    /// abweicht. `RootContentView` beobachtet dieses Flag und zeigt
    /// einen kurzen, global sichtbaren Hinweis — die Übungs-Setup-
    /// Picker (Quiz/Training/Karteikarten) haben selbst keine eigene
    /// Toast-Infrastruktur, „Meine Listen" schon, aber der Hinweis soll
    /// überall gleich funktionieren, egal von wo die Auswahl kommt.
    @Published var listDivergenceWarning: String?
    private var listDivergenceDismissWorkItem: DispatchWorkItem?

    /// **2026-08-05, Testphase-Guard** — stellt sicher, dass der
    /// `FeatureFlags.alwaysResetGoalOnboardingForTesting`-Reset wirklich
    /// nur EINMAL pro App-Start läuft.
    ///
    /// Ohne diesen Guard war der Reset an `RootContentView.onAppear`
    /// gekoppelt — und das feuert erneut, wenn die App aus dem
    /// Hintergrund zurückkehrt. Genau das passiert mitten im Scan-Flow
    /// (Kamera bzw. Fotoauswahl blenden die App aus): Das gerade im
    /// Onboarding gesetzte Ziel wurde dadurch gelöscht, während der
    /// Nutzer noch scannte. Beim Import-Abschluss war
    /// `isAwaitingListAssignment` folglich `false` und statt des
    /// "Du bist startbereit"-Screens erschien die normale
    /// Modul-Auswahl — der Nutzer fiel aus dem Onboarding heraus
    /// (User-Report mit Screenshot).
    private static var didRunTestingResetThisLaunch = false

    /// Führt den Testphase-Reset genau einmal pro App-Start aus.
    /// No-Op, sobald der Flag aus ist oder der Reset schon lief.
    func resetForTestingIfNeeded() {
        guard FeatureFlags.alwaysResetGoalOnboardingForTesting,
              !Self.didRunTestingResetThisLaunch
        else { return }
        Self.didRunTestingResetThisLaunch = true
        reset()
    }

    // MARK: - Keys

    private var planKey: String {
        AccountStore.shared.namespacedKey(appLearningGoalPlanKey)
    }
    private var archiveKey: String {
        AccountStore.shared.namespacedKey(appLearningGoalArchiveKey)
    }

    // MARK: - Init

    init() {
        load()
    }

    // MARK: - Ziel setzen / ändern

    /// Schreibt einen neuen Plan (Onboarding-Abschluss oder späteres
    /// Ändern). Der Wochenfortschritt bleibt dabei **erhalten** — wer
    /// mitten in der Woche sein Ziel anpasst, soll nicht die bereits
    /// geübten Tage verlieren.
    func setPlan(_ newPlan: LearningGoalPlan) {
        plan = newPlan
        persist()
        syncGlobalSelectionWithContentGoal()
    }

    /// Nur das Tagesziel ändern, Inhaltsziel unangetastet.
    func updateDailyTarget(minutes: Int) {
        guard var current = plan else { return }
        current.dailyTargetMinutes = LearningGoalPlan.clampDailyTargetMinutes(minutes)
        plan = current
        persist()
    }

    /// Inhaltsziel setzen, ersetzen oder (mit `nil`) entfernen.
    /// Ein vorhandenes Inhaltsziel wandert dabei ins Archiv, damit der
    /// Verlauf nicht verloren geht.
    func updateContentGoal(_ content: LearningGoalContent?) {
        guard var current = plan else { return }
        if let previous = current.content, previous != content {
            archivedContentGoals.append(previous)
        }
        current.content = content
        plan = current
        persist()
        syncGlobalSelectionWithContentGoal()
    }

    /// Setzt die Listen eines Inhaltsziels neu (Mehrfachauswahl-Screen).
    func setLists(_ listIDs: [UUID]) {
        guard var current = plan, var content = current.content else { return }
        content.listIDs = listIDs
        current.content = content
        plan = current
        persist()
        syncGlobalSelectionWithContentGoal()
    }

    /// Hängt eine Liste an ein bestehendes Inhaltsziel an, ohne die
    /// vorhandenen zu verwerfen.
    ///
    /// Das ist der **Rückweg aus dem Scan**: Wenn ein Ziel auf Material
    /// wartet und der Schüler gerade sein Kapitel abfotografiert hat,
    /// wandert die frisch gebaute Liste hierüber ins Ziel. Ohne diesen
    /// Weg hätte er zwar gescannt, sein Ziel bliebe aber leer.
    ///
    /// Doppelte Zuordnung wird still ignoriert.
    func addList(_ listID: UUID) {
        guard var current = plan, var content = current.content else { return }
        guard !content.listIDs.contains(listID) else { return }
        content.listIDs.append(listID)
        current.content = content
        plan = current
        persist()
        syncGlobalSelectionWithContentGoal()
    }

    /// **2026-08-05, Korrektur** — die Anlass `.shakyItems` („Meine
    /// Wackelkandidaten wegräumen") hat bewusst KEINE `listIDs`: der
    /// Bestand kommt dynamisch aus dem Lernstatus, nicht aus einer fest
    /// zugeordneten Liste, damit frisch gefestigte Vokabeln automatisch
    /// rausfallen. Für die Listen-AUSWAHL in Quiz/Training/Karteikarten
    /// braucht es aber trotzdem eine konkrete Liste — sonst überspringt
    /// das Onboarding zwar zurecht die Listen-Auswahl, aber Training
    /// bleibt auf der zuvor gewählten Liste stehen (User-Report: Ziel =
    /// Wackelkandidaten, „Vokabeln"-Übung zeigte trotzdem „Buch Seite
    /// 76"). Die generierte Wackelkandidaten-Liste
    /// (`VocabularyListStore.wackelkandidatenListID`) ist genau dafür da.
    var effectiveGoalListIDs: [UUID] {
        guard let content = plan?.content else { return [] }
        if content.occasion == .shakyItems {
            return [VocabularyListStore.wackelkandidatenListID]
        }
        return content.listIDs
    }

    /// **2026-08-05** — Macht die Zielliste(n) überall in der App zur
    /// aktiven Auswahl (Quiz, Training, Karteikarten, …). User-Report: das
    /// Ziel war auf „Meine Wackelkandidaten" gesetzt, Quiz zeigte aber
    /// weiterhin „gesamter eigener Wortschatz" — Ziel-Liste und globale
    /// Auswahl waren zwei getrennte Systeme, die nie synchronisiert
    /// wurden.
    private func syncGlobalSelectionWithContentGoal() {
        let listIDs = effectiveGoalListIDs
        guard !listIDs.isEmpty else { return }
        VocabularyListSelectionResolver.setGlobalSelectedListIDs(Set(listIDs))
    }

    /// **2026-08-05** — Gegenstück zu `syncGlobalSelectionWithContentGoal`:
    /// wird gerufen, wenn die globale Auswahl NICHT vom Ziel-System selbst
    /// kommt, sondern von einem Übungs-Setup-Picker (Quiz/Training/
    /// Karteikarten) oder „Meine Listen". Zeigt einen kurzen Hinweis,
    /// wenn die neue Auswahl von der Zielliste abweicht — ändert am Ziel
    /// selbst nichts, ist reine Information.
    func noteManualListSelection(_ ids: Set<UUID>) {
        let goalListIDs = effectiveGoalListIDs
        guard !goalListIDs.isEmpty else { return }
        guard ids != Set(goalListIDs) else { return }

        listDivergenceDismissWorkItem?.cancel()
        listDivergenceWarning = "Du übst gerade nicht deine Zielliste."
        let workItem = DispatchWorkItem { [weak self] in
            self?.listDivergenceWarning = nil
        }
        listDivergenceDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: workItem)
    }

    /// Ob gerade ein Inhaltsziel auf Vokabeln wartet. Der Scan-Flow fragt
    /// das ab, um nach getaner Arbeit „Zu deinem Ziel hinzufügen?"
    /// anzubieten statt den Nutzer mit einer losen Liste stehenzulassen.
    var isAwaitingListAssignment: Bool {
        let result = plan?.content?.isAwaitingList ?? false
        #if DEBUG
        // Diagnose-Hilfe für den Scan-Rückweg: Dieser Wert entscheidet,
        // ob nach dem Import der Onboarding-Abschluss oder die normale
        // Modul-Auswahl erscheint. Bei Fehlverhalten zeigt der Log
        // sofort, WELCHE Bedingung gekippt ist.
        if let content = plan?.content {
            print("🎯 [Rückweg] isAwaitingListAssignment=\(result) — occasion=\(content.occasion.rawValue), requiresList=\(content.occasion.requiresListSelection), listIDs=\(content.listIDs.count)")
        } else {
            print("🎯 [Rückweg] isAwaitingListAssignment=false — plan=\(plan == nil ? "nil" : "gesetzt"), content=nil")
        }
        #endif
        return result
    }

    /// Schiebt ein abgelaufenes bzw. erledigtes Inhaltsziel ins Archiv,
    /// ohne es als „gescheitert" zu markieren. Das Tagesziel bleibt
    /// bestehen — der Nutzer fällt also nie in einen ziellosen Zustand.
    func archiveContentGoal() {
        guard var current = plan, let content = current.content else { return }
        archivedContentGoals.append(content)
        current.content = nil
        plan = current
        persist()
    }

    // MARK: - Fortschritt

    /// Fortschritt des Tagesziels heute. Liest `ProgressStore.todayCorrectCount`
    /// — denselben Zähler, der auch den Streak triggert. Kein eigener
    /// Buchungsaufruf nötig: `ProgressService.record(session:)` schreibt
    /// diesen Zähler bereits für den Streak fort, das Tagesziel liest nur
    /// mit. Ohne Plan wird das Default-Ziel angenommen, damit die UI immer
    /// eine sinnvolle Zahl bekommt.
    var dailyProgress: DailyGoalProgress {
        let minutes = plan?.dailyTargetMinutes ?? LearningGoalPlan.defaultDailyTargetMinutes
        let target = LearningGoalPlan.dailyTargetItems(forMinutes: minutes)
        let today = GamificationConfig.currentDayIndex
        let store = ProgressStore.shared
        let done = store.progress.todayCorrectDayIndex == today ? store.progress.todayCorrectCount : 0
        return DailyGoalProgress(doneItems: done, targetItems: target)
    }

    /// Fortschritt des Inhaltsziels — vollständig abgeleitet, nichts
    /// davon ist persistiert.
    ///
    /// Zwei Quellen je nach Anlass:
    ///   • `.shakyItems` → dynamischer Bestand aus dem Lernstatus. „Fertig"
    ///     heißt hier: es wackelt nichts mehr.
    ///   • sonst → die zugeordnete Liste; `.strong` gilt als gekonnt.
    ///
    /// Der Abgleich läuft über denselben kanonisierten Schlüssel, den
    /// `ItemLearningStatusStore` beim Buchen verwendet — sonst würden
    /// Groß-/Kleinschreibung oder Artikel zu Fehltreffern führen.
    func contentProgress(
        listStore: VocabularyListStore,
        statusStore: ItemLearningStatusStore = .shared
    ) -> ContentGoalProgress? {
        guard let content = plan?.content else { return nil }

        if content.occasion == .shakyItems {
            let shaky = VocabularyListStore
                .usableWackelkandidatenItems(from: statusStore.wackelkandidatenItems)
                .count
            let strong = statusStore.strongItems.count
            return ContentGoalProgress(
                strongCount: strong,
                totalCount: strong + shaky
            )
        }

        guard !content.listIDs.isEmpty else {
            return ContentGoalProgress(strongCount: 0, totalCount: 0)
        }

        // **Dedupe über Listengrenzen hinweg.** Bei Mehrfachauswahl kann
        // dieselbe Vokabel in zwei Listen stehen (z. B. „Unit 3" und
        // „Vokabelheft"). Ohne Dedupe würde sie doppelt in Zähler UND
        // Nenner landen und den Fortschritt verzerren. Der kanonische
        // Schlüssel ist derselbe, den `ItemLearningStatusStore` beim
        // Buchen verwendet — sonst gäbe es Fehltreffer durch
        // Groß-/Kleinschreibung oder Satzzeichen.
        var uniqueKeys = Set<String>()
        for listID in content.listIDs {
            guard let list = listStore.customList(with: listID) else { continue }
            for item in list.items {
                uniqueKeys.insert(
                    ItemLearningStatusStore.canonicalKey(
                        french: item.french,
                        german: item.german,
                        cardType: item.cardType
                    )
                )
            }
        }

        let strongKeys = Set(statusStore.strongItems.map(\.key))
        return ContentGoalProgress(
            strongCount: uniqueKeys.intersection(strongKeys).count,
            totalCount: uniqueKeys.count
        )
    }

    /// Ob ein Inhaltsziel mit abgelaufener Deadline auf den
    /// „Wie lief's?"-Nachlauf wartet.
    var hasExpiredContentGoal: Bool {
        plan?.content?.isExpired() ?? false
    }

    // MARK: - Reset

    /// Setzt das **gesamte** Ziel-System zurück, inklusive Plan und
    /// Archiv. Nur für den destruktiven Pfad (Account löschen / alle
    /// Nutzerdaten verwerfen) — nach diesem Aufruf hat der Nutzer kein
    /// Ziel mehr und muss die Ziel-Auswahl erneut durchlaufen.
    ///
    /// **2026-08-08** — der frühere `resetWeeklyProgress()` (Pfad für
    /// „Spielstand zurücksetzen", Ziel bleibt stehen) ist entfallen: der
    /// Tagesziel-Fortschritt lebt jetzt komplett in `ProgressStore`
    /// (`todayCorrectCount`), dessen eigener Reset (`GameStateResetService`)
    /// das bereits mit abdeckt — keine zweite Stelle mehr nötig.
    func reset() {
        plan = nil
        archivedContentGoals = []
        persist()
    }

    // MARK: - Persistenz

    /// Lädt aus dem Namespace des aktuell aktiven Accounts. Öffentlich,
    /// damit der Account-Switch dieselbe Reload-Mechanik nutzen kann wie
    /// die anderen Per-Account-Stores.
    func load() {
        let defaults = UserDefaults.standard

        if let data = defaults.data(forKey: planKey) {
            plan = try? JSONDecoder().decode(LearningGoalPlan.self, from: data)
        } else {
            plan = nil
        }

        if let data = defaults.data(forKey: archiveKey) {
            archivedContentGoals =
                (try? JSONDecoder().decode([LearningGoalContent].self, from: data)) ?? []
        } else {
            archivedContentGoals = []
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard

        if let plan, let data = try? JSONEncoder().encode(plan) {
            defaults.set(data, forKey: planKey)
        } else {
            defaults.removeObject(forKey: planKey)
        }

        if archivedContentGoals.isEmpty {
            defaults.removeObject(forKey: archiveKey)
        } else if let data = try? JSONEncoder().encode(archivedContentGoals) {
            defaults.set(data, forKey: archiveKey)
        }
    }
}

#if DEBUG
// MARK: - Debug-Verifikation
//
// Solange die Onboarding-Screens noch nicht stehen, gibt es keinen Weg,
// ein Ziel zu setzen. Diese Helfer schließen die Lücke, damit die
// Rechnung geprüft werden kann, BEVOR UI darauf gebaut wird — Screens
// auf eine nie verifizierte Zahl zu setzen rächt sich erfahrungsgemäß.
//
// Vollständig in `#if DEBUG` gekapselt: Im Release-Build existiert
// nichts davon, kein späteres Aufräumen nötig.
extension LearningGoalStore {
    /// Setzt ein Testziel. `listID` optional — ohne Liste landet das
    /// Inhaltsziel im „wartet noch auf Vokabeln"-Zustand, was ebenfalls
    /// ein prüfenswerter Fall ist.
    func debugSeedGoal(
        dailyTargetMinutes: Int = 10,
        occasion: LearningOccasion? = nil,
        listIDs: [UUID] = [],
        deadlineInDays: Int? = nil
    ) {
        let content: LearningGoalContent? = occasion.map { occ in
            LearningGoalContent(
                occasion: occ,
                listIDs: listIDs,
                deadline: deadlineInDays.map {
                    Calendar.current.date(byAdding: .day, value: $0, to: Date()) ?? Date()
                }
            )
        }
        setPlan(LearningGoalPlan(dailyTargetMinutes: dailyTargetMinutes, content: content))
        debugDumpState()
    }

    /// Füllt den heutigen Tagesziel-Balken künstlich, ohne echtes Üben —
    /// bucht direkt in `ProgressStore.todayCorrectCount` (derselbe Zähler,
    /// den auch der Streak liest).
    func debugAddTodayCorrect(_ count: Int) {
        let today = GamificationConfig.currentDayIndex
        ProgressStore.shared.mutate { p in
            if p.todayCorrectDayIndex != today {
                p.todayCorrectDayIndex = today
                p.todayCorrectCount = 0
            }
            p.todayCorrectCount += max(0, count)
        }
        debugDumpState()
    }

    /// Schreibt den kompletten Zielzustand in die Konsole — inklusive
    /// Inhalts-Fortschritt, wenn ein `listStore` mitgegeben wird.
    func debugDumpState(listStore: VocabularyListStore? = nil) {
        print("──────── 🎯 Ziel-Status ────────")
        guard let plan else {
            print("  Kein Ziel gesetzt (Onboarding noch nicht durchlaufen).")
            print("  Tagesziel-Default greift: \(dailyProgress.doneItems)/\(dailyProgress.targetItems)")
            print("────────────────────────────────")
            return
        }

        let d = dailyProgress
        print("  Heute: \(d.doneItems) von \(d.targetItems) Vokabeln"
              + (d.isReached ? "  ✅" : "  (noch \(d.remainingItems))"))

        if let content = plan.content {
            print("  Inhaltsziel: \(content.displayTitle)  [\(content.occasion.rawValue)]")
            if content.isAwaitingList {
                print("    ⚠️ Noch keine Liste zugeordnet.")
            }
            if let days = content.daysRemaining() {
                print("    Deadline: noch \(days) Tag(e)" + (content.isExpired() ? "  ⏰ abgelaufen" : ""))
            }
            if let listStore, let p = contentProgress(listStore: listStore) {
                print("    Fortschritt: \(p.strongCount)/\(p.totalCount) sitzen"
                      + (p.isEmpty ? "  (kein Bestand)" : "  → \(Int(p.fraction * 100)) %"))
            } else if listStore == nil {
                print("    (listStore nicht übergeben — Inhalts-Fortschritt nicht berechnet)")
            }
        } else {
            print("  Kein Inhaltsziel — reines Tagesziel.")
        }
        print("  Archiv: \(archivedContentGoals.count) abgeschlossene(s) Ziel(e)")
        print("────────────────────────────────")
    }
}
#endif
