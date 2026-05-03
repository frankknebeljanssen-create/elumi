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
@MainActor
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
    /// **2026-05-02 (User-Befund „click noise bei slot drehen etwas
    /// leiser machen, ist lauter als alles andere")**: 0.6 → 0.3 —
    /// halbiert. Bei 16 Clicks/Sek. (max via Throttle) summieren
    /// sich auch leise Einzelticks akustisch auf, deshalb ist die
    /// effektive Lautstärke deutlich höher als ein single-shot
    /// Sound mit gleichem `volume`-Wert.
    private static let clickVolume: Float = 0.3

    // MARK: - State

    private var players: [AVAudioPlayer] = []
    private var nextPlayerIndex: Int = 0
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
            print("⚠️ [SlotAudio] Click-Resource '\(Self.clickResourceName).wav' fehlt im Bundle")
            return
        }
        for _ in 0..<Self.poolSize {
            do {
                let player = try AVAudioPlayer(contentsOf: url)
                player.volume = Self.clickVolume
                player.prepareToPlay()
                players.append(player)
            } catch {
                print("⚠️ [SlotAudio] Failed to preload click player: \(error)")
            }
        }
    }

    // MARK: - Mute-Awareness

    /// Liest den globalen Sound-Toggle aus `UserDefaults`. Gleicher Key
    /// wie `FeedbackPlayer.soundsEnabledKey` (dort `private`, daher
    /// hier inline gespiegelt — Pattern aus
    /// `LanguageDirectionSwitch.swift:92`). Default `true` (sounds an),
    /// wenn Key noch nie gesetzt wurde.
    private var soundsEnabled: Bool {
        let key = "FRDEVocabMVP.soundsEnabled.v1"
        let defaults = UserDefaults.standard
        if defaults.object(forKey: key) == nil { return true }
        return defaults.bool(forKey: key)
    }

    // MARK: - Public API

    /// Spielt einen einzelnen Reel-Click ab. Throttled — bei rapid
    /// successive Aufrufen werden Aufrufe < 60 ms nach dem letzten
    /// Click ignoriert. Player-Pool rotiert; älteste Instanz wird
    /// wiederverwendet wenn nötig.
    func playClick() {
        guard soundsEnabled else { return }
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastClickAt >= Self.clickThrottleSeconds else { return }
        lastClickAt = now

        guard !players.isEmpty else { return }
        let player = players[nextPlayerIndex]
        nextPlayerIndex = (nextPlayerIndex + 1) % players.count
        // Wenn der Player gerade noch läuft, abbrechen + von vorn —
        // ist OK für so kurze Samples, sounds gleichermaßen wie ein
        // frischer Tick.
        if player.isPlaying {
            player.stop()
            player.currentTime = 0
        }
        player.play()
    }

    /// Spielt den Settle-Sound bei `phase == .landed`. Aktuell
    /// System-Sound 1057 (Tink) als Platzhalter.
    func playSettle() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(1057)
    }

    /// Spielt den Win-Sound bei Reveal mit ≥ 2 Game-Symbolen (außer
    /// Jackpot). System-Sound 1025 als Platzhalter.
    func playWin() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(1025)
    }

    /// Spielt den Jackpot-Sound bei Reveal mit 3× Game. System-Sound
    /// 1306 als Platzhalter — wird in Stufe 6 (Branch
    /// `feature/training-session-flow`) durch echtes Feuerwerk-Sound
    /// ersetzt.
    func playJackpot() {
        guard soundsEnabled else { return }
        AudioServicesPlaySystemSound(1306)
    }
}
