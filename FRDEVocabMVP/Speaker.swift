import SwiftUI
import AVFoundation

@MainActor
final class Speaker: NSObject, ObservableObject, @preconcurrency AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false

    private let synth = AVSpeechSynthesizer()
    private let audioSession = AVAudioSession.sharedInstance()

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(
        text: String,
        languageCode: String,
        rate: Float = 0.48,
        pitchMultiplier: Float = 1.0,
        volume: Float = 0.82
    ) {
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false

        do {
            try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .duckOthers])
            try audioSession.setActive(true)
        } catch {
            // If session setup fails, continue with speech synthesis anyway.
        }

        let utterance = AVSpeechUtterance(string: Self.spokenText(from: text))
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        utterance.rate = rate
        utterance.pitchMultiplier = pitchMultiplier
        utterance.volume = volume
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        synth.speak(utterance)
    }

    /// Normalisiert den Input für TTS. Wichtigster Punkt: Alternativ-Slashes /
    /// Pipes („le/la", „un|une") durch Komma ersetzen, damit die Stimme eine
    /// kurze Pause macht und die Wörter nicht zu einem einzigen zusammenklebt.
    /// Ohne diesen Schritt spricht AVSpeechSynthesizer entweder „Schrägstrich"
    /// aus oder quetscht die Tokens zu einem unverständlichen Wort.
    private static func spokenText(from text: String) -> String {
        var result = text
        for separator in ["/", "\u{FF0F}", "|"] {
            result = result.replacingOccurrences(of: separator, with: ", ")
        }
        // Mehrfache Leerzeichen und doppelte Kommata einsammeln, die bei Text
        // wie „le / la" oder „le/,la" entstehen können.
        result = result.replacingOccurrences(
            of: #"\s*,\s*,\s*"#,
            with: ", ",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func stop() {
        guard synth.isSpeaking || isSpeaking else { return }
        synth.stopSpeaking(at: .immediate)
        isSpeaking = false
        deactivatePlaybackSession()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }

    private func deactivatePlaybackSession() {
        try? audioSession.setActive(false, options: .notifyOthersOnDeactivation)
    }
}
