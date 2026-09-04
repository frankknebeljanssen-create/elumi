import Foundation
import AVFoundation

/// **SpeechVoiceService (Phase 9.1, dynamic)** — vollständig gerät-
/// basierte Stimmen-Auflösung. Keine hart kodierten Stimmen-Namen
/// mehr.
///
/// Aufgabe:
///   1. Zur Laufzeit via `AVSpeechSynthesisVoice.speechVoices()` alle
///      tatsächlich installierten Apple-Stimmen scannen.
///   2. Pro Sprache (Deutsch/Französisch) eine sortierte Liste liefern
///      — Qualität absteigend (premium > enhanced > default), dann
///      alphabetisch.
///   3. Die beste verfügbare Stimme als „empfohlen" ausweisen — nicht
///      über einen festen Namen, sondern über Qualitätsrang.
///   4. Eine `VoiceSelectionRecord`-persistierte User-Wahl zu einer
///      konkreten `AVSpeechSynthesisVoice` auflösen, mit sauberer
///      Fallback-Chain (Identifier → beste verfügbare Stimme gleicher
///      Sprache → Systemstandard der Sprache → nil).
@MainActor
final class SpeechVoiceService: ObservableObject {
    static let shared = SpeechVoiceService()

    /// Alle installierten Voices, gruppiert nach Sprache und in
    /// Qualitäts-Reihenfolge. Wird beim Init + jedem `refresh()`
    /// neu aufgebaut.
    @Published private(set) var germanOptions: [VoiceOption] = []
    @Published private(set) var frenchOptions: [VoiceOption] = []

    private init() {
        rebuild()
    }

    // MARK: - Refresh

    /// Aktualisiert die Voice-Listen. Aufgerufen beim App-Start, beim
    /// onAppear der Stimme-View, beim Scene-Phase → .active (User
    /// zurück aus iPhone-Settings) und manuell per „Verfügbarkeit
    /// erneut prüfen".
    func refresh() {
        rebuild()
    }

    private func rebuild() {
        let all = AVSpeechSynthesisVoice.speechVoices()
        germanOptions = buildOptions(for: .german, from: all)
        frenchOptions = buildOptions(for: .french, from: all)
    }

