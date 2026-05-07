import Foundation
import AVFoundation
import AudioToolbox

/// **Slot-Machine Audio-Player** (Branch `feature/slot-machine-sounds`,
/// 2026-04-30).
///
/// Liefert Sound-Feedback für die Trainings-Generator-Slot-Machine im
/// Elumi-Tab:
///   • **Click** pro Reel-Symbol-Pass — kurzer Tick, synchron zur
///     Reel-Rotation. Mehrere Clicks können sich überlappen, deshalb
///     Player-Pool mit 5 vorgeladenen `AVAudioPlayer`-Instanzen.
///   • **Settle** beim Stillstand aller Reels (`phase == .landed`).
///   • **Win** beim Reveal mit ≥ 2 Game-Symbolen (kein Jackpot).
///   • **Jackpot** beim Reveal mit 3× Game (`elumiCount == 3`).
///
/// **Audio-File-Stand 2026-04-30**:
///   • **Click** = `elumi_toggle.wav` als **Placeholder** — der vom User
///     bereitgestellte `slot_machine_click_tick.wav` aus
///     `/mnt/user-data/uploads/` war im Sandbox-Build-Setup nicht
///     erreichbar. Der Toggle-Sound ist click-artig und überbrückt das,
///     bis das echte File ins Bundle kommt (Backlog-Item, dann nur
///     `clickResourceName` umstellen — Architektur unverändert).
///   • **Settle / Win / Jackpot** = `AudioServicesPlaySystemSound`-IDs
///     (1057 / 1025 / 1306) als Platzhalter — werden später durch echte
///     Sound-Files ersetzt (Backlog).
///
/// **Mute-Awareness**: liest `soundsEnabledKey` aus `UserDefaults`
/// (gleicher Key wie `FeedbackPlayer.areSoundsEnabled`), damit der
/// globale Sound-Toggle aus dem Footer respektiert wird. Pattern aus
/// `LanguageDirectionSwitch.swift:93`.
///
/// **Throttle für Click**: minimum-Interval von 60 ms zwischen Clicks
/// — bei voller Reel-Geschwindigkeit (30 Symbol-Passes/Sek.) würden
/// sonst alle Pool-Player permanent recyclen und ein Buzz statt
/// einzelner Ticks entstehen. 60 ms = max 16 Clicks/Sek., entspricht
/// realer Slot-Machine-Klangcharakteristik.
///
/// **2026-05-04 Off-Main-Refactor (Real-Device-Stutter-Fix):**
/// Vorher war die Klasse `@MainActor`-bound. Bei ~16 Hz Click-Rate
/// während eines Spins blockierten `player.isPlaying` /
/// `player.stop()` / `player.play()` (synchroner AudioToolbox-
/// Roundtrip, ~1–2 ms pro Call) das Main-Thread-Frame-Budget der
/// 60-fps-Reel-Animation. Auf Real-iPhone-Hardware war das als
/// Audio-Stutter hörbar (Sim mit Mac-Audio-Path nicht).
///
/// Jetzt: eigene Serial-Dispatch-Queue mit `qos: .userInteractive`.
/// `playClick()` dispatcht async, alle State-Mutationen
/// (`nextPlayerIndex`, `lastClickAt`, `player.play()`) laufen auf
/// dieser Queue, der Main-Thread bleibt frei.
///
/// Das frühere `if player.isPlaying { stop()/currentTime = 0 }`-
/// Cleanup ist entfallen — Pool-Rotation (5 Player) deckt Overlap
/// ab. Wenn alle 5 gleichzeitig laufen würden (extreme Reel-Speed,
/// in der Praxis durch 60-ms-Throttle nicht erreichbar), gibt's
/// gelegentliches Sound-Overlap statt einem synchronen Stop-
/// Roundtrip — akzeptabel, wirkt wie natürliches Casino-Echo.
final class SlotAudioPlayer {

    // MARK: - Singleton

    static let shared = SlotAudioPlayer()

    // MARK: - Konfiguration

    /// Resource-Name für den Click-Sound (ohne `.wav`-Extension).
    /// Echtes File `slot_reel_click.wav` (vom User in Branch
    /// `feature/slot-machine-sounds` 2026-04-30 geliefert), liegt in
    /// `Sounds/`. Der frühere Placeholder `elumi_toggle` ist abgelöst.
    private static let clickResourceName: String = "slot_reel_click"

    /// Größe des Click-Player-Pools. 5 Instanzen reichen für
    /// überlappende Clicks bei voller Reel-Geschwindigkeit.
    private static let poolSize: Int = 5

    /// Mindest-Intervall zwischen aufeinanderfolgenden Clicks. Schützt
    /// gegen Rapid-Fire-Buzz bei voller Reel-Geschwindigkeit.
    private static let clickThrottleSeconds: TimeInterval = 0.06

    /// Click-Volume (0.0–1.0). Bewusst gedämpft, damit der dichte
    /// Click-Stream nicht die anderen App-Sounds übertönt.
    /// **2026-05-02 Iter 2 (User-Befund weiterhin „click noise zu
    /// laut")**: 0.3 → 0.15 — nochmal halbiert. Bei 16 Clicks/Sek.
    /// (max via Throttle) summieren sich auch leise Einzelticks
    /// akustisch auf, der effektive Pegel ist deshalb deutlich höher
    /// als der `volume`-Wert vermuten lässt. 0.15 schließt zu den
    /// `AudioServicesPlaySystemSound`-Effekten (Settle/Win/Jackpot)
    /// auf, die keine Volume-Control haben und auf System-Lautstärke
    /// laufen — der Click-Stream ist jetzt Teil des Mix-Hintergrunds,
    /// nicht mehr Vordergrund-Vorder-Knaller.
    private static let clickVolume: Float = 0.15

