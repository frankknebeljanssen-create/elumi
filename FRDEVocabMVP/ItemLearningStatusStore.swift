import Foundation
import SwiftUI

/// App-weiter Per-Item-Lernstatus-Store.
///
/// Zweck: über **alle** Module hinweg (Karteikarten, Training, Verbformen,
/// Quiz) pro Vokabel-Eintrag zählen, wie viele Versuche richtig/falsch
/// waren — damit die Home-Card und der Detail-Screen anzeigen können,
/// welche Einträge schon sitzen (`.strong`), welche noch Aufmerksamkeit
/// brauchen (`.needsWork`) und welche noch zu wenig Signal haben
/// (`.sparse`).
///
/// **Identität über UUIDs ist unzuverlässig**, weil `VocabularyItem.id`
/// pro Init neu vergeben wird (siehe `StudyDomainModels+Vocabulary.swift`)
/// und verschiedene Codepfade (Dictionary-Generierung, Scan-Import, Quiz-
/// Merge, Flashcard-Deck-Aufbau) dieselbe logische Vokabel mehrfach mit
/// unterschiedlichen UUIDs instanziieren. Deshalb nutzt der Store einen
/// **kanonisierten Text-Schlüssel** aus `(french, german, cardType)` —
/// genauer: den lowercased-getrimmten Varianten beider Sprachen plus dem
/// `CardType.rawValue` („Wörter" / „Phrasen").
///
/// **Persistenz**: File-basiert über `AppPersistenceSupport` statt
/// `UserDefaults`, weil das Dictionary mit der Zeit wächst (in der
/// Größenordnung einige Kilobytes bis niedrige zweistellige Megabytes)
/// und in `UserDefaults` unnötig laden/sync'en würde. Datei:
/// `item-learning-status.v1.json` im App-Support-`Persistence`-Ordner.
///
/// **Thread-Modell**: `@MainActor`. Alle Module-Hooks laufen ohnehin auf
/// dem MainActor (SwiftUI-View-Flow), und die Schreiblast ist klein
/// (eine Antwort = eine Mutation), daher kein Nebenläufigkeits-Overhead
/// nötig.
@MainActor
final class ItemLearningStatusStore: ObservableObject {
    /// Singleton-Zugriff — spart das Durchreichen durch jede View-Hierarchie.
    /// Die 4 Module-Hooks rufen direkt `ItemLearningStatusStore.shared.record...`.
    static let shared = ItemLearningStatusStore()

    /// Alle bekannten Einträge, indexiert nach kanonisiertem Schlüssel.
    /// `@Published`, damit Home-Card und Detail-Screen live reagieren,
    /// sobald während einer Session eine neue Antwort eingeht.
    @Published private(set) var statuses: [String: ItemLearningStatus] = [:]

    /// Globaler Legacy-Filename (pre-Phase E.3). Bleibt als Fallback
    /// für die Erst-Migration in den ersten Account liegen; danach
    /// liest/schreibt der Store ausschließlich per-Account.
    private let legacyFileName = "item-learning-status.v1.json"

    /// **Per-Account-Filename** (Phase E.3): der Account-UUID ist
    /// Teil des Dateinamens, damit jeder Account seinen eigenen
    /// Lernstatus-Blob hat. Fallback auf den globalen Namen, falls
    /// noch kein Account aktiv ist (z. B. Erst-Install vor Onboarding).
    private var fileName: String {
        if let id = AccountStore.shared.currentAccountID {
            return "item-learning-status.v1-\(id.uuidString).json"
        }
        return legacyFileName
    }

