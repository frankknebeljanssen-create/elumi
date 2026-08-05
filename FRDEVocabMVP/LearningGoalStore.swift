import Foundation
import SwiftUI

// LearningGoalStore.swift
// **Ziel-System (2026-08-05)** — Persistenz + Fortschritts-Berechnung.
//
// Rolle im System (Abgrenzung zu den Nachbar-Stores):
//   • `ProgressStore`           → XP / Level / Credits / Streak
//   • `DailyStatsStore`         → Tages-Feedback (wie viel heute?)
//   • `ItemLearningStatusStore` → pro Vokabel: sitzt / wackelt
//   • **`LearningGoalStore`**   → **das selbstgesetzte Ziel** und wie weit
//     der Nutzer dabei ist.
//
// **Bewusst keine eigene Lernerfolgs-Buchführung.** Der Inhalts-Fortschritt
// wird bei jedem Zugriff aus `ItemLearningStatusStore` + `VocabularyListStore`
// abgeleitet. Nur zwei Dinge werden hier wirklich gespeichert: der Plan
// selbst und an welchen Tagen geübt wurde.
//
// **Wochen-Rhythmus:** Die Woche beginnt Montag und folgt demselben
// 6-Uhr-Rollover wie Streak und DailyStats (`GamificationConfig.currentDayIndex`),
// damit „heute" überall in der App dasselbe bedeutet. Ein Schüler, der um
// 1 Uhr nachts noch übt, bucht das auf den Vortag — so wie er es selbst
// empfinden würde.
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

    /// Tages-Indizes der laufenden Woche, an denen geübt wurde.
    /// Set statt Zähler: Zwei Sessions am selben Tag sind ein Tag.
    @Published private(set) var practicedDayIndices: Set<Int> = []

    /// Wochen-Index, zu dem `practicedDayIndices` gehört. Weicht er vom
    /// aktuellen ab, gilt die Woche als frisch.
    @Published private(set) var weekIndex: Int = LearningGoalStore.currentWeekIndex

    // MARK: - Keys

    private var planKey: String {
        AccountStore.shared.namespacedKey(appLearningGoalPlanKey)
    }
    private var archiveKey: String {
        AccountStore.shared.namespacedKey(appLearningGoalArchiveKey)
    }
    private var practicedDaysKey: String {
        AccountStore.shared.namespacedKey(appLearningGoalPracticedDaysKey)
    }
    private var weekKey: String {
        AccountStore.shared.namespacedKey(appLearningGoalWeekIndexKey)
    }

    // MARK: - Init

    init() {
        load()
        refreshForCurrentWeekIfNeeded()
    }

    // MARK: - Wochen-Rechnung

    /// Fortlaufender Wochen-Index, Montag als Wochenstart.
    ///
    /// `currentDayIndex` 0 entspricht dem 1.1.1970 (ein Donnerstag), daher
    /// der Versatz von 4 Tagen: `dayIndex % 7 == 4` ist ein Montag.
    static var currentWeekIndex: Int {
        weekIndex(forDay: GamificationConfig.currentDayIndex)
    }

    static func weekIndex(forDay dayIndex: Int) -> Int {
        floorDiv(dayIndex - mondayOffset, 7)
    }

    private static let mondayOffset = 4

    /// Abrundende Division, die auch bei negativen Werten korrekt ist —
    /// Swifts `/` schneidet Richtung Null ab und würde vor 1970 eine
    /// Woche verschieben.
    private static func floorDiv(_ lhs: Int, _ rhs: Int) -> Int {
        let q = lhs / rhs
        return (lhs % rhs < 0) ? q - 1 : q
    }

    // MARK: - Ziel setzen / ändern

    /// Schreibt einen neuen Plan (Onboarding-Abschluss oder späteres
    /// Ändern). Der Wochenfortschritt bleibt dabei **erhalten** — wer
    /// mitten in der Woche sein Ziel anpasst, soll nicht die bereits
    /// geübten Tage verlieren.
    func setPlan(_ newPlan: LearningGoalPlan) {
        plan = newPlan
        persist()
    }

    /// Nur den Wochenrhythmus ändern, Inhaltsziel unangetastet.
    func updateWeeklyTarget(_ days: Int) {
        guard var current = plan else { return }
        current.weeklyTargetDays = LearningGoalPlan.clampWeeklyTarget(days)
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
    }

    /// Setzt die Listen eines Inhaltsziels neu (Mehrfachauswahl-Screen).
    func setLists(_ listIDs: [UUID]) {
        guard var current = plan, var content = current.content else { return }
        content.listIDs = listIDs
        current.content = content
        plan = current
        persist()
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
    /// ohne es als „gescheitert" zu markieren. Das Rhythmusziel bleibt
    /// bestehen — der Nutzer fällt also nie in einen ziellosen Zustand.
    func archiveContentGoal() {
        guard var current = plan, let content = current.content else { return }
        archivedContentGoals.append(content)
        current.content = nil
        plan = current
        persist()
    }

    // MARK: - Aktivität buchen

    /// Markiert heute als „geübt". Wird zentral am Session-Ende gerufen —
    /// idempotent, mehrfaches Aufrufen am selben Tag zählt einmal.
    func recordPracticeToday() {
        refreshForCurrentWeekIfNeeded()
        let today = GamificationConfig.currentDayIndex
        guard !practicedDayIndices.contains(today) else {
            #if DEBUG
            print("🎯 [Ziel] Heute (\(today)) war schon gebucht — Woche bleibt bei \(practicedDayIndices.count)/\(rhythmProgress.targetDays)")
            #endif
            return
        }
        practicedDayIndices.insert(today)
        persist()
        #if DEBUG
        let p = rhythmProgress
        print("🎯 [Ziel] Tag \(today) gebucht → Woche \(p.practicedDays)/\(p.targetDays)"
              + (p.isReached ? " ✅ Wochenziel erreicht!" : " (noch \(p.remainingDays))"))
        #endif
    }

    /// Idempotenter Wochen-Rollover. Öffentlich, damit Screens beim
    /// Erscheinen synchronisieren können, falls die App über einen
    /// Wochenwechsel hinweg im Hintergrund lag.
    func refreshForCurrentWeekIfNeeded() {
        let current = Self.currentWeekIndex
        guard current != weekIndex else { return }
        weekIndex = current
        practicedDayIndices = []
        persist()
    }

    // MARK: - Fortschritt

    /// Fortschritt des Rhythmusziels in der laufenden Woche.
    /// Ohne Plan wird der Default-Rhythmus angenommen, damit die UI immer
    /// eine sinnvolle Zahl bekommt.
    var rhythmProgress: WeeklyRhythmProgress {
        let target = plan?.weeklyTargetDays ?? LearningGoalPlan.defaultWeeklyTargetDays
        return WeeklyRhythmProgress(
            practicedDays: practicedDayIndices.count,
            targetDays: target
        )
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

    /// Löscht **nur** den Wochenfortschritt, lässt das Ziel selbst stehen.
    ///
    /// Das ist der Pfad für „Spielstand zurücksetzen": Der Plan ist ein
    /// Nutzerdatum wie Profil und Vorname (die dort ebenfalls verschont
    /// bleiben), die geübten Tage sind Spielstand wie Streak und
    /// Tages-Counter. Wer seinen Spielstand zurücksetzt, will nicht
    /// nebenbei sein Lernziel verlieren und das Onboarding neu machen.
    func resetWeeklyProgress() {
        practicedDayIndices = []
        weekIndex = Self.currentWeekIndex
        persist()
    }

    /// Setzt das **gesamte** Ziel-System zurück, inklusive Plan und
    /// Archiv. Nur für den destruktiven Pfad (Account löschen / alle
    /// Nutzerdaten verwerfen) — nach diesem Aufruf hat der Nutzer kein
    /// Ziel mehr und muss die Ziel-Auswahl erneut durchlaufen.
    func reset() {
        plan = nil
        archivedContentGoals = []
        practicedDayIndices = []
        weekIndex = Self.currentWeekIndex
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

        weekIndex = defaults.object(forKey: weekKey) as? Int ?? Self.currentWeekIndex
        let stored = defaults.array(forKey: practicedDaysKey) as? [Int] ?? []
        practicedDayIndices = Set(stored)
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

        defaults.set(weekIndex, forKey: weekKey)
        defaults.set(Array(practicedDayIndices), forKey: practicedDaysKey)
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
        weeklyTargetDays: Int = 3,
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
        setPlan(LearningGoalPlan(weeklyTargetDays: weeklyTargetDays, content: content))
        debugDumpState()
    }

    /// Bucht künstlich zurückliegende Tage der laufenden Woche, um den
    /// Balken ohne echtes Üben zu füllen.
    func debugAddPracticedDays(_ count: Int) {
        refreshForCurrentWeekIfNeeded()
        let today = GamificationConfig.currentDayIndex
        for offset in 0..<max(0, count) {
            practicedDayIndices.insert(today - offset)
        }
        persist()
        debugDumpState()
    }

    /// Schreibt den kompletten Zielzustand in die Konsole — inklusive
    /// Inhalts-Fortschritt, wenn ein `listStore` mitgegeben wird.
    func debugDumpState(listStore: VocabularyListStore? = nil) {
        print("──────── 🎯 Ziel-Status ────────")
        guard let plan else {
            print("  Kein Ziel gesetzt (Onboarding noch nicht durchlaufen).")
            print("  Rhythmus-Default greift: \(rhythmProgress.practicedDays)/\(rhythmProgress.targetDays)")
            print("────────────────────────────────")
            return
        }

        let r = rhythmProgress
        print("  Woche #\(weekIndex) — geübt an \(r.practicedDays) von \(r.targetDays) Tagen"
              + (r.isReached ? "  ✅" : "  (noch \(r.remainingDays))"))
        print("  Gebuchte Tages-Indizes: \(practicedDayIndices.sorted())")

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
            print("  Kein Inhaltsziel — reines Rhythmusziel.")
        }
        print("  Archiv: \(archivedContentGoals.count) abgeschlossene(s) Ziel(e)")
        print("────────────────────────────────")
    }
}
#endif
