import Foundation
import AVFoundation

/// **Zentrale SFX-Verwaltung für den Word Runner.**
///
/// - Singleton, `@MainActor`
/// - Delegiert Audio-I/O an `SoundPlayer.shared` (selbe Infrastruktur
///   wie WordRunner-Musik + bestehende UI-SFX) — kein paralleler
///   Loader, kein zweiter Audio-Stack
/// - Preload aller SFX beim ersten Zugriff
///
/// **Mapping** (Resource-Namen ohne Extension):
///
///   | Type        | File              | Volume |
///   |-------------|-------------------|--------|
///   | .lane       | sfx_lane          | 0.32   |
///   | .correct    | sfx_correct       | 0.55   |
///   | .wrong      | sfx_wrong         | 0.50   |
///   | .lifeLoss   | sfx_life_loss     | 0.65   |
///   | .pickup     | sfx_pickup        | 0.55   |
///   | .boost      | sfx_boost         | 0.55   |
///
/// **Priorität**:
/// `.lifeLoss` überschreibt einen `wrong`-Trigger — das stellt
/// `playEither(_:_:)` sicher: spielt entweder den ersten oder den
/// zweiten Sound, nie beide. Der Caller im VM/View nutzt
/// `play(.lifeLoss)` direkt; der reine `play(.wrong)`-Pfad ist nur
/// für Wrong-Hits ohne Life-Loss.
///
/// **Robustheit**:
/// - Fehlende Files → kein Crash, nur Debug-Log
/// - Schnelle Inputs (z. B. Lane-Spam): SoundPlayer ersetzt den
///   alten Player für die gleiche Resource → keine doppelten
///   Sounds derselben Sorte parallel
@MainActor
final class WordRunnerSFXPlayer {

    static let shared = WordRunnerSFXPlayer()

    enum SFXType: CaseIterable {
        case lane
        case correct
        case wrong
        case lifeLoss
        case pickup
        case boost

        var resourceName: String {
            switch self {
            case .lane:     return "sfx_lane"
            case .correct:  return "sfx_correct"
            case .wrong:    return "sfx_wrong"
            case .lifeLoss: return "sfx_life_loss"
            case .pickup:   return "sfx_pickup"
            case .boost:    return "sfx_boost"
            }
        }

        // Audio-Balance-Pass (Phase 7.6): Musik ist um ~15 % leiser
        // (siehe `WordRunnerMusicPlayer.defaultVolume`), SFX werden
        // leicht angehoben, damit sie über der Musik durchkommen.
        //   • Life-Loss bleibt am stärksten (klarstes Fehler-Signal).
        //   • Lane bleibt dezent (feuert sehr häufig).
        //   • Correct/Wrong/Pickup/Boost wandern auf ~0.65.
        var volume: Float {
            switch self {
            case .lane:     return 0.38
            case .correct:  return 0.68
            case .wrong:    return 0.65
            case .lifeLoss: return 0.78
            case .pickup:   return 0.68
            case .boost:    return 0.65
            }
        }
    }

    /// Globaler Mute-Flag für **Game-Over-Phase**: nach einem Game-
    /// Over werden weitere SFX (außer Life-Loss selbst) unterdrückt,
    /// damit verspätete Frame-Triggers den Crash-Sound nicht
    /// übertönen. View ruft `setMuted(true)` auf Game-Over,
    /// `setMuted(false)` beim Restart.
    private var isMuted: Bool = false

    /// Cache vorgeladener AVAudioPlayer pro SFX-Type. Erlaubt
    /// **sofortiges** Abspielen ohne Decode-Verzögerung beim ersten
    /// Lane-Wechsel.
    private var preloadedPlayers: [SFXType: AVAudioPlayer] = [:]

    private init() {}

    // MARK: - Public API

    /// Spielt einen SFX ab. Robust gegen fehlende Files (kein Crash,
    /// nur Debug-Log). Während `isMuted == true` werden alle Sounds
    /// **außer `.lifeLoss`** unterdrückt.
    func play(_ type: SFXType) {
        if isMuted && type != .lifeLoss { return }
        ensurePreloaded(type)
        guard let player = preloadedPlayers[type] else {
            // Fallback auf SoundPlayer für robustes Behavior, falls
            // Preload aus irgendeinem Grund nicht klappte.
            SoundPlayer.shared.playMusic(
                resource: type.resourceName,
                ext: "wav",
                volume: type.volume
            )
            // Direkt wieder stoppen — playMusic loopt, das wollen
            // wir bei SFX nicht. Stop nach 1 s.
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                SoundPlayer.shared.stopMusic(resource: type.resourceName)
            }
            return
        }
        // Replay durch currentTime = 0 + play() — schneller als
        // neuer Player, vermeidet Decoder-Roundtrip.
        player.currentTime = 0
        player.volume = type.volume
        player.play()
    }

    /// **Priority-Helper**: spielt den **stärkeren** der beiden Typen.
    /// Damit lassen sich Wrong + LifeLoss-Trigger im selben Frame
    /// zusammenfassen — nur der stärkere Sound wird hörbar.
    func playEither(_ a: SFXType, or b: SFXType) {
        // Aktuell: lifeLoss > wrong, wrong > rest.
        let priority: [SFXType: Int] = [
            .lifeLoss: 100, .wrong: 50, .correct: 30,
            .pickup: 30, .boost: 30, .lane: 10
        ]
        let pa = priority[a] ?? 0
        let pb = priority[b] ?? 0
        play(pa >= pb ? a : b)
    }

    /// Game-Over: weitere SFX unterdrücken (außer LifeLoss selbst).
    func setMuted(_ muted: Bool) {
        isMuted = muted
    }

    /// Pre-Loads alle SFX (z. B. beim Run-Start aufrufen). Vermeidet
    /// First-Play-Latenz auf dem ersten Spurwechsel.
    func preloadAll() {
        for type in SFXType.allCases {
            ensurePreloaded(type)
        }
    }

    // MARK: - Intern

    private func ensurePreloaded(_ type: SFXType) {
        if preloadedPlayers[type] != nil { return }
        // SFX-Files liegen im Sub-Ordner `Sounds/sfx/`. Bundle-
        // Lookup mit `subdirectory:` adressiert das direkt.
        guard let url = Bundle.main.url(
            forResource: type.resourceName,
            withExtension: "wav",
            subdirectory: "sfx"
        ) ?? Bundle.main.url(
            forResource: type.resourceName,
            withExtension: "wav"
        ) else {
            #if DEBUG
            print("⚠️ [SFX] Missing: \(type.resourceName).wav")
            #endif
            return
        }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.volume = type.volume
            preloadedPlayers[type] = player
        } catch {
            #if DEBUG
            print("⚠️ [SFX] Load failed for \(type.resourceName): \(error)")
            #endif
        }
    }
}
