import Foundation

/// Session-Resume für das Akzent-Modul — beschränkt auf den **Üben-Modus**.
/// Lernen-Modus hat keinen Queue-Fortschritt (nur Karten-Durchblättern),
/// Speed Round wird bewusst nicht gespeichert (Timer-Runde, Fortsetzen
/// nach Unterbrechung verfälscht das Ergebnis — analog zum Training).
///
/// Was wir festhalten müssen:
/// • die komplette Exercise-Queue (inkl. Soft-Re-Insertions, damit der
///   didaktische Re-Loop durch Unterbrechung nicht verloren geht),
/// • den Index der nächsten Aufgabe,
/// • die bisherigen `AccentAnswerRecord`s (für das Ergebnis-Breakdown),
/// • den Re-Insertion-Count pro Exercise-ID (schützt gegen unbegrenzte
///   Wiederholungen bei wiederholt falschen Antworten).
///
/// Plus Metadaten (Listen-ID für Fingerprint, Timestamp).
struct AccentSessionResumeState: Codable, Equatable {

    // MARK: Setup-Kontext (Fingerprint)

    /// Nur `.uben` wird gespeichert — explizit als rawValue im Snapshot,
    /// damit ein späterer Decode zweifelsfrei feststellt, in welchem
    /// Modus der Snapshot entstand.
    var modeRaw: String

    /// Gewählte Liste beim Start. Wechselt der Nutzer zwischen zwei
    /// Akzent-Sessions die Liste, verwirft der Fingerprint den Snapshot.
    /// `nil` wenn keine Liste gewählt war (Standard-Wörter-Fallback).
    var selectedListID: UUID?

    // MARK: Session-Content

    var exercises: [AccentExercise]
    var currentIndex: Int
    var answerRecords: [AccentAnswerRecord]
    /// Map Exercise-ID → bereits genutzte Reinsertion-Slots. Spiegelt
    /// `AccentSessionEngine.reinsertionCountByID` 1:1.
    var reinsertionCountByID: [UUID: Int]

    // MARK: Metadata

    var configFingerprint: String
    var lastUpdatedEpoch: TimeInterval
}

// MARK: - Store

enum AccentSessionResumeStore {

    private static let fileName = "accent-session-resume-v1.json"

    /// Synchrone Save-API — für Cleanup-Pfade. Der Engine nutzt im
    /// Hot-Path `scheduleSave(_:)` (debounced Background-Write, siehe
    /// `TrainingSessionResumeStore` für das identische Muster).
    static func save(_ state: AccentSessionResumeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        AppPersistenceSupport.writeData(data, named: fileName)
    }

    private static var pendingSaveItem: DispatchWorkItem?

    static func scheduleSave(_ state: AccentSessionResumeState) {
        pendingSaveItem?.cancel()
        let targetName = fileName
        let item = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(state) else { return }
            AppPersistenceSupport.writeData(data, named: targetName)
        }
        pendingSaveItem = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.4, execute: item)
    }

    static func load() -> AccentSessionResumeState? {
        guard let data = AppPersistenceSupport.readData(named: fileName) else { return nil }
        return try? JSONDecoder().decode(AccentSessionResumeState.self, from: data)
    }

    static func clear() {
        pendingSaveItem?.cancel()
        pendingSaveItem = nil
        AppPersistenceSupport.removeData(named: fileName)
    }

    /// Stabiler Fingerprint — Modus + Listen-ID. Der Mode-Anteil ist
    /// redundant (wir speichern nur `.uben`), aber explizit im Fingerprint,
    /// damit spätere Mode-Erweiterungen hier klar greifen können.
    /// Version-Präfix `v1:` (wie Training/Quiz) ermöglicht späteren
    /// Format-Wechsel ohne inkompatible Altsnapshots fälschlich zu matchen.
    static func fingerprint(mode: AccentMode, selectedListID: UUID?) -> String {
        "v1:\(mode.rawValue)|\(selectedListID?.uuidString ?? "<none>")"
    }
}