    init() {
        load()

        // Auf Account-Switches hören — Lernstatus des neuen Accounts
        // laden. Weak-Self, damit die Subscription das Singleton nicht
        // künstlich am Leben hält (hier zwar ohnehin singleton, aber
        // korrekter Stil spart späteres Refactoring).
        NotificationCenter.default.addObserver(
            forName: AccountStore.didSwitchAccount,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadForCurrentAccount()
            }
        }
    }

    /// **Phase E.3** — invalidiert den in-memory-State und lädt den
    /// Lernstatus des aktuell aktiven Accounts. Views, die auf
    /// `statuses` binden, aktualisieren automatisch.
    func reloadForCurrentAccount() {
        statuses = [:]
        load()
    }

    // MARK: - Persistenz

    private func load() {
        let activeName = fileName
        // Erster Load für den Per-Account-File: wenn dort nichts
        // liegt, aber der globale Legacy-File existiert, übernehmen
        // wir dessen Inhalt einmalig — ohne Datenverlust beim ersten
        // Start nach App-Update (Pre-Phase-E-Daten lebten global).
        // Danach nur noch aus dem Per-Account-File lesen.
        if let data = AppPersistenceSupport.readData(named: activeName),
           let decoded = try? JSONDecoder().decode([String: ItemLearningStatus].self, from: data) {
            statuses = decoded
            return
        }

        // Per-Account-File leer/fehlt → Legacy-Fallback versuchen.
        // `activeName != legacyFileName` schützt vor Endlos-Schleife,
        // falls kein Account aktiv ist (dann ist fileName = legacy).
        if activeName != legacyFileName,
           let legacyData = AppPersistenceSupport.readData(named: legacyFileName),
           let legacy = try? JSONDecoder().decode([String: ItemLearningStatus].self, from: legacyData) {
            statuses = legacy
            #if DEBUG
            appDebugLog("📦 [LearningStatus] first-time per-account load — seeded from legacy file (\(legacy.count) entries)")
            #endif
            // Sofort in den Per-Account-File schreiben, damit der
            // Legacy-Fallback nur einmal greift.
            persist()
        }
    }

    /// Debounce-Token für `persist()`. Bei schneller Antwort-Sequenz
    /// wird der Write so lange gedrückt, bis 400 ms keine weitere
    /// Mutation mehr kommt. Verhindert 1×Write pro Tap auf dem Main-
    /// Thread und spart bei 50-Antwort-Sessions ~40–50 File-Writes.
    private var pendingPersistItem: DispatchWorkItem?

    /// Schedule-API für das Schreiben. Alle Mutations-Pfade rufen hier
    /// rein (statt `persist()` direkt). Der eigentliche Write läuft in
    /// einem Background-Task — das Encoding selbst ist dadurch nicht
    /// mehr Main-Thread-blockierend.
    private func schedulePersist() {
        pendingPersistItem?.cancel()
        let snapshot = statuses
        let targetName = fileName
        let item = DispatchWorkItem {
            // Background-Queue — Encoding + File-Write passieren off-main.
            // `statuses` wird beim Planen gesnapshottet, damit die
            // Hintergrund-Operation auf einem konsistenten Wert arbeitet
            // und nicht mit laufenden Mutationen kollidiert.
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            AppPersistenceSupport.writeData(data, named: targetName)
        }
        pendingPersistItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    /// Synchrone Variante — bleibt als API erhalten, falls ein Caller
    /// sicher stellen will, dass der aktuelle Stand sofort auf der
    /// Platte liegt (z. B. vor App-Terminate). Call-Sites im Hot-Path
    /// sollten `schedulePersist()` nutzen.
    private func persist() {
        guard let data = try? JSONEncoder().encode(statuses) else { return }
        AppPersistenceSupport.writeData(data, named: fileName)
    }

    // MARK: - Mutation

    /// Registriert **eine** Antwort für den Eintrag
    /// `(french, german, cardType)`. Richtigkeit über `correct`.
    ///
    /// Leere/whitespace-only Strings werden defensive ignoriert — das
    /// passiert z. B. bei Quiz-Fill-Blanks, wo nur ein Wort im Blank
    /// steht und die Zuordnung zur Vokabel mehrdeutig wäre.
    ///
    /// Der Schlüssel wird aus den kanonisierten Eingaben gebaut; die
    /// Anzeige-Versionen (`displayFrench`/`displayGerman`) werden mit der
    /// zuletzt gesehenen **Original-Groß-Klein-Schreibung** aktualisiert,
    /// damit der Detail-Screen „Apfel" und nicht „apfel" zeigt.
    func recordAnswer(french: String, german: String, cardType: CardType, correct: Bool) {
        let key = Self.canonicalKey(french: french, german: german, cardType: cardType)
        // Früher: `guard !fr.isEmpty, !de.isEmpty` — hat silent **jedes**
        // Signal verworfen, bei dem eine der beiden Seiten leer war.
        // Das war ein Kern-Bug: Akzente tracked per french-only
        // (german: ""), manche Training-Pfade liefern einseitige Einträge.
        // Neue Regel: **mindestens eine** Seite muss Text haben → Eintrag
        // kommt in den Store. Wenn beide leer sind, ist der Call
        // fachlich sinnlos → dann droppen.
        guard !Self.canonicalText(french).isEmpty
           || !Self.canonicalText(german).isEmpty else {
            return
        }

        let trimmedFrench = french.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedGerman = german.trimmingCharacters(in: .whitespacesAndNewlines)

        var entry = statuses[key] ?? ItemLearningStatus(
            key: key,
            displayFrench: trimmedFrench,
            displayGerman: trimmedGerman,
            cardType: cardType,
            correctCount: 0,
            wrongCount: 0,
            lastSeen: Date()
        )

        if correct {
            entry.correctCount += 1
        } else {
            entry.wrongCount += 1
        }
        entry.lastSeen = Date()
        entry.displayFrench = trimmedFrench
        entry.displayGerman = trimmedGerman

        statuses[key] = entry
        // Debounced Background-Write (vorher synchron auf Main-Thread).
        // Bei schneller Antwort-Sequenz kollabiert das ~40 Writes pro
        // Session auf ~1–3 — messbar weniger Main-Thread-Last zwischen
        // Taps, ohne dass Lernstatus-Persistenz spürbar verzögert wird.
        schedulePersist()
    }

    // MARK: - Abgeleitete Listen für Home-Card & Detail-Screen

    var strongItems: [ItemLearningStatus] {
        statuses.values
            .filter { $0.status == .strong }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    var learningItems: [ItemLearningStatus] {
        statuses.values
            .filter { $0.status == .learning }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    /// **Priorisiert nach Trefferquote** (niedrigste zuerst) — wer nur
    /// 30 % richtig hat, steht weiter oben als wer 55 % hat. Bei
    /// Gleichstand entscheidet `lastSeen` zugunsten der aktuelleren
    /// Einträge.
    var needsWorkItems: [ItemLearningStatus] {
        statuses.values
            .filter { $0.status == .needsWork }
            .sorted { lhs, rhs in
                if lhs.accuracy != rhs.accuracy { return lhs.accuracy < rhs.accuracy }
                return lhs.lastSeen > rhs.lastSeen
            }
    }

    var sparseItems: [ItemLearningStatus] {
        statuses.values
            .filter { $0.status == .sparse }
            .sorted { $0.lastSeen > $1.lastSeen }
    }

    var totalTracked: Int { statuses.count }

    /// **Wackelkandidaten (2026-08-04)** — alles außer `.strong`:
    /// `needsWork` + `learning` + `sparse`. Das ist der Bestand, aus dem
    /// die generierte Übungsliste „Meine Wackelkandidaten" gebaut wird
    /// (siehe `VocabularyListStore.rebuildWackelkandidatenList(from:)`).
    ///
    /// Reihenfolge bewusst: erst `needsWork` (nach Trefferquote, das am
    /// stärksten Hakende zuerst), dann `learning`, dann `sparse` — so
    /// steht beim Drill das Schwächste vorne.
    var wackelkandidatenItems: [ItemLearningStatus] {
        needsWorkItems + learningItems + sparseItems
    }

    /// Anzahl ohne Sort/Filter-Ketten — für Button-Sichtbarkeit & Label.
    var wackelkandidatenCount: Int {
        statuses.values.reduce(0) { $1.status == .strong ? $0 : $0 + 1 }
    }

    // MARK: - Reine Anzahl-Aggregate
    //
    // `strongItems.count` etc. würden immer den kompletten Filter + Sort
    // triggern — teuer, wenn die UI nur die Zahl braucht (Hero, Card).
    // Diese Counts laufen ohne Sort und geben direkt `Int`.

    var strongCount: Int {
        statuses.values.reduce(0) { $1.status == .strong ? $0 + 1 : $0 }
    }

    var learningCount: Int {
        statuses.values.reduce(0) { $1.status == .learning ? $0 + 1 : $0 }
    }

    var needsWorkCount: Int {
        statuses.values.reduce(0) { $1.status == .needsWork ? $0 + 1 : $0 }
    }

    var sparseCount: Int {
        statuses.values.reduce(0) { $1.status == .sparse ? $0 + 1 : $0 }
    }

    // MARK: - Canonicalization

    /// Kanonischer Schlüssel für den Store-Key. Aus
    /// `(french, german, cardType)`, robust gegen Casing/Trimmung/
    /// Satzend-Punktuation. Getrennt durch `|`, damit der Key auch bei
    /// komplexen Phrasen eindeutig bleibt.
    static func canonicalKey(french: String, german: String, cardType: CardType) -> String {
        "\(canonicalText(french))|\(canonicalText(german))|\(cardType.rawValue)"
    }

    /// Interne Text-Kanonisierung:
    ///   1. Trim whitespace/newlines
    ///   2. Lowercased (Locale-unabhängig — Unicode-Casing)
    ///   3. Entfernt abschließende Satz-Punktuation (`?!.`), die zwischen
    ///      Modulen nicht konsistent gesetzt wird (Quiz zeigt z. B. gern
    ///      ein Fragezeichen, Karteikarten nicht).
    ///   4. Erneutes Trim für den Fall, dass nach der Punktuations-
    ///      Entfernung ein führender/trailing Space übrigbleibt.
    ///
    /// Bewusst **keine** weitergehende Normalisierung (Diakritika-
    /// Stripping etc.) — „ça" und „ca" sollen verschiedene Einträge
    /// bleiben, sonst würden unterschiedliche Vokabeln kollidieren.
    static func canonicalText(_ text: String) -> String {
        var canonical = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        while let last = canonical.last, "?!.".contains(last) {
            canonical.removeLast()
        }

        return canonical.trimmingCharacters(in: .whitespaces)
    }
}
