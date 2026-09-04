import Foundation

/// Session-Resume für das Quiz-Modul. Anders als Training/Akzente hat Quiz
/// keine Speed-Round-Variante — jede angefangene Runde ist grundsätzlich
/// resumable. Was wir persistieren:
/// • die komplette Fragen-Queue (inkl. generierter Distraktoren/Matchings/
///   Lückensätze), damit der User bei Fortsetzen **dieselben Fragen** noch
///   einmal sieht und nicht eine frisch gewürfelte Runde bekommt,
/// • Index der aktuellen Frage,
/// • bisherige Treffer-Ergebnisse (`answeredResults`),
/// • Setup-Kontext für Fingerprint-Check (Direction, Listen, Anzahl-Option).
///
/// Quiz-Fragen sind seit `QuizQuestion: Codable` direkt serialisierbar —
/// Matching, Fill-Blanks usw. kommen samt Distraktoren-Shuffle zurück.
struct QuizSessionResumeState: Codable, Equatable {

    // MARK: Setup-Kontext

    var directionRaw: String
    var selectedListIDs: [UUID]
    var questionCountOptionRaw: Int

    // MARK: Session-Content

    var questions: [QuizQuestion]
    var currentQuestionIndex: Int
    var answeredResults: [Bool]

    // MARK: Gamification

    var streak: SessionStreak

    // MARK: Metadata

    var configFingerprint: String
    var lastUpdatedEpoch: TimeInterval
}

// MARK: - Store

enum QuizSessionResumeStore {

    /// Legacy-Filename (pre-Phase E.4). Bleibt als Fallback für die
    /// Erst-Migration — neue Writes gehen in den account-scoped Slot.
    private static let legacyFileName = "quiz-session-resume-v1.json"

    /// **Per-Account-Filename** (Phase E.4): jeder Account hält seinen
    /// eigenen Resume-Snapshot. Switch zwischen Accounts verschüttet
    /// keine laufenden Sessions — jede Identität taucht in ihrem
    /// eigenen Zustand wieder auf. @MainActor, weil `AccountStore`
    /// MainActor-isoliert ist — alle Save-/Load-Call-Sites laufen
    /// ohnehin auf Main (SwiftUI-View-Flow).
    @MainActor
    private static var fileName: String {
        if let id = AccountStore.shared.currentAccountID {
            return "quiz-session-resume-v1-\(id.uuidString).json"
        }
        return legacyFileName
    }

    /// Synchrone Save-API — für Cleanup-Pfade. Hot-Path nutzt
    /// `scheduleSave(_:)` (debounced Background-Write). @MainActor,
    /// weil fileName den MainActor-isolierten `AccountStore` liest;
    /// alle Call-Sites laufen in SwiftUI-View-Code auf Main.
    @MainActor
    static func save(_ state: QuizSessionResumeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        AppPersistenceSupport.writeData(data, named: fileName)
    }

    private static var pendingSaveItem: DispatchWorkItem?

    @MainActor
    static func scheduleSave(_ state: QuizSessionResumeState) {
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
    static func load() -> QuizSessionResumeState? {
        guard let data = AppPersistenceSupport.readData(named: fileName) else { return nil }
        return try? JSONDecoder().decode(QuizSessionResumeState.self, from: data)
    }

    @MainActor
    static func clear() {
        pendingSaveItem?.cancel()
        pendingSaveItem = nil
        AppPersistenceSupport.removeData(named: fileName)
    }

    /// Stabiler Fingerprint — Direction + Listen + Fragenanzahl. Beim
    /// Start-Versuch im Setup wird dieser gebildet und gegen den Snapshot
    /// verglichen; bei Abweichung wird der Snapshot verworfen und eine
    /// frische Runde gebaut. Version-Präfix `v1:` erlaubt späteren
    /// Format-Wechsel ohne inkompatible Altsnapshots versehentlich zu
    /// matchen.
    static func fingerprint(
        direction: String,
        selectedListIDs: [UUID],
        questionCountOptionRaw: Int
    ) -> String {
        let sortedIDs = selectedListIDs
            .map { $0.uuidString }
            .sorted()
            .joined(separator: ",")
        return "v1:\(direction)|\(questionCountOptionRaw)|\(sortedIDs)"
    }
}