    // MARK: - State (Queue-exklusiv)

    /// Audio-Queue für alle State-Mutationen + Player-Calls.
    /// `qos: .userInteractive` — Audio braucht ms-präzise Latenz, sonst
    /// klingt der Click-Stream wackelig. Serial, damit
    /// `nextPlayerIndex`/`lastClickAt` ohne explizites Lock konsistent
    /// bleiben.
    private let audioQueue = DispatchQueue(label: "com.frank.SlotAudio", qos: .userInteractive)

    /// Player-Pool. Wird in `init` einmalig befüllt (Main-Thread); im
    /// Hot-Path nur lesend per Index zugegriffen — Read-Only nach Init,
    /// thread-safe per memory-write-fence am Init-Ende.
    private var players: [AVAudioPlayer] = []
    /// Pool-Rotation-Cursor. Mutationen NUR auf `audioQueue`.
    private var nextPlayerIndex: Int = 0
    /// Throttle-State. Mutationen NUR auf `audioQueue`.
    private var lastClickAt: TimeInterval = 0

    // MARK: - Init

    private init() {
        loadPlayers()
    }

    /// Lädt `poolSize` AVAudioPlayer-Instanzen mit dem Click-Sample
    /// vor. Beim ersten `playClick()` ist alles bereit, kein
    /// Decoder-Anlauf in der Hot-Path.
    private func loadPlayers() {
        guard let url = Bundle.main.url(forResource: Self.clickResourceName, withExtension: "wav") else {
            appDebugLog("⚠️ [SlotAudio] Click-Resource '\(Self.clickResourceName).wav' fehlt im Bundle")
            return
        }
        for _ in 0..<Self.poolSize {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = Self.clickVolume
                player.prepareToPlay()
                players.append(player)
            } catch {
                appDebugLog("⚠️ [SlotAudio] Failed to preload click player: \(error)")
            }
        }
    }

    // MARK: - Mute-Awareness

    /// Liest den globalen Sound-Toggle aus `UserDefaults`. Gleicher Key
    /// wie `FeedbackPlayer.soundsEnabledKey` (dort `private`, daher
    /// hier inline gespiegelt — Pattern aus
    /// `LanguageDirectionSwitch.swift:92`). Default `true` (sounds an),
    /// wenn Key noch nie gesetzt wurde.
    /// `UserDefaults.standard` ist thread-safe per Apple-Doc — direkter
    /// Read auf der Audio-Queue ohne Lock zulässig.
    private var soundsEnabled: Bool {
        let key = "FRDEVocabMVP.soundsEnabled.v1"
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil { return true }
        return defaults.bool(forKey: key)
    }

    // MARK: - Public API

    /// Spielt einen einzelnen Reel-Click ab. Throttled — bei rapid
    /// successive Aufrufen werden Aufrufe < 60 ms nach dem letzten
    /// Click ignoriert. Player-Pool rotiert; bei extremer Rate kommt
    /// es zu Sound-Overlap (akzeptabel — wirkt wie Casino-Echo).
    ///
    /// **Off-Main:** Caller (z.B. Spin-Timer-Body in `SlotMachineView`)
    /// dispatcht hier nur eine Queue-Async-Submission — kein
    /// synchroner Audio-Roundtrip auf Main.
    func playClick() {
        guard soundsEnabled else { return }
        let now = Date().timeIntervalSinceReferenceDate
        audioQueue.async { [weak self] in
            guard let self else { return }
            guard now - self.lastClickAt >= Self.clickThrottleSeconds else { return }
            self.lastClickAt = now

            guard !self.players.isEmpty else { return }
            let player = self.players[self.nextPlayerIndex]
            self.nextPlayerIndex = (self.nextPlayerIndex + 1) % self.players.count
            // Kein synchroner Stop mehr — Pool-Rotation deckt Overlap
            // ab. Bei extremer Reel-Speed gibt's gelegentlich
            // Sound-Overlap statt synchronem Stop-Roundtrip
            // (Real-Device-Stutter-Fix 2026-05-04).
            player.play()
        }
    }

    /// Spielt den Settle-Sound bei `phase == .landed`. Aktuell
    /// System-Sound 1057 (Tink) als Platzhalter.
    /// `AudioServicesPlaySystemSound` ist thread-safe per Apple-Doc;
    /// dispatch zur Konsistenz auf die Audio-Queue (= alle
    /// Slot-Audio-Calls auf einem Thread, klare Ordering-Semantik).
    func playSettle() {
        guard soundsEnabled else { return }
        audioQueue.async {
            AudioServicesPlaySystemSound(1057)
        }
    }

    /// Spielt den Win-Sound bei Reveal mit ≥ 2 Game-Symbolen (außer
    /// Jackpot). System-Sound 1025 als Platzhalter.
    func playWin() {
        guard soundsEnabled else { return }
        audioQueue.async {
            AudioServicesPlaySystemSound(1025)
        }
    }

    /// Spielt den Jackpot-Sound bei Reveal mit 3× Game. System-Sound
    /// 1306 als Platzhalter — wird in Stufe 6 (Branch
    /// `feature/training-session-flow`) durch echtes Feuerwerk-Sound
    /// ersetzt.
    func playJackpot() {
        guard soundsEnabled else { return }
        audioQueue.async {
            AudioServicesPlaySystemSound(1306)
        }
    }
}
