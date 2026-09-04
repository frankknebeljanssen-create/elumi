import Foundation

/// Session-Resume für das **normale** Training (Vokabeln / Nomen / Artikel /
/// Verben — **nicht** Speed Round). Der Snapshot wird nach jeder Antwort
/// und beim Laden der nächsten Karte geschrieben, bei Session-Ende oder
/// inkompatibler Konfiguration gelöscht. Beim Start-Versuch prüft
/// `TrainingSessionController.startTraining`, ob ein passender Snapshot
/// vorliegt und restored direkt in den letzten Stand.
///
/// Designentscheidungen:
/// • **Items werden voll persistiert** (nicht nur IDs) — `VocabularyItem`
///   ist bereits `Codable`. Das macht uns unabhängig davon, ob zwischen
///   zwei Sessions Listen-IDs rotieren (z. B. Lexikon-Auffüllung).
/// • **Config-Fingerprint** (Modus + Direction + CardType + Liste-Set)
///   entscheidet, ob ein Snapshot zur aktuellen Setup-Konfiguration passt.
///   Ein Modus-Wechsel oder Listen-Update verwirft den Snapshot stumm.
/// • **Kein User-Prompt** — MVP-Vorgabe: direkt fortsetzen.
/// • **Speed Round wird nie gespeichert** — der Call-Site im Controller
///   prüft `isSpeedRound` und ruft in dem Fall `clear()` statt `save()`.
struct TrainingSessionResumeState: Codable, Equatable {

    // MARK: - Setup-Kontext (für Fingerprint + spätere Restore-Plausibilität)

    var trainingModeRaw: String
    var directionRaw: String
    var cardTypeRaw: String
    /// Sortierte List-IDs (stable hash für Fingerprint).
    var selectedListIDs: [UUID]

    // MARK: - Session-Content

    /// Vollständige Item-Reihenfolge der aktuellen Runde, nachdem sie
    /// einmal geshuffled wurde. Wird beim Restore 1:1 in
    /// `preparedTrainingItems` zurückgeschrieben, damit der Deck-Rest auch
    /// bei mehrfachem Resume identisch bleibt.
    var preparedItems: [VocabularyItem]

    /// Noch offene Items (in Reihenfolge) — beim Restore zurück in
    /// `remainingTrainingItems`.
    var remainingItems: [VocabularyItem]

    /// Gerade sichtbare Karte (falls Session unterbrochen wurde, während
    /// eine Karte auf der Anzeige war).
    var currentItem: VocabularyItem?

    /// Fehlversuche auf der aktuellen Karte — für die First-Attempt-Streak-
    /// Regel wichtig (retry-corrects brechen die Serie ab).
    var failedAttemptsOnCurrentCard: Int

    /// Wie viele Runden (= volle Durchläufe der prepared-Queue) wurden
    /// abgeschlossen? Spiegelt `TrainingSessionController.completedRound`.
    var completedRound: Int

    // MARK: - Gamification

    var sessionCorrectCount: Int
    var sessionWrongCount: Int
    var streak: SessionStreak

    // MARK: - Metadata

    /// Fingerprint über den Setup-Kontext — verwirft den Snapshot, wenn
    /// der Nutzer zwischen zwei Sessions Modus oder Listen wechselt.
    var configFingerprint: String

    /// Zeitstempel des letzten Save-Calls — für spätere Staleness-Checks
    /// (aktuell nicht ausgewertet, aber gespeichert, damit ein Cleanup
    /// später nachgerüstet werden kann ohne Migration).
    var lastUpdatedEpoch: TimeInterval
}

// MARK: - Store

/// Dateibasierte Persistenz für den Training-Resume-Snapshot. Landet im
/// `AppPersistenceSupport`-Persistence-Ordner; ein einziger Key appweit,
/// modus-agnostisch (Vokabel/Nomen/Artikel/Verben teilen sich einen
/// Eintrag — nur die **aktive** Session wird gespeichert). Kein
/// UserDefaults-Legacy, weil es vorher nichts gab.
enum TrainingSessionResumeStore {

    private static let legacyFileName = "training-session-resume-v1.json"

    /// Per-Account-Filename (Phase E.4). Fallback auf Legacy-Name,
    /// solange kein Account aktiv ist. @MainActor — `AccountStore` ist
    /// MainActor-isoliert; alle Save-/Load-Sites laufen eh auf Main.
    @MainActor
    private static var fileName: String {
        if let id = AccountStore.shared.currentAccountID {
            return "training-session-resume-v1-\(id.uuidString).json"
        }
        return legacyFileName
    }

    // MARK: Save / Load / Clear

    /// Synchrone Save-API — bleibt erhalten für Cleanup-Pfade, in denen
    /// sofortige Persistenz wichtig ist (z. B. bei App-Terminate).
    /// Für den Hot-Path (recordAnswer, loadNextTrainingCard) nutzt der
    /// Controller `scheduleSave(_:)` mit Background-Write + Debounce —
    /// spart ~5–15 ms pro Antwort auf dem Main-Thread.
    @MainActor
    static func save(_ state: TrainingSessionResumeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        AppPersistenceSupport.writeData(data, named: fileName)
    }

    /// Debounced Background-Save. Sammelt Mutations für 400 ms, schreibt
    /// dann **einen** JSON-File auf einer Utility-Queue. Parallele
    /// Scheduler-Aufrufe cancelen vorherige pendings, so dass nur der
    /// zuletzt geplante State landet.
    private static var pendingSaveItem: DispatchWorkItem?

    @MainActor
    static func scheduleSave(_ state: TrainingSessionResumeState) {
        pendingSaveItem?.cancel()
        let targetName = fileName
        let item = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(state) else { return }
            AppPersistenceSupport.writeData(data, named: targetName)
        }
        pendingSaveItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    @MainActor
    static func load() -> TrainingSessionResumeState? {
        guard let data = AppPersistenceSupport.readData(named: fileName) else { return nil }
        return try? JSONDecoder().decode(TrainingSessionResumeState.self, from: data)
    }

    @MainActor
    static func clear() {
        // Pending Save canceln — sonst könnte ein verspäteter Write den
        // gerade geklärten Snapshot wieder rausschreiben.
        pendingSaveItem?.cancel()
        pendingSaveItem = nil
        AppPersistenceSupport.removeData(named: fileName)
    }

    // MARK: Fingerprint

    /// Stabiler Fingerprint über die Konfiguration einer Training-Session —
    /// wenn sich einer der Inputs zwischen zwei Sessions ändert, wird der
    /// Snapshot verworfen. Listen-IDs werden sortiert, damit sich die
    /// Reihenfolge der Auswahl nicht auf das Ergebnis auswirkt.
    ///
    /// Version-Präfix (`v1:`) macht den Fingerprint-Algorithmus selbst
    /// Teil des Keys. Wenn wir künftig zusätzliche Felder einrechnen oder
    /// das Format ändern (z. B. JSON-Hash statt String-Konkat), erhöhen
    /// wir den Präfix — alte Snapshots matchen dann automatisch nicht
    /// mehr und werden beim nächsten Setup stumm verworfen.
    static func fingerprint(
        mode: String,
        direction: String,
        cardType: String,
        selectedListIDs: [UUID]
    ) -> String {
        let sortedIDs = selectedListIDs
            .map { $0.uuidString }
            .sorted()
            .joined(separator: ",")
        return "v1:\(mode)|\(direction)|\(cardType)|\(sortedIDs)"
    }
}
