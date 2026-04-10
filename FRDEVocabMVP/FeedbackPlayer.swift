import SwiftUI
import AVFoundation

@MainActor
struct SoundToggleToast: Equatable {
    let message: String
    let systemImage: String
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
    var engine: AVAudioEngine?
    var playerNode: AVAudioPlayerNode?
    var loopPlayerNode: AVAudioPlayerNode?
    var bgmPlayerNode: AVAudioPlayerNode?
    let audioSession = AVAudioSession.sharedInstance()
    let sampleRate: Double = 44_100
    lazy var cardFlipBuffer: AVAudioPCMBuffer? = makeCardFlipBuffer()
    lazy var scanStartBuffer: AVAudioPCMBuffer? = makeScanStartBuffer()
    lazy var scanDoneBuffer: AVAudioPCMBuffer? = makeScanDoneBuffer()
    lazy var appStartBuffer: AVAudioPCMBuffer? = makeAppStartBuffer()
    lazy var toggleBuffer: AVAudioPCMBuffer? = makeToggleBuffer()
    lazy var tabSwitchBuffer: AVAudioPCMBuffer? = makeTabSwitchBuffer()
    lazy var listActionBuffer: AVAudioPCMBuffer? = makeListActionBuffer()
    lazy var favStarBuffer: AVAudioPCMBuffer? = makeFavStarBuffer()
    lazy var launchBuffer: AVAudioPCMBuffer? = makeLaunchBuffer()
    lazy var successBuffer: AVAudioPCMBuffer? = makeSuccessBuffer()
    lazy var errorBuffer: AVAudioPCMBuffer? = makeErrorBuffer()
    lazy var achievementBuffer: AVAudioPCMBuffer? = makeAchievementBuffer()
    lazy var flashcardSuccessBuffer: AVAudioPCMBuffer? = makeFlashcardSuccessBuffer()
    lazy var flashcardErrorBuffer: AVAudioPCMBuffer? = makeFlashcardErrorBuffer()
    lazy var flashcardAchievementBuffer: AVAudioPCMBuffer? = makeFlashcardAchievementBuffer()
    lazy var quizCoinBuffer: AVAudioPCMBuffer? = makeQuizCoinBuffer()
    lazy var arcadeComboBuffer: AVAudioPCMBuffer? = makeArcadeComboBuffer()
    lazy var gameOverBuffer: AVAudioPCMBuffer? = makeGameOverBuffer()
    lazy var slowMotionActivateBuffer: AVAudioPCMBuffer? = makeSlowMotionActivateBuffer()
    lazy var slowMotionEndBuffer: AVAudioPCMBuffer? = makeSlowMotionEndBuffer()
    lazy var snackMissBuffer: AVAudioPCMBuffer? = makeSnackMissBuffer()
    lazy var roundClearBuffer: AVAudioPCMBuffer? = makeRoundClearBuffer()
    lazy var highScoreBuffer: AVAudioPCMBuffer? = makeHighScoreBuffer()
    lazy var powerUpSpawnBuffer: AVAudioPCMBuffer? = makePowerUpSpawnBuffer()
    lazy var shieldActivateBuffer: AVAudioPCMBuffer? = makeShieldActivateBuffer()
    lazy var shieldAbsorbBuffer: AVAudioPCMBuffer? = makeShieldAbsorbBuffer()
    lazy var bgmBuffer: AVAudioPCMBuffer? = makeBGMBuffer()
    lazy var suctionWhirBuffer: AVAudioPCMBuffer? = makeSuctionWhirBuffer()
    lazy var suctionLoopBuffer: AVAudioPCMBuffer? = makeSuctionLoopBuffer()
    lazy var suctionWindDownBuffer: AVAudioPCMBuffer? = makeSuctionWindDownBuffer()
    var isConfigured = false
    var soundToastDismissWorkItem: DispatchWorkItem?

    init() {
        if UserDefaults.standard.object(forKey: soundsEnabledKey) != nil {
            areSoundsEnabled = UserDefaults.standard.bool(forKey: soundsEnabledKey)
        }
    }
}