    private func buildOptions(for language: ElumiSpeechLanguage, from all: [AVSpeechSynthesisVoice]) -> [VoiceOption] {
        let filtered = all.filter { voice in
            // Akzeptiere `de-*` bzw. `fr-*` — iOS liefert für einige
            // Stimmen regionale Varianten („de-AT", „fr-CA"), die wir
            // pragmatisch in den jeweiligen Sprachtopf werfen.
            voice.language.hasPrefix(language.bcpPrefix + "-")
                || voice.language == language.bcpPrefix
        }
        let mapped = filtered.map { VoiceOption(voice: $0, language: language) }
        // Sortierung: Qualität absteigend, dann alphabetisch stabil.
        let sorted = mapped.sorted { lhs, rhs in
            if lhs.qualityRank != rhs.qualityRank {
                return lhs.qualityRank > rhs.qualityRank
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        // Systemstandard hängt IMMER unten als Fallback-Auswahl.
        return sorted + [VoiceOption.systemDefault(for: language)]
    }

    // MARK: - Lookup / Recommended

    func options(for language: ElumiSpeechLanguage) -> [VoiceOption] {
        switch language {
        case .german: return germanOptions
        case .french: return frenchOptions
        }
    }

    /// Die aktuell beste **konkrete** Stimme pro Sprache. Systemstandard
    /// ist nie „empfohlen". Bei mehreren gleich-premium Stimmen gewinnt
    /// die erste nach Sortier-Reihenfolge (alphabetisch).
    func recommendedOption(for language: ElumiSpeechLanguage) -> VoiceOption? {
        options(for: language)
            .first { !$0.isSystemDefault }
    }

    /// Gibt es mindestens eine Stimme mit Enhanced- oder Premium-Quality
    /// auf dem Gerät — überhaupt, über beide Sprachen hinweg? Steuert
    /// das „Bessere Stimmen laden"-Banner.
    var hasAnyHighQualityVoice: Bool {
        let all = germanOptions + frenchOptions
        return all.contains { option in
            guard let q = option.quality else { return false }
            return q == .enhanced || q == .premium
        }
    }

    /// Ist in einer bestimmten Sprache eine Enhanced/Premium-Stimme
    /// vorhanden?
    func hasHighQualityVoice(for language: ElumiSpeechLanguage) -> Bool {
        options(for: language).contains { option in
            guard let q = option.quality else { return false }
            return q == .enhanced || q == .premium
        }
    }

    // MARK: - Resolver

    /// Findet die konkrete `AVSpeechSynthesisVoice` aus einem
    /// Persistenz-Record. Fallback-Chain:
    ///   1. Exakter `identifier` → voll qualifizierter Treffer
    ///   2. Identifier nicht (mehr) installiert → beste verfügbare
    ///      Stimme derselben Sprache
    ///   3. Keine Stimme → `AVSpeechSynthesisVoice(language: <code>)`
    ///   4. Nichts → nil (System wählt Default der System-Locale)
    func resolvedVoice(forRecord record: VoiceSelectionRecord?) -> AVSpeechSynthesisVoice? {
        guard let record else {
            return nil
        }
        // 1) System-Sentinel → Systemstandard der Sprache.
        if record.identifier == VoiceOption.systemDefaultID {
            return AVSpeechSynthesisVoice(language: record.language.languageCode)
        }
        // 2) Identifier direkt auflösen.
        if let byID = AVSpeechSynthesisVoice(identifier: record.identifier) {
            return byID
        }
        // 3) Beste verfügbare Stimme der Sprache.
        if let best = recommendedOption(for: record.language),
           let voice = AVSpeechSynthesisVoice(identifier: best.identifier) {
            return voice
        }
        // 4) Systemstandard der Sprache.
        return AVSpeechSynthesisVoice(language: record.language.languageCode)
    }

    /// Gibt die **User-Wahl** als Option zurück (auch wenn nicht mehr
    /// installiert — dann aus dem Record rekonstruiert mit Display-
    /// Name „Gewählt" + Sprache).
    func selectedOption(forRecord record: VoiceSelectionRecord?, language: ElumiSpeechLanguage) -> VoiceOption {
        guard let record else {
            return .systemDefault(for: language)
        }
        if record.identifier == VoiceOption.systemDefaultID {
            return .systemDefault(for: language)
        }
        // Wenn installiert → aus der Liste ziehen.
        if let existing = options(for: language).first(where: { $0.identifier == record.identifier }) {
            return existing
        }
        // Nicht mehr installiert → Platzhalter-Option mit gespeichertem
        // Identifier + „uninstalled"-Marker. Wir haben den Display-Namen
        // verloren, zeigen „Stimme nicht mehr verfügbar" an.
        return VoiceOption(
            identifier: record.identifier,
            language: language,
            displayName: "Stimme nicht mehr verfügbar",
            quality: nil
        )
    }

    /// Liefert die **tatsächlich** zum Rendern genutzte Option (Resolver-
    /// Ergebnis als Option-Wrapper). Ist der `identifier` der User-Wahl
    /// nicht auflösbar, wird die beste verfügbare Stimme derselben
    /// Sprache zurückgegeben; fallbackt weiter auf Systemstandard.
    func effectiveOption(forRecord record: VoiceSelectionRecord?, language: ElumiSpeechLanguage) -> VoiceOption {
        guard let record else {
            return .systemDefault(for: language)
        }
        if record.identifier == VoiceOption.systemDefaultID {
            return .systemDefault(for: language)
        }
        // Wunsch vorhanden → direkt zurück.
        if let existing = options(for: language).first(where: { $0.identifier == record.identifier }) {
            return existing
        }
        // Sonst: beste verfügbare Stimme der Sprache.
        if let fallback = recommendedOption(for: language) {
            return fallback
        }
        // Nichts da → Systemstandard.
        return .systemDefault(for: language)
    }

    /// Convenience für View-Call-Sites: resolvedVoice für eine Sprache,
    /// greift auf den `VoiceSettingsStore` zu.
    func resolvedVoice(for language: ElumiSpeechLanguage) -> AVSpeechSynthesisVoice? {
        let record = VoiceSettingsStore.shared.record(for: language)
        return resolvedVoice(forRecord: record)
    }

    /// User-facing Beschreibung der tatsächlich genutzten Stimme.
    func effectiveVoiceDescription(for language: ElumiSpeechLanguage) -> String {
        let record = VoiceSettingsStore.shared.record(for: language)
        let effective = effectiveOption(forRecord: record, language: language)
        if effective.isSystemDefault {
            return "Systemstandard"
        }
        // Wunsch und Effektiv identisch? → nur Name. Sonst „X (Fallback
        // auf Y)" gibt dem User klarere Feedback — matcht UI-Block
        // „Aktuell verwendet".
        let selected = selectedOption(forRecord: record, language: language)
        if selected.identifier == effective.identifier {
            return effective.displayName
        }
        return "\(effective.displayName) (bis \(selected.displayName) verfügbar ist)"
    }
}
