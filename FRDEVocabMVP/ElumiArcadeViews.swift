import SwiftUI

enum ElumiArcadeDropKind: Equatable {
    case wuermchen
    case wasserfloh
    case algenkugel
    case bonusblase
    case saugglocke
    case slowMotionPotion
    case falseElumi

    var snackKind: ElumiSnackKind? {
        switch self {
        case .wuermchen:
            return .wuermchen
        case .wasserfloh:
            return .wasserfloh
        case .algenkugel:
            return .algenkugel
        case .bonusblase, .saugglocke, .slowMotionPotion, .falseElumi:
            return nil
        }
    }

    var isSnack: Bool {
        snackKind != nil
    }
}

/// Central configuration for arcade round difficulty — single source of truth.
struct ArcadeRoundConfig {
    let round: Int

    // ── Spawn rates ──
    var bonusChance: Double {
        switch round {
        case 4: return 0.14          // Bonus-Regen
        case 5: return 0.055         // Elumi-Freunde
        default: return round >= 6 ? 0.10 : 0.055
        }
    }

    var suctionChance: Double {
        switch round {
        case 4: return 0.12
        case 5: return 0.07
        default: return round >= 6 ? 0.10 : 0.07
        }
    }

    var falseElumiChance: Double {
        switch round {
        case 4: return min(0.10, 0.04 + (Double(round - 1) * 0.02))
        case 5: return 0.20           // Elumi-Freunde: many
        default: return round >= 6 ? 0.16 : min(0.12, 0.04 + (Double(round - 1) * 0.02))
        }
    }

    var slowMotionPotionChance: Double { round >= 2 ? 0.04 : 0.0 }

    // ── Speed ──
    var spawnDelay: Double { max(0.38, 1.05 - (Double(round - 1) * 0.13)) }
    var fallDuration: Double { max(1.45, 4.2 - (Double(round - 1) * 0.4)) }

    // ── Querschläger ──
    var querschlaegerChance: Double {
        switch round {
        case 3: return 0.20           // Sanfter Einstieg
        default: return round >= 4 ? 0.30 : 0.0
        }
    }

    /// Wobble amplitude — how far Querschläger sway (wider = harder)
    var querschlaegerAmplitude: ClosedRange<CGFloat> {
        round <= 3 ? 0.08...0.15 : 0.15...0.30
    }

    /// Wobble frequency — how fast they zigzag
    var querschlaegerFrequency: ClosedRange<Double> {
        round <= 3 ? 2.0...4.0 : 4.0...6.5
    }

    // ── Snacks per round ──
    var snacksRequired: Int { 12 }

    // ── Bonus round ──
    var isBonusRoundTrigger: Bool { round % 3 == 0 }

    // ── Jellyfish ──
    var jellyfishChance: Double {
        switch round {
        case 1...2: return 0.0
        case 3: return 0.008
        default: return 0.012
        }
    }
}

struct JellyfishState: Identifiable, Equatable {
    let id = UUID()
    let spawnedAt: Date
    let fromLeft: Bool
    let normalizedY: CGFloat      // 0.15–0.40
    let speed: Double             // 7–10s crossing time
    let wobblePhase: Double
    var tentaclesDropped: Int = 0
    var lastTentacleDropAt: Date?
}

struct TentacleDropState: Identifiable, Equatable {
    let id = UUID()
    let spawnedAt: Date
    let startY: CGFloat           // Quallen-Y beim Abwurf (screen coords)
    let normalizedX: CGFloat      // X-Position beim Abwurf (0–1)
    let wobbleAmplitude: CGFloat  // 0.02–0.05
    let fallDuration: Double      // 2.8–3.5s
}

struct BonusFishState: Identifiable, Equatable {
    let id = UUID()
    let spawnedAt: Date
    let fromLeft: Bool
    let normalizedY: CGFloat
    let speed: Double
    let wobblePhase: Double
    let renderScale: CGFloat     // 1.0-3.0
    var isCaught: Bool = false
}

struct ElumiArcadeSnackState: Identifiable, Equatable {
    let id = UUID()
    let kind: ElumiArcadeDropKind
    let spawnedAt: Date
    let laneX: CGFloat
    let wobbleAmplitude: CGFloat
    let wobbleFrequency: Double
    let fallDuration: Double
    let rotationDrift: Double
    let renderScale: CGFloat
    let motionPhase: Double
    let points: Int
}

