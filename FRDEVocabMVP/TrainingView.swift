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

    // Session-Summary-Outcomes — werden beim Reward-Vergeben gesetzt und
    // steuern die Anzeige der zentralen `SessionSummaryView`. Für Training
    // als Overlay (nach `handleTopBarBack`), für Verbformen ersetzt das
    // Outcome den bisherigen Result-Screen komplett.
    @State var trainingSessionOutcome: SessionRewardOutcome?
    @State var verbformsSessionOutcome: SessionRewardOutcome?
    @ObservedObject var progressStore = ProgressStore.shared

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

    // Verben-Modul Listen-Picker / Lemma-Detail (eigene Sheet-States, damit
    // die Custom-Card im Verben-Setup unabhängig von Verbformen funktioniert)
    @State var verbsListPickerActive: Bool = false
    @State var verbsVerbDetailActive: Bool = false

    // Nomen + Artikel: jeweils eigener Listen-Picker (gleicher Stil wie Verben)
    @State var nounsListPickerActive: Bool = false
    @State var articlesListPickerActive: Bool = false

    // Cache: Lemma-Liste für die aktuelle Setup-Card. Wird bei Selection- oder
    // Mode-Wechsel via onChange neu berechnet, NICHT bei jedem Render — sonst
    // hängt die App ab ~4 großen Listen (verbformsLemmasFromSelectedLists ist
    // teuer wegen FrenchListStatisticsAggregator).
    @State var setupCardLemmas: [String] = []
    /// Gecachter „kann Training starten"-Flag für die Modi mit teurer
    /// Analyse-Pipeline (verbs/verbforms/nouns/articles). Wird im selben
    /// Background-Task gesetzt wie `setupCardLemmas`.
    @State var setupCanStartCached: Bool = false

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

    /// Master-Session-Setup-Estimate für die verpflichtende Gamification-Bar
    /// oberhalb des Training-CTA. Item-Count = effektive aktive Items der
    /// gewählten Liste(n). Modul variiert je nach Training-Typ, damit die
    /// Dauer-Schätzung stimmt (Verbformen kürzer als Vokabel-Training,
    /// Speed-Round nochmal deutlich kürzer).
    @MainActor
    var trainingSessionEstimate: SessionEstimate {
        let items = activeItems.count
        // In Verbformen / Speed-Round rechnet eine Session nicht durch alle
        // Items, sondern durch eine Teilmenge. Als Preview-Schätzung kappen
        // wir auf einen realistischen Session-Umfang — ProgressService liefert
        // am Ende die exakten Werte, aber hier wollen wir Orientierung.
        let estimatedItemCount: Int
        let module: SessionConfig.Module
        if isVerbformsMode {
            module = session.isSpeedRound ? .speedRound : .verbforms
            estimatedItemCount = session.isSpeedRound ? min(items, 20) : min(items, 12)
        } else if session.isSpeedRound {
            module = .speedRound
            estimatedItemCount = min(items, 20)
        } else {
            module = .training
            estimatedItemCount = min(items, 15)
        }
        let config = SessionConfig(module: module, itemCount: estimatedItemCount)
        return SessionSetupEstimator.estimate(
            for: config,
            progress: progressStore.progress,
            dailyChallenge: DailyChallengeStore.shared.challenge
        )
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
        // Vocabulary nutzt simple cardType-Filterung (kein analyze) — fast.
        // Verbs/Verbforms/Nouns/Articles laufen über teure Pipeline und werden
        // im setupCanStartCached gehalten (per onChange aktualisiert).
        switch session.trainingMode {
        case .vocabulary:
            return !activeItems.isEmpty
        case .verbs, .verbforms, .nouns, .articles:
            return setupCanStartCached
        }
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
