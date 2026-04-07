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
    let audioSession = AVAudioSession.sharedInstance()
    let sampleRate: Double = 44_100
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
    var isConfigured = false
    var soundToastDismissWorkItem: DispatchWorkItem?

    init() {
        if UserDefaults.standard.object(forKey: soundsEnabledKey) != nil {
            areSoundsEnabled = UserDefaults.standard.bool(forKey: soundsEnabledKey)
        }
    }
}