struct ElumiArcadeGameView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    @AppStorage(appElumiArcadeHighScoreKey) var highScore = 0
    @AppStorage(appArcadeCreditsKey) var arcadeCredits = 0
    /// Wenn `true`, wird das Start-Overlay übersprungen und das Spiel beginnt
    /// direkt — Credit-Abzug und „Spiel starten"-CTA sind dann Aufgabe der
    /// aufrufenden View (z. B. `GameHubView`). Default `false` bewahrt das
    /// bisherige Verhalten für den Footer-Elumi-Quick-Launch.
    var autoStart: Bool = false

    @State var gameSeed = UUID()
    @State var gameSize: CGSize = .zero
    @State var gameClock = Date()
    @State var lastFrameDate: Date?
    @State var elumiX: CGFloat = 0.5
    @State var activeSnacks: [ElumiArcadeSnackState] = []
    @State var score = 0
    @State var misses = 0
    @State var isPlaying = false
    @State var isGameOver = false
    // Hinweis: Initialwert des Overlays wird in der konsumierenden View
    // `ElumiArcadeGameView+Layout.swift` via `.onAppear` je nach `autoStart`
    // angepasst. Wir starten default mit dem Overlay, damit alte Call-Sites
    // (Footer-Elumi) unverändert funktionieren.
    @State var showingStartOverlay = true
    @State var mouthOpen = false
    @State var characterScale: CGFloat = 1
    @State var characterRotation: Double = 0
    @State var sparkleBurst = false
    @State var comboCount = 0
    @State var bestCombo = 0
    @State var totalCaught = 0
    @State var lastCatchDate: Date?
    @State var comboBannerText: String?
    @State var didBeatHighScore = false
    @State var suctionEndsAt: Date?
    @State var suctionDockScale: CGFloat = 1.0
    @State var bonusPointsEndsAt: Date?
    @State var slowMotionEndsAt: Date?
    @State var screenShakeOffset: CGFloat = 0
    @State var gameOverTitle = "Game Over"
    @State var gameOverSubtitle = ""
    @State var round = 1
    @State var roundCatchCount = 0
    @State var roundSuctionSpawned = false
    @State var showingRoundBanner = false
    @State var roundBannerPhase = 0  // 0=geschafft, 1=ready blink, 2=done
    @State var readyBlinkVisible = true
    @State var elumiVisible = false

    // Bonus fish round
    @State var isBonusRound = false
    @State var bonusFishCaught = 0
    @State var bonusFishSpawned = 0
    @State var activeFish: [BonusFishState] = []
    @State var elumiY: CGFloat = 0.5
    @State var bonusRoundStartedAt: Date?
    @State var bonusRoundResultText: String?
    @State var bonusRoundWaitingForTap = false
    let bonusFishTotal = 15
    let bonusRoundDuration: TimeInterval = 12.0

    // Jellyfish
    @State var activeJellyfish: JellyfishState?
    @State var activeTentacles: [TentacleDropState] = []
    @State var jellyfishStingCount = 0

    // Phase 4 – Start-Overlay: Spielregeln sind per Default eingeklappt,
    // damit der CTA und der Credit-Status die primäre Aufmerksamkeit
    // bekommen. Der User kann die Regeln bei Bedarf ausklappen.
    @State var isShowingArcadeRules = false

    let maxMisses = 4
    let suctionDuration: TimeInterval = 4.6
    let bonusPointsDuration: TimeInterval = 5.0
    let slowMotionDuration: TimeInterval = 0.55
    let slowMotionPotionDuration: TimeInterval = 5.0
    let suctionBeamHalfWidth: CGFloat = 92

    var headerTitle: String {
        if isGameOver { return "Spiel vorbei" }
        if showingStartOverlay { return "Elumi Spiel" }
        return "Runde \(round)"
    }

    func snacksForRound(_ r: Int) -> Int {
        ArcadeRoundConfig(round: r).snacksRequired
    }

    var roundSubtitle: String {
        switch round {
        case 1: return "Los geht's!"
        case 2: return "🧪 Zeitlupe-Trank!"
        case 3: return "Querschläger!"
        case 4: return "Bonus-Regen!"
        case 5: return "Elumi-Freunde!"
        default: return "Chaos!"
        }
    }

}
