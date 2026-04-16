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

    /// Konfiguriert die Audio-Session für lauten Output über den Lautsprecher.
    ///
    /// Knackpunkt: Wenn der TTS-Speaker (`Speaker.swift`) zuvor lief, hat er
    /// `.playAndRecord` gesetzt und beim Ende `setActive(false)` aufgerufen.
    /// In dem Zustand routet iOS Audio standardmäßig zur Earpiece (winzig
    /// leise) — der `.defaultToSpeaker` Override gilt nur, solange der
    /// Speaker den setCategory-Call selbst macht.
    ///
    /// Lösung:
    /// • Wenn Session aktuell auf `.playAndRecord` steht (Recording läuft
    ///   evtl. noch oder wurde nur deaktiviert), explizit
    ///   `overrideOutputAudioPort(.speaker)` setzen — das routet jeden
    ///   weiteren Output zum lauten Speaker, OHNE die Recording-Pipeline
    ///   zu beenden.
    /// • Sonst: `.playback` setzen (geht von Haus aus über Speaker, ist die
    ///   richtige Category für Vordergrund-Audio).
    /// • Vor jedem Play `setActive(true)`, weil der Speaker die Session
    ///   nach jedem Sprechakt deaktiviert.
    private func ensureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            if session.category == .playAndRecord {
                // Recording-Modus aktiv (oder kürzlich aktiv) → Output explizit
                // auf Speaker zwingen, sonst spielt der Sound über die
                // Earpiece und wirkt deutlich leiser als TTS.
                try session.setActive(true)
                try session.overrideOutputAudioPort(.speaker)
            } else {
                // Normaler Vordergrund-Audio-Pfad: laute Playback-Category.
                if session.category != .playback {
                    try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                }
                try session.setActive(true)
            }
        } catch {
            print("⚠️ [Sound] Audio-Session konnte nicht aktiviert werden: \(error)")
        }
    }

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
