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

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode)
        utterance.rate = rate
        utterance.pitchMultiplier = pitchMultiplier
        utterance.volume = volume
        utterance.preUtteranceDelay = 0
        utterance.postUtteranceDelay = 0
        synth.speak(utterance)
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
