import SwiftUI

struct TrainingView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.appUsesGlobalChrome) var usesGlobalChrome
    @AppStorage(appDirectionKey) var selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
    @AppStorage(appArcadeCreditsKey) var arcadeCredits = 0
    @ObservedObject var listStore: VocabularyListStore
    let runtimeSpeechController: SpeechController?
    let runtimeSpeaker: Speaker?
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let launchContext: TrainingLaunchContext?
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let ensureAudioDependenciesReady: () async -> Void
    var sectionStyle: AppSectionStyle {
        switch session.trainingMode {
        case .vocabulary: return .train
        case .nouns: return .trainNouns
        case .articles: return .trainArticles
        case .verbs: return .trainVerbs
        case .verbforms: return .trainVerbforms
        }
    }

    @StateObject var session = TrainingSessionController()
    @State var lastResult: ScoreResult?
    @State var trainingCorrectCount = 0
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
    @State var showingArticleTranslation = false
    @State var verbMCOptions: [String] = []
    @State var verbMCSelected: String?
    @State var verbMCLocked = false
    @State var showingVerbTranslation = false
    @State var listPickerCategory: ListPickerCategory?

    // Verbformen
    @StateObject var verbformsSession = VerbformsSessionController()
    @State var verbformsInflections: [VerbformsEngine.VerbInflections] = []
    @State var verbformsCountdown: Int? = nil

    // Verbformen Drag-and-Drop (Quiz-Stil: DragGesture + Frame-Tracking,
    // KEIN Long-Press wie bei `.draggable`)
    @State var verbformsDraggingPronoun: VerbformsPerson?
    @State var verbformsDragOffset: CGSize = .zero
    @State var verbformsPronounFrames: [VerbformsPerson: CGRect] = [:]
    @State var verbformsFormFrames: [VerbformsPerson: CGRect] = [:]
    @State var verbformsHoveredForm: VerbformsPerson?

    // Verbformen Listen-Picker Sheet (separates Sheet auf der custom Listen-Card)
    @State var verbformsListPickerActive: Bool = false
    // Verbformen Verb-Lemma-Detail-Sheet (geöffnet via „X Verben"-Tap)
    @State var verbformsVerbDetailActive: Bool = false

    enum ListPickerCategory: Identifiable {
        case own, level, topic, all
        var id: String {
            switch self {
            case .own: return "own"
            case .level: return "level"
            case .topic: return "topic"
            case .all: return "all"
            }
        }
    }
    @State var speedCountdown: Int? = nil
    @FocusState var typedAnswerFieldFocused: Bool

    var speechController: SpeechController? {
        runtimeSpeechController
    }

    var speaker: Speaker? {
        runtimeSpeaker
    }

    var trainingListSummary: String {
        "\(trainingListName)\n\(trainingListCount)"
    }

    var trainingListName: String {
        let ids = session.selectedTrainingListIDs
        if ids.isEmpty { return "Listen wählen" }
        let allAvailable = availableTrainingLists
        let selected = allAvailable.filter { ids.contains($0.id) }
        if selected.count == 1, let first = selected.first {
            return first.name
        }
        return "\(selected.count) Listen"
    }

    var trainingListCount: String {
        let ids = session.selectedTrainingListIDs
        if ids.isEmpty { return "" }

        // Use activeItems count — same filtering as actual training
        let count = activeItems.count
        if count == 0 {
            let allAvailable = availableTrainingLists
            let selected = allAvailable.filter { ids.contains($0.id) }
            let totalItems = selected.reduce(0) { $0 + $1.items.count }
            return "\(totalItems) Eintr\u{00E4}ge"
        }

        if isVerbMode || isVerbformsMode {
            return "\(count) Verben"
        } else if isArticleMode || isNounMode {
            return "\(count) Nomen"
        } else {
            return "\(count) Eintr\u{00E4}ge"
        }
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

    var isNounMode: Bool {
        session.trainingMode == .nouns
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

    var isVerbformsMode: Bool {
        session.trainingMode == .verbforms
    }

    var ownListCount: Int {
        availableTrainingLists.filter { !$0.isBuiltIn || $0.isAggregateVocabulary }.count
    }
    var levelListCount: Int {
        availableTrainingLists.filter { $0.collectionPreset == .standardLevel }.count
    }
    var topicListCount: Int {
        availableTrainingLists.filter { $0.collectionPreset == .standardTopic }.count
    }
    var allInOneCount: Int { 1 }

    func filteredLists(for category: ListPickerCategory) -> [VocabularyList] {
        switch category {
        case .own:
            return availableTrainingLists.filter { !$0.isBuiltIn || $0.isAggregateVocabulary }
        case .level:
            return availableTrainingLists.filter { $0.collectionPreset == .standardLevel }
        case .topic:
            return availableTrainingLists.filter { $0.collectionPreset == .standardTopic }
        case .all:
            return [StandardVocabularyLoader.allInOneList]
        }
    }

    var verbPromptText: String {
        guard let item = session.currentTrainingItem else { return "" }
        let isFRtoDe = selectedAppDirection == .frenchToGerman || selectedAppDirection == .englishToGerman
        return isFRtoDe ? item.french : item.german
    }

    var verbCorrectAnswer: String {
        guard let item = session.currentTrainingItem else { return "" }
        let isFRtoDe = selectedAppDirection == .frenchToGerman || selectedAppDirection == .englishToGerman
        return isFRtoDe ? item.german : item.french
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
        0
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

        return trainingActionTint
    }

    var listeningButtonColor: Color {
        trainingActionTint
    }

    var trainingActionTint: Color {
        sectionStyle.accent
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

    var trainingItemLabel: String {
        if isVerbMode { return "Verben" }
        if isNounMode || isArticleMode { return "Nomen" }
        return "Eintr\u{00E4}ge"
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
