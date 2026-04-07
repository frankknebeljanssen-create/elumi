import SwiftUI

enum ElumiArcadeDropKind: Equatable {
    case wuermchen
    case wasserfloh
    case algenkugel
    case bonusblase
    case saugglocke
    case falseElumi

    var snackKind: ElumiSnackKind? {
        switch self {
        case .wuermchen:
            return .wuermchen
        case .wasserfloh:
            return .wasserfloh
        case .algenkugel:
            return .algenkugel
        case .bonusblase, .saugglocke, .falseElumi:
            return nil
        }
    }

    var isSnack: Bool {
        snackKind != nil
    }
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
    @State var bonusPointsEndsAt: Date?
    @State var slowMotionEndsAt: Date?
    @State var screenShakeOffset: CGFloat = 0
    @State var gameOverTitle = "Elumi ist satt"
    @State var gameOverSubtitle = "Ein starker Lauf."

    let maxMisses = 3
    let suctionDuration: TimeInterval = 4.6
    let bonusPointsDuration: TimeInterval = 5.0
    let slowMotionDuration: TimeInterval = 0.55
    let suctionBeamHalfWidth: CGFloat = 92

    var level: Int {
        max(1, 1 + score / 80)
    }

    var headerTitle: String {
        isGameOver ? "Spiel vorbei" : "Elumi Arcade"
    }

}
