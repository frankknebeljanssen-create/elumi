import SwiftUI

struct TrainingView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.appUsesGlobalChrome) var usesGlobalChrome
    @AppStorage(appDirectionKey) var selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
    @ObservedObject var listStore: VocabularyListStore
    let runtimeSpeechController: SpeechController?
    let runtimeSpeaker: Speaker?
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let launchContext: TrainingLaunchContext?
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let ensureAudioDependenciesReady: () async -> Void
    let sectionStyle: AppSectionStyle = .train

    @StateObject var session = TrainingSessionController()
    @State var lastResult: ScoreResult?
    @State var shouldEvaluateAfterStop = false
    @State var pendingFeedbackTask: DispatchWorkItem?
    @State var typedAnswer = ""
    @State var showingTypedAnswerInput = false
    @State var isMicPulseVisible = false
    @State var hasTriggeredAudioPreparation = false
    @State var isPreparingAudioDependencies = false
    @State var wasSpeakerSpeaking = false
    @State var wasRecording = false
    @State var articleAnswer: String?
    @State var articleLocked = false
    @FocusState var typedAnswerFieldFocused: Bool

    var speechController: SpeechController? {
        runtimeSpeechController
    }

    var speaker: Speaker? {
        runtimeSpeaker
    }

    var activeItems: [VocabularyItem] {
        session.activeItems(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )
    }

    var currentCard: FlashCard? {
        session.currentTrainingItem?.card(for: session.direction)
    }

    var isArticleMode: Bool {
        session.trainingMode == .articles
    }

    var articlePromptText: String? {
        guard isArticleMode, let item = session.currentTrainingItem else { return nil }
        return TrainingSessionController.strippingFrenchArticle(from: item.french)
    }

    var correctArticle: String? {
        guard isArticleMode, let item = session.currentTrainingItem else { return nil }
        return TrainingSessionController.determineFrenchArticle(item)
    }

    var isVerbMode: Bool {
        session.trainingMode == .verbs
    }

    var dictionaryTrainingList: VocabularyList? {
        session.dictionaryTrainingList()
    }

    var shouldPrepareDictionaryTrainingList: Bool {
        session.shouldPrepareDictionaryTrainingList(launchContext: launchContext)
    }

    var availableTrainingLists: [VocabularyList] {
        session.availableTrainingLists(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )
    }

    var selectedTrainingList: VocabularyList? {
        session.selectedTrainingList(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )
    }

    var selectedAppDirection: Direction {
        (Direction(rawValue: selectedAppDirectionRaw) ?? .frenchToGerman).sanitizedForFrenchOnly
    }

    var selectedTrainingListLanguages: [StudyLanguage] {
        session.selectedTrainingListLanguages(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )
    }

    var isDictionaryTrainingSelected: Bool {
        session.isDictionaryTrainingSelected()
    }

    var localeIdentifierForRecognition: String {
        session.direction.recognitionLocaleIdentifier
    }

    var actionButtonHeight: CGFloat {
        AppTheme.Layout.buttonHeight
    }

    var trainingSessionCardInset: CGFloat {
        8
    }

    var recordingSymbolName: String {
        isSpeechRecording ? "stop.fill" : "mic.fill"
    }

    var showsRetryOnlyMessage: Bool {
        lastResult?.label.hasPrefix("Falsch") == true
    }

    var showsNotRecognizedMessage: Bool {
        lastResult?.label == "Nicht erkannt"
    }

    var showsSuccessOnlyMessage: Bool {
        lastResult?.label == "Richtig 🙂"
    }

    var showsSolutionMessage: Bool {
        lastResult?.label == "Lösung"
    }

    var solutionUnlockThreshold: Int {
        2
    }

    var canRevealSolution: Bool {
        session.hasStartedTraining && currentCard != nil && session.failedAttemptsOnCurrentCard >= solutionUnlockThreshold
    }

    var recordingButtonColor: Color {
        if showsSuccessOnlyMessage {
            return AppTheme.Colors.success
        }

        if showsRetryOnlyMessage {
            return Color(red: 0.9, green: 0.3, blue: 0.15)
        }

        return AppTheme.Colors.warning
    }

    var listeningButtonColor: Color {
        AppTheme.Colors.warning
    }

    var trainingActionTint: Color {
        AppTheme.Colors.warning
    }

    var isAudioModeEnabled: Bool {
        feedbackPlayer.areSoundsEnabled
    }

    var canUseSpeechRecognition: Bool {
        guard let speechController else { return false }
        return speechController.authorizationStatus != .denied && speechController.authorizationStatus != .restricted
    }

    var solutionButtonTitle: String {
        if canRevealSolution {
            return "Lösung"
        }
        return "Lösung \(session.failedAttemptsOnCurrentCard)/\(solutionUnlockThreshold)"
    }

    var nextCardTitle: String {
        session.cardType == .phrases ? "Nächste Phrase" : "Nächstes Wort"
    }

    var sessionCardMinHeight: CGFloat {
        session.cardType == .phrases ? 152 : 118
    }

    var sessionPromptFont: Font {
        .system(size: session.cardType == .phrases ? 20 : 28, weight: .bold, design: .rounded)
    }

    var canStartTraining: Bool {
        !activeItems.isEmpty
    }

    var isSpeechRecording: Bool {
        speechController?.isRecording == true
    }

    var isSpeakerSpeaking: Bool {
        speaker?.isSpeaking == true
    }

    var startHintText: String {
        if isDictionaryTrainingSelected {
            return "Wähle ein anderes Lernniveau oder eine andere Quelle."
        }
        if availableTrainingLists.isEmpty {
            return "Lege zuerst eine Liste mit Vokabeln an."
        }
        return "Für diesen Typ gibt es in der gewählten Liste noch keine Einträge."
    }
}
