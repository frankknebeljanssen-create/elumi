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
    /// Aktive Fade-Timer pro Music-Resource. Wird in
    /// `fadeStopMusic(resource:over:)` zu- und abgebaut.
    private var musicFadeTimers: [String: Timer] = [:]

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

    // MARK: - Music API
    //
    // Die Music-Methoden brechen gezielt mit den SFX-Konventionen von
    // `play(_:)` / `loop(_:)`:
    //   • kein `elumi_`-Prefix (Music-Files heißen frei),
    //   • beliebige Extension (MP3 für Musik, WAV bleibt SFX-Default),
    //   • mit optionalem Fade-Out statt hartem Stop.
    //
    // So landet **alles** Audio-Loading (Bundle-URL, AVAudioSession,
    // AVAudioPlayer-Setup) weiterhin an einer Stelle — kein paralleler
    // Loader. Music-spezifische Orchestrierung (Track-Alternation,
    // Volume-Policy) lebt darüber in `WordRunnerMusicPlayer`.

    /// Startet ein Musik-File als Endlos-Loop. `resource`
    /// **ohne** Extension. Handle zum späteren Stop/Fade ist schlicht
    /// der Resource-Name.
    func playMusic(resource: String, ext: String = "mp3", volume: Float = 0.55) {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            print("⚠️ [Music] Missing: \(resource).\(ext)")
            return
        }
        ensureAudioSession()
        do {
            // Alten Player mit demselben Key beenden — keine zwei
            // Loops gleichzeitig auf derselben Ressource.
            players[resource]?.stop()

            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = volume
            player.prepareToPlay()
            player.play()
            players[resource] = player
            #if DEBUG
            print("🎵 [Music] playing \(resource).\(ext) (loop, vol=\(volume))")
            #endif
        } catch {
            print("⚠️ [Music] Playback failed for \(resource): \(error)")
        }
    }

    /// Stoppt ein Musik-File sofort (hart).
    /// Bricht zusätzlich einen eventuell laufenden Fade-Timer für
    /// dieselbe Resource ab — ohne das würde der Ghost-Fade weiter
    /// gegen einen `nil`-Player ticken (keine Funktion, nur Overhead),
    /// und der `onComplete`-Hook könnte ggf. noch feuern. Mit diesem
    /// Fix ist `stopMusic` wirklich sofort + final.
    func stopMusic(resource: String) {
        musicFadeTimers[resource]?.invalidate()
        musicFadeTimers[resource] = nil
        players[resource]?.stop()
        players[resource] = nil
    }

    /// Fadet ein Musik-File über `duration` Sekunden linear auf 0 und
    /// beendet dann den Player. `onComplete` läuft auf dem MainActor,
    /// nachdem das File stillgelegt wurde.
    ///
    /// Wiederholter Aufruf während eines laufenden Fades ist
    /// idempotent — der alte Timer wird verworfen, ein neuer startet
    /// von der aktuellen Volume-Position aus.
    func fadeStopMusic(resource: String, over duration: TimeInterval, onComplete: (() -> Void)? = nil) {
        guard let player = players[resource], player.isPlaying else {
            onComplete?()
            return
        }
        // Alten Fade canceln, falls aktiv (via Key pro Resource).
        musicFadeTimers[resource]?.invalidate()
        musicFadeTimers[resource] = nil

        let startVolume = player.volume
        let effectiveDuration = max(duration, 0.05)
        let fadeStart = Date()
        let steps: TimeInterval = 0.05

        let timer = Timer.scheduledTimer(withTimeInterval: steps, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            Task { @MainActor in
                let elapsed = Date().timeIntervalSince(fadeStart)
                let t = min(1.0, elapsed / effectiveDuration)
                self.players[resource]?.volume = startVolume * Float(1.0 - t)
                if t >= 1.0 {
                    timer.invalidate()
                    self.musicFadeTimers[resource] = nil
                    self.players[resource]?.stop()
                    self.players[resource] = nil
                    onComplete?()
                }
            }
        }
        musicFadeTimers[resource] = timer
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
