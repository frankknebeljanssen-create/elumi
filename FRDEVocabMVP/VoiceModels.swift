import Foundation
import AVFoundation

/// **Voice-System Phase 9.1 (dynamic)** — vollständig geräteabhängige
/// Stimmenauflösung. KEINE hart kodierten Namen (Vicki/Yannick/Thomas)
/// mehr — der `SpeechVoiceService` scannt zur Laufzeit, was auf dem
/// iPhone tatsächlich installiert ist, und baut daraus die Auswahl-
/// Liste. Die App speichert lediglich den `AVSpeechSynthesisVoice.identifier`
/// der User-Wahl, plus den Sprach-Code als Fallback-Anker, falls der
/// Identifier später nicht mehr auflösbar ist (Stimme deinstalliert).

/// Sprachen, die Elumi aktiv bedient.
enum ElumiSpeechLanguage: String, Codable, CaseIterable, Identifiable, Hashable {
    case german
    case french

    var id: String { rawValue }

    /// BCP-47-Sprachcode für die jeweilige Region.
    var languageCode: String {
        switch self {
        case .german: return "de-DE"
        case .french: return "fr-FR"
        }
    }

    /// Kurzpräfix für Sprachfilterung (voice.language prüft auf
    /// `.starts(with:)`, weil iOS manchmal „de-AT" o. Ä. zurückgibt
    /// und wir auch diese Varianten als „deutsch" akzeptieren).
    var bcpPrefix: String {
        switch self {
        case .german: return "de"
        case .french: return "fr"
        }
    }

    var displayName: String {
        switch self {
        case .german: return "Deutsch"
        case .french: return "Französisch"
        }
    }
}

/// Dynamisch erzeugte Stimmen-Option. Entweder eine konkrete, auf dem
/// Gerät installierte `AVSpeechSynthesisVoice` (identifiziert über
/// `identifier`) oder der sprachspezifische „Systemstandard" (Sentinel-
/// ID `VoiceOption.systemDefaultID`).
///
/// Die User-Wahl wird **nur** über den `identifier` persistiert. Beim
/// Laden resolved der `SpeechVoiceService` diesen gegen die aktuell
/// installierten Stimmen; ist er nicht mehr da, fällt die App auf die
/// beste verfügbare Stimme derselben Sprache zurück.
struct VoiceOption: Identifiable, Equatable, Hashable {
    /// Sentinel-Identifier für „Systemstandard". Nicht-leer + eindeutig,
    /// damit Codable-Persistenz sauber funktioniert.
    static let systemDefaultID = "__elumi.voice.system_default__"

    /// `AVSpeechSynthesisVoice.identifier` oder `systemDefaultID`.
    let identifier: String
    let language: ElumiSpeechLanguage
    let displayName: String
    /// Rohquality-Stufe der Apple-Stimme. nil für Systemstandard.
    let quality: AVSpeechSynthesisVoiceQuality?

    var id: String { identifier }

    var isSystemDefault: Bool {
        identifier == VoiceOption.systemDefaultID
    }

    /// User-facing Qualitätsbadge — „Premium" / „Enhanced" / „Standard"
    /// / „Systemstimme". Nur für den Einstellungs-UI-Chip genutzt.
    var qualityBadge: String? {
        guard let quality else { return nil }
        switch quality {
        case .premium:  return "Premium"
        case .enhanced: return "Enhanced"
        case .default:  return "Standard"
        @unknown default: return nil
        }
    }

    /// Stabiler Rang für Qualitätssortierung. Höher = besser.
    var qualityRank: Int {
        guard let quality else { return 0 } // Systemstandard unten
        switch quality {
        case .premium:  return 3
        case .enhanced: return 2
        case .default:  return 1
        @unknown default: return 1
        }
    }

    /// Convenience-Factory für den Systemstandard-Eintrag pro Sprache.
    static func systemDefault(for language: ElumiSpeechLanguage) -> VoiceOption {
        VoiceOption(
            identifier: systemDefaultID,
            language: language,
            displayName: "Systemstandard",
            quality: nil
        )
    }

    /// Baut eine Option aus einer realen `AVSpeechSynthesisVoice`-Instanz.
    init(voice: AVSpeechSynthesisVoice, language: ElumiSpeechLanguage) {
        self.identifier = voice.identifier
        self.language = language
        self.displayName = voice.name
        self.quality = voice.quality
    }

    /// Raw-Initializer (privater Gebrauch für den Systemstandard).
    init(identifier: String, language: ElumiSpeechLanguage, displayName: String, quality: AVSpeechSynthesisVoiceQuality?) {
        self.identifier = identifier
        self.language = language
        self.displayName = displayName
        self.quality = quality
    }
}

/// **Persistenz-Snapshot** (Codable): Identifier plus Sprache. Sprache
/// dient als Fallback-Anker, falls der Identifier nicht mehr existiert
/// — dann sucht der Resolver die beste verfügbare Stimme **derselben
/// Sprache**.
struct VoiceSelectionRecord: Codable, Equatable {
    let identifier: String
    let language: ElumiSpeechLanguage
}
