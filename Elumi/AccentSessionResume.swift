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

    private static let legacyFileName = "accent-session-resume-v1.json"

    /// Per-Account-Filename (Phase E.4). Fallback auf Legacy-Name,
    /// solange kein Account aktiv ist. @MainActor — `AccountStore` ist
    /// MainActor-isoliert; alle Save-/Load-Sites laufen eh auf Main.
    @MainActor
    private static var fileName: String {
        if let id = AccountStore.shared.currentAccountID {
            return "accent-session-resume-v1-\(id.uuidString).json"
        }
        return legacyFileName
    }

    /// Synchrone Save-API — für Cleanup-Pfade. Der Engine nutzt im
    /// Hot-Path `scheduleSave(_:)` (debounced Background-Write, siehe
    /// `TrainingSessionResumeStore` für das identische Muster).
    @MainActor
    static func save(_ state: AccentSessionResumeState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        AppPersistenceSupport.writeData(data, named: fileName)
    }

    private static var pendingSaveItem: DispatchWorkItem?

    @MainActor
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

    @MainActor
    static func load() -> AccentSessionResumeState? {
        guard let data = AppPersistenceSupport.readData(named: fileName) else { return nil }
        return try? JSONDecoder().decode(AccentSessionResumeState.self, from: data)
    }

    @MainActor
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
    ///
    /// **v2 (2026-09-03)** — Präfix-Bump wegen der strikten Listen-
    /// Bindung in `AccentContentBuilder`. Snapshots aus der Zeit davor
    /// können mit Built-in-Wörtern aufgefüllt sein, die gar nicht in der
    /// gewählten Liste stehen. Der neue Präfix lässt solche Altsnapshots
    /// beim Fingerprint-Check durchfallen — sie werden verworfen und die
    /// Runde frisch (und listenrein) aufgebaut.
    static func fingerprint(mode: AccentMode, selectedListID: UUID?) -> String {
        "v2:\(mode.rawValue)|\(selectedListID?.uuidString ?? "<none>")"
    }
}
