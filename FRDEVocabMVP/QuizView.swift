import SwiftUI

struct QuizView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.appUsesGlobalChrome) var usesGlobalChrome
    /// **Stufe 3 (2026-05-01)** — Chain-Advance-Closure (siehe
    /// FlashcardsView.swift:Doc).
    @Environment(\.appChainAdvanceAction) var chainAdvance
    @AppStorage(appDirectionKey) var selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
    @AppStorage(appQuizHeartsKey) var collectedWorms = 0
    @AppStorage(appElumiWaterflohKey) var collectedWaterfloh = 0
    @AppStorage(appElumiAlgenkugelKey) var collectedAlgenkugel = 0
    @AppStorage(appElumiXPKey) var collectedXP = 0
    @AppStorage(appElumiCurrentStreakKey) var currentStreak = 0
    @AppStorage(appElumiBestStreakKey) var bestStreak = 0
    @AppStorage(appElumiLastRewardDayIndexKey) var lastRewardDayIndex = 0
    @AppStorage(appArcadeCreditsKey) var arcadeCredits = 0
    @ObservedObject var listStore: VocabularyListStore
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let launchContext: QuizLaunchContext?
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let sectionStyle: AppSectionStyle = .quiz

    @StateObject var session = QuizSessionController()
    /// **Stufe 4b-Modal-Refactor (2026-05-02)** — Token der aktuellen
    /// `TrainingChainStore`-Force-Advance-Handler-Registration. Siehe
    /// `FlashcardsView.forceAdvanceHandlerToken` für Doc.
    @State var forceAdvanceHandlerToken: UUID?
    @State var selectedMultipleChoiceOption: String?
    @State var multipleChoiceLocked = false
    @State var selectedPromptID: UUID?
    @State var selectedAnswerID: UUID?
    @State var matchedPairIDs: Set<UUID> = []
    @State var matchingHadMistake = false
    @State var flashingPromptID: UUID?
    @State var flashingAnswerID: UUID?
    @State var draggingPromptID: UUID?
    @State var dragOffset: CGSize = .zero
    @State var hoveredAnswerID: UUID?
    @State var answerFrames: [UUID: CGRect] = [:]
    @State var promptFrames: [UUID: CGRect] = [:]
    @State var showingWrongAnswers = false
    @State var fillBlanksSelected: String?
    @State var fillBlanksLocked = false
    @State var fillBlanksHadMistake = false
    @State var fillBlanksWrongOptions: Set<String> = []
    @State var fillBlanksFlashWrong: String?
    @State var comboSelectedVerbID: UUID?
    @State var comboMatchedIDs: Set<UUID> = []
    @State var comboHadMistake = false
    @State var comboFlashVerbID: UUID?
    @State var comboFlashNounID: UUID?
    @State var awardedHearts = 0
    @State var awardedWaterfloh = 0
    @State var awardedAlgenkugel = 0
    @State var unlockedRewardLevels: [ElumiLevelTier] = []
    @State var didPersistHearts = false
    /// Outcome aus dem zentralen `ProgressService` — wird in `persistHeartsIfNeeded`
    /// gesetzt und speist die `SessionSummaryView` im Ergebnis-Screen.
    @State var quizSessionOutcome: SessionRewardOutcome?
    @ObservedObject var progressStore = ProgressStore.shared
    @State var advanceTask: DispatchWorkItem?
    @State var typingInput = ""
    @State var typingLocked = false
    @State var typingShowCorrectAnswer: String?
    @State var showingQuizListPicker = false
    @FocusState var isTypingFieldFocused: Bool

    var selectedAppDirection: Direction {
        (Direction(rawValue: selectedAppDirectionRaw) ?? .frenchToGerman).sanitizedForFrenchOnly
    }

    var quizListSummary: String {
        let ids = session.selectedListIDs
        if ids.isEmpty { return "Listen wählen" }
        let selected = availableQuizLists.filter { ids.contains($0.id) }
        // **V1b (2026-04-28)** — Setup-Counts respektieren den globalen
        // Lernjahr-Filter; konsistent zu dem was nach „Quiz starten"
        // tatsächlich in den Question-Pool einfließt.
        let lernjahrMax = VocabularyListSelectionResolver.currentLernjahrMax()
        if selected.count == 1, let first = selected.first {
            let cnt = VocabularyListSelectionResolver.effectiveItems(
                for: first, lernjahrMax: lernjahrMax
            ).count
            return "\(first.name) · \(cnt) Einträge"
        }
        let total = selected.reduce(0) { acc, list in
            acc + VocabularyListSelectionResolver.effectiveItems(
                for: list, lernjahrMax: lernjahrMax
            ).count
        }
        return "\(selected.count) Listen · \(total) Einträge"
    }

    var availableQuizLists: [VocabularyList] {
        var lists: [VocabularyList] = []
        if let aggregateList = listStore.allCustomVocabularyList {
            lists.append(aggregateList)
        }
        lists.append(contentsOf: listStore.sortedCustomLists)
        lists.append(contentsOf: StandardVocabularyLoader.levelLists)
        lists.append(contentsOf: StandardVocabularyLoader.topicLists)
        return lists
    }

    var selectedQuizLists: [VocabularyList] {
        availableQuizLists.filter { session.selectedListIDs.contains($0.id) }
    }

    var canStartQuiz: Bool {
        session.canStartQuiz
    }

    /// Master-Session-Setup-Estimate für die Gamification-Bar.
    /// Berechnet aus der aktuellen Quiz-Config (Fragenzahl) + zentralen Werten.
    @MainActor
    var quizSessionEstimate: SessionEstimate {
        let config = SessionConfig(module: .quiz, itemCount: session.questionCountOption.rawValue)
        return SessionSetupEstimator.estimate(
            for: config,
            progress: progressStore.progress,
            dailyChallenge: DailyChallengeStore.shared.challenge
        )
    }

    var currentQuestion: QuizQuestion? {
        session.currentQuestion
    }

    var displayedQuestionCount: Int {
        session.displayedQuestionCount
    }

    var correctCount: Int {
        session.correctCount
    }

    var wrongCount: Int {
        session.wrongCount
    }

    var resultHeadline: String {
        if !unlockedRewardLevels.isEmpty {
            return "Level-Up!"
        }

        if wrongCount == 0, !session.answeredResults.isEmpty {
            return "Perfekte Lektion!"
        }

        switch correctCount {
        case 8...:
            return "Excellent !"
        case 5...:
            return "Très bien !"
        case 1...:
            return "Bien joué !"
        default:
            return "Continue !"
        }
    }

    /// Fasst die Quiz-spezifischen Elumi-Rewards (Hearts-Sammlung) zusammen.
    /// XP läuft jetzt ausschließlich über `SessionSummaryView` — wird hier
    /// bewusst NICHT mehr dupliziert (sonst divergieren alte/neue Rechnung).
    var rewardSummaryText: String {
        var parts: [String] = []

        if awardedHearts > 0 {
            parts.append("+\(awardedHearts) Würmchen")
        }
        if awardedWaterfloh > 0 {
            parts.append("+\(awardedWaterfloh) Wasserflöhe")
        }
        if awardedAlgenkugel > 0 {
            parts.append("+\(awardedAlgenkugel) Algenkugeln")
        }

        return parts.isEmpty ? "Quiz beendet" : parts.joined(separator: " · ")
    }

    var currentLevelAfterRewards: ElumiLevelTier {
        elumiLevelTier(for: collectedXP)
    }

    var isPerfectQuiz: Bool {
        wrongCount == 0 && !session.answeredResults.isEmpty
    }

    var totalRewardCount: Int {
        awardedHearts + awardedWaterfloh + awardedAlgenkugel
    }

    var dominantRewardSnackKind: ElumiSnackKind {
        if awardedAlgenkugel > 0 {
            return .algenkugel
        }
        if awardedWaterfloh > 0 {
            return .wasserfloh
        }
        return .wuermchen
    }

    var quizTopBarSpacing: CGFloat {
        AppLayout.topBarInsetTop + AppTheme.Spacing.xs
    }

    var quizBottomBarSpacing: CGFloat {
        AppLayout.bottomBarInsetBottom + AppTheme.Spacing.sm
    }

    var quizSetupCardInset: CGFloat {
        8
    }
}
