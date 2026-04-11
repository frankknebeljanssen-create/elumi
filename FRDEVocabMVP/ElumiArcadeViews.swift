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

    let maxMisses = 4
    let suctionDuration: TimeInterval = 4.6
    let bonusPointsDuration: TimeInterval = 5.0
    let slowMotionDuration: TimeInterval = 0.55
    let slowMotionPotionDuration: TimeInterval = 5.0
    let suctionBeamHalfWidth: CGFloat = 92

    var headerTitle: String {
        if isGameOver { return "Spiel vorbei" }
        if showingStartOverlay { return "Elumi Arcade" }
        return "Runde \(round)"
    }

    func snacksForRound(_ r: Int) -> Int {
        switch r {
        case 1: return 12
        case 2: return 15
        default: return 18
        }
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
