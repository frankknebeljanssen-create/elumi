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

    private static let fileName = "quiz-session-resume-v1.json"

    /// Synchrone Save-API — für Cleanup-Pfade. Hot-Path nutzt
    /// `scheduleSave(_:)` (debounced Background-Write).
    static func save(_ state: QuizSessionResumeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        AppPersistenceSupport.writeData(data, named: fileName)
    }

    private static var pendingSaveItem: DispatchWorkItem?

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

    static func load() -> QuizSessionResumeState? {
        guard let data = AppPersistenceSupport.readData(named: fileName) else { return nil }
        return try? JSONDecoder().decode(QuizSessionResumeState.self, from: data)
    }

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
