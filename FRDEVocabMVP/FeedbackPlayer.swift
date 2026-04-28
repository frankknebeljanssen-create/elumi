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
    /// Preloaded Music-Player (Phase 7.6). Halten AVAudioPlayer +
    /// `prepareToPlay`-Buffer bereit, damit `playMusic` ohne
    /// Decoder-Anlauf startet. Key = Resource-Name ohne Extension.
    private var preloadedMusicPlayers: [String: AVAudioPlayer] = [:]
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
    ///
    /// **Phase 7.6** — jetzt `internal` (vorher private), damit Views
    /// die Session explizit vor einem Musik-Start warm-up'en können
    /// (User-Report „Elumi-Musik startet erst nach SFX-Trigger").
    func ensureAudioSession() { ensureAudioSessionInternal() }

    private func ensureAudioSessionInternal() {
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
        ensureAudioSession()
        // **Pending-Fade-Killer** (Phase 7.6): jeder ggf. laufende
        // Fade für **diese** Resource wird hier abgebrochen, bevor
        // der neue Player lebt. Sonst kann ein bereits-dispatcher
        // Task vom alten Fade den Volume des neuen Players gleich
        // wieder auf 0 setzen — Effekt: Musik spielt theoretisch,
        // ist aber stumm, und klingt erst nach ein paar Sekunden
        // auf (User-Report „Musik startet spät").
        musicFadeTimers[resource]?.invalidate()
        musicFadeTimers[resource] = nil

        // Alten aktiven Player mit demselben Key beenden — keine zwei
        // Loops gleichzeitig auf derselben Resource.
        players[resource]?.stop()
        players[resource] = nil

        // **Preloaded-Player verwenden** (Phase 7.6 Bug-Fix: Silent-
        // Playback läuft bereits bei Volume 0). Wir setzen nur den
        // Volume auf den echten Wert — die Engine streamt schon, die
        // ersten Samples kommen **sofort** hörbar an. Keine neue
        // `play()`-Schicht, die Decode-Buffer füllen müsste.
        if let preloaded = preloadedMusicPlayers[resource] {
            preloadedMusicPlayers[resource] = nil
            if !preloaded.isPlaying {
                // Defensiv: falls der preloaded Player zwischenzeitlich
                // gestoppt wurde, nochmal starten.
                preloaded.play()
            }
            preloaded.volume = volume
            players[resource] = preloaded
            #if DEBUG
            print("🎵 [Music] playing (preloaded-silent→audible) \(resource) vol=\(volume)")
            #endif
            return
        }

        // Normal-Pfad: Player frisch erzeugen.
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            print("⚠️ [Music] Missing: \(resource).\(ext)")
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = volume
            player.prepareToPlay()
            player.play()
            // Doppelt Volumen setzen — manche iOS-Versionen
            // übernehmen `volume` nur nach `play()` sauber.
            player.volume = volume
            players[resource] = player
            #if DEBUG
            print("🎵 [Music] playing \(resource).\(ext) (loop, vol=\(volume))")
            #endif
        } catch {
            print("⚠️ [Music] Playback failed for \(resource): \(error)")
        }
    }

    /// **Silent-Playback-Preload** (Phase 7.6 Bug-Fix für „Musik
    /// startet Sekunden später"). Statt nur `prepareToPlay()` starten
    /// wir den Player **tatsächlich bei Volume 0** — die Audio-Engine
    /// ist damit vollständig aktiv (Session live, Buffer voll, Player
    /// im Loop). Beim späteren `playMusic()` setzen wir nur den
    /// Volume auf den echten Wert, ohne einen zweiten Pipeline-Setup
    /// zu erzwingen.
    ///
    /// Warum das Problem vorher nicht zuverlässig weg war: iOS fährt
    /// die Audio-Engine bei Inaktivität teilweise zurück. `play()` auf
    /// einem frisch erstellten Player muss dann Session re-activate,
    /// Buffer füllen und Decode starten — das kann mehrere Sekunden
    /// dauern, bis die ersten Samples ankommen. Ein bereits laufender
    /// (silent) Player umgeht das.
    ///
    /// Mehrfach-Aufrufe für dieselbe Resource sind idempotent.
    func preloadMusic(resource: String, ext: String = "mp3") {
        guard let url = Bundle.main.url(forResource: resource, withExtension: ext) else {
            print("⚠️ [Music] Preload missing: \(resource).\(ext)")
            return
        }
        ensureAudioSession()
        // Schon vorbereitet? Nichts zu tun.
        if preloadedMusicPlayers[resource] != nil { return }
        // Liegt bereits als aktiver Player vor? Auch nichts zu tun.
        if players[resource] != nil { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.numberOfLoops = -1
            player.volume = 0
            player.prepareToPlay()
            // **Silent-Playback starten** — Engine wirklich anwerfen.
            player.play()
            preloadedMusicPlayers[resource] = player
            #if DEBUG
            print("🎵 [Music] preloaded+playing-silent \(resource).\(ext)")
            #endif
        } catch {
            print("⚠️ [Music] Preload failed for \(resource): \(error)")
        }
    }

    /// Stoppt ein Musik-File sofort (hart).
    /// Bricht zusätzlich einen eventuell laufenden Fade-Timer für
    /// dieselbe Resource ab — ohne das würde der Ghost-Fade weiter
    /// gegen einen `nil`-Player ticken (keine Funktion, nur Overhead),
    /// und der `onComplete`-Hook könnte ggf. noch feuern. Mit diesem
    /// Fix ist `stopMusic` wirklich sofort + final.
    ///
    /// **Phase 7.6 Bug-Fix 2** (Fish-Overlap): stopMusic nukt jetzt
    /// auch preloaded-silent-Player für dieselbe Resource. Sonst
    /// würde ein Silent-Playback (Volume 0, aber Engine aktiv)
    /// gegen den neu gestarteten Track rennen und theoretisch zu
    /// zwei parallelen Playern führen, sobald ein fadeTimer Volume
    /// in unerwartete Richtung dreht.
    func stopMusic(resource: String) {
        musicFadeTimers[resource]?.invalidate()
        musicFadeTimers[resource] = nil
        players[resource]?.stop()
        players[resource] = nil
        // **Preloaded-Player bewusst NICHT hier stoppen** — sonst
        // würde `stopAllTracks` bei einem Track-Wechsel den
        // Silent-Preload zerstören, den `playMusic` direkt danach
        // für dieselbe Resource wieder braucht. Nur `dropPreload`
        // räumt Preloaded-Player explizit weg, z. B. bei echtem
        // Track-Wechsel (Fish-Event).
    }

    /// **Preload-Cleanup** (Phase 7.6) — entfernt einen silent-
    /// gehaltenen Player für eine Resource. Wird von ArcadeMusic-
    /// Player genutzt, wenn ein anderer Track gestartet wird
    /// (z. B. beim Übergang zur Fischrunde), damit das Silent-
    /// Playback der alten Resource nicht neben dem neuen Track
    /// hängt.
    func dropPreload(resource: String) {
        preloadedMusicPlayers[resource]?.volume = 0
        preloadedMusicPlayers[resource]?.stop()
        preloadedMusicPlayers[resource] = nil
    }

    /// **Nuke-Option** (Phase 7.6 Bug-2 Hardening): stoppt **jeden**
    /// aktiven + preloaded Music-Player, **unabhängig** davon ob der
    /// Resource-Key im `MusicCatalog` gelistet ist. Wird von
    /// ArcadeMusicPlayer bei Fish-Event + Run-Start aufgerufen, damit
    /// es keine Zombie-Player gibt, die parallel weiterlaufen.
    ///
    /// Optionales `keepPreloadFor` erhält einen Silent-Preload für
    /// den Track, der gleich als nächstes gespielt werden soll — so
    /// bleibt der Bug-1-Fix (sofortiger Musikstart) erhalten.
    func stopAllMusic(keepPreloadFor preserved: String? = nil) {
        for (key, player) in players {
            musicFadeTimers[key]?.invalidate()
            musicFadeTimers[key] = nil
            player.volume = 0
            player.stop()
        }
        players.removeAll()

        for (key, player) in preloadedMusicPlayers where key != preserved {
            player.volume = 0
            player.stop()
        }
        if let preserved = preserved {
            let keep = preloadedMusicPlayers[preserved]
            preloadedMusicPlayers.removeAll()
            if let keep { preloadedMusicPlayers[preserved] = keep }
        } else {
            preloadedMusicPlayers.removeAll()
        }

        #if DEBUG
        print("🛑 [Music] stopAllMusic (keep preload: \(preserved ?? "none"))")
        #endif
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
                // **Race-Guard** (Bug-Fix: „Elumi-Start nur kurzer
                // Noise dann nichts"): Zwischen dem Timer-Fire und
                // dem MainActor-Hop kann `stopMusic` den Fade-Timer
                // bereits invalidiert und einen **neuen** Player
                // unter derselben Resource-Key gespeichert haben. Wenn
                // wir dann `players[resource]?.volume = 0` setzen,
                // drehen wir den frischen Track stumm.
                //
                // Lösung: Nur weitermachen, wenn der aktuelle
                // `musicFadeTimers[resource]` **genau dieser** Timer
                // ist. Sonst: abgelöst → abbrechen.
                guard self.musicFadeTimers[resource] === timer else { return }
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
