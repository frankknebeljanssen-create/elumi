import Foundation
import Combine

// MARK: - ⚠️ DEPRECATED — Removal-Backlog
//
// **2026-04-30, Branch `feature/training-session-flow`, Stufe 1**:
// Persistent-Wrapper um `GeneratedTrainingSession` (out of
// `TrainingGenerator.generate`). Mit dem Chain-Builder-Pfad
// (`TrainingChainContext.make(from:slotResult)`) ist die Persistenz
// einer „letzten generierten Session" überflüssig — die Chain selbst
// ist In-Memory und überlebt App-Restart bewusst nicht.
//
// Verifikation 2026-04-30: einzige Live-Call-Sites waren
// `ElumiTabView.swift:48` (@StateObject) + `:1196` (storeSession) —
// beide entfernt. Keine weiteren Referenzen im Code.
//
// Removal mit `TrainingGenerator.swift` und `TrainingGeneratorModels.swift`
// als gemeinsamer Backlog-Item nach Merge des Chain-Branches.

/// **Training-Generator-Store** — persistiert die zuletzt generierte
/// Session, die zuletzt gewählte Dauer und den zuletzt gewählten Fokus
/// in UserDefaults. Singleton, weil Screen + Tab-Card beide lesen und
/// nur die View schreibt.
@MainActor
final class TrainingGeneratorStore: ObservableObject {
    static let shared = TrainingGeneratorStore()

    @Published private(set) var lastSession: GeneratedTrainingSession?
    @Published var lastDuration: Int {
        didSet { UserDefaults.standard.set(lastDuration, forKey: Self.durationKey) }
    }
    @Published var lastFocus: TrainingFocus {
        didSet { UserDefaults.standard.set(lastFocus.rawValue, forKey: Self.focusKey) }
    }

    private init() {
        self.lastDuration = Self.loadDuration()
        self.lastFocus = Self.loadFocus()
        self.lastSession = Self.loadSession()
    }

    // MARK: - Public API

    /// Merkt sich die übergebene Session und persistiert sie direkt.
    func storeSession(_ session: GeneratedTrainingSession) {
        lastSession = session
        saveSession(session)
    }

    /// Löscht die gemerkte Session — z. B. wenn der User den Generator
    /// verlässt und nicht gestartet hat, oder nach Abschluss. V1 nutzt
    /// das noch nicht aktiv, ist aber für spätere Cleanup-Pfade da.
    func clearSession() {
        lastSession = nil
        UserDefaults.standard.removeObject(forKey: Self.sessionKey)
    }

    // MARK: - Persistence

    private static let sessionKey = "elumi.trainingGenerator.lastSession.v1"
    private static let durationKey = "elumi.trainingGenerator.lastDuration.v1"
    private static let focusKey = "elumi.trainingGenerator.lastFocus.v1"

    private static let defaultDuration = 10

    private static func loadSession() -> GeneratedTrainingSession? {
        guard let data = UserDefaults.standard.data(forKey: sessionKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(GeneratedTrainingSession.self, from: data)
    }

    private static func loadDuration() -> Int {
        let raw = UserDefaults.standard.integer(forKey: durationKey)
        return [5, 10, 15, 20].contains(raw) ? raw : defaultDuration
    }

    private static func loadFocus() -> TrainingFocus {
        guard let raw = UserDefaults.standard.string(forKey: focusKey),
              let parsed = TrainingFocus(rawValue: raw) else {
            return .mixed
        }
        return parsed
    }

    private func saveSession(_ session: GeneratedTrainingSession) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data = try encoder.encode(session)
            UserDefaults.standard.set(data, forKey: Self.sessionKey)
        } catch {
            print("⚠️ TrainingGeneratorStore encode failed: \(error)")
        }
    }
}
