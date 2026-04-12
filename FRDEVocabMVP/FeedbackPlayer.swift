import SwiftUI
import AVFoundation

@MainActor
struct SoundToggleToast: Equatable {
    let message: String
    let systemImage: String
}

@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()
    private var players: [String: AVAudioPlayer] = [:]

    private func ensureAudioSession() {
        if !isSessionActive {
            do {
                try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)
                isSessionActive = true
            } catch {}
        }
    }
    private var isSessionActive = false

    func play(_ name: String, volume: Float = 1.0) {
        guard let url = Bundle.main.url(forResource: "elumi_\(name)", withExtension: "wav") else {
            print("⚠️ [Sound] Missing: elumi_\(name).wav")
            return
        }
        ensureAudioSession()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = volume
            player.play()
            players[name] = player
        } catch {
            print("⚠️ [Sound] Error playing \(name): \(error)")
        }
    }

    func loop(_ name: String, volume: Float = 1.0, rate: Float = 1.0) {
        guard let url = Bundle.main.url(forResource: "elumi_\(name)", withExtension: "wav") else {
            print("⚠️ [Sound] Missing: elumi_\(name).wav")
            return
        }
        ensureAudioSession()
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = volume
            if rate != 1.0 {
                player.enableRate = true
                player.rate = rate
            }
            player.play()
            players[name] = player
        } catch {
            print("⚠️ [Sound] Error looping \(name): \(error)")
        }
    }

    func stop(_ name: String) {
        players[name]?.stop()
        players[name] = nil
    }

    func stopAll() {
        players.values.forEach { $0.stop() }
        players.removeAll()
    }
}

@MainActor
final class FeedbackPlayer: ObservableObject {
    private let soundsEnabledKey = "FRDEVocabMVP.soundsEnabled.v1"
    @Published var areSoundsEnabled: Bool = true {
        didSet {
            UserDefaults.standard.set(areSoundsEnabled, forKey: soundsEnabledKey)
            if !areSoundsEnabled {
                stopAllFeedback()
            }
        }
    }
    @Published var soundToggleToast: SoundToggleToast?

    // BGM uses AVAudioEngine (programmatic buffer, too large for WAV)
    var engine: AVAudioEngine?
    var bgmPlayerNode: AVAudioPlayerNode?
    let audioSession = AVAudioSession.sharedInstance()
    let sampleRate: Double = 44_100
    lazy var bgmBuffer: AVAudioPCMBuffer? = makeBGMBuffer()
    var isBGMConfigured = false

    var soundToastDismissWorkItem: DispatchWorkItem?

    let sp = SoundPlayer.shared

    init() {
        if UserDefaults.standard.object(forKey: soundsEnabledKey) != nil {
            areSoundsEnabled = UserDefaults.standard.bool(forKey: soundsEnabledKey)
        }
    }
}
