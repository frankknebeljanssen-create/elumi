import Foundation
import Combine

/// **VoiceSettingsStore (Phase 9.1, dynamic)** — persistiert die User-
/// Wahl pro Sprache als `VoiceSelectionRecord` (Identifier + Sprache)
/// in UserDefaults. Keine hart kodierten Stimmen-Namen mehr.
///
/// Persistence-Form: JSON-Blob pro Key, damit der Identifier-String
/// UND der Sprach-Anker zusammen gespeichert werden — letzterer
/// wird vom Resolver für die Fallback-Chain gebraucht, falls der
/// Identifier später nicht mehr installiert ist.
///
/// Defaults: beide Sprachen starten auf `.systemDefault` — der
/// Resolver wählt dann automatisch die beste verfügbare Stimme,
/// ohne dass der User auf dem ersten App-Start eine Entscheidung
/// treffen muss.
@MainActor
final class VoiceSettingsStore: ObservableObject {
    static let shared = VoiceSettingsStore()

    @Published private(set) var germanRecord: VoiceSelectionRecord {
        didSet { persist(germanRecord, key: appVoiceGermanSelectionKey) }
    }
    @Published private(set) var frenchRecord: VoiceSelectionRecord {
        didSet { persist(frenchRecord, key: appVoiceFrenchSelectionKey) }
    }

    private init() {
        self.germanRecord = Self.load(key: appVoiceGermanSelectionKey, language: .german)
        self.frenchRecord = Self.load(key: appVoiceFrenchSelectionKey, language: .french)
    }

    // MARK: - Lookup

    func record(for language: ElumiSpeechLanguage) -> VoiceSelectionRecord {
        switch language {
        case .german: return germanRecord
        case .french: return frenchRecord
        }
    }

    func selectedOption(for language: ElumiSpeechLanguage) -> VoiceOption {
        SpeechVoiceService.shared.selectedOption(forRecord: record(for: language), language: language)
    }

    /// Setzt die User-Wahl für eine konkrete Option. Identifier wird
    /// persistiert, Sprach-Anker ebenfalls (aus der Option abgeleitet).
    func setSelection(_ option: VoiceOption) {
        let rec = VoiceSelectionRecord(identifier: option.identifier, language: option.language)
        switch option.language {
        case .german: germanRecord = rec
        case .french: frenchRecord = rec
        }
    }

    // MARK: - Persistence

    private func persist(_ record: VoiceSelectionRecord, key: String) {
        let encoder = JSONEncoder()
        do {
            let data = try encoder.encode(record)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            appDebugLog("⚠️ VoiceSettingsStore encode failed: \(error)")
        }
    }

    private static func load(key: String, language: ElumiSpeechLanguage) -> VoiceSelectionRecord {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            // Kein Eintrag: Default = Systemstandard. Der Resolver setzt
            // automatisch auf die beste verfügbare Stimme, wenn der User
            // nie eine bewusste Wahl trifft.
            return VoiceSelectionRecord(identifier: VoiceOption.systemDefaultID, language: language)
        }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(VoiceSelectionRecord.self, from: data),
           decoded.language == language {
            return decoded
        }
        // Migration/Corruption-Fallback: Systemstandard.
        return VoiceSelectionRecord(identifier: VoiceOption.systemDefaultID, language: language)
    }
}
