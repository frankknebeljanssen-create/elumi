import SwiftUI

struct QuizView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.appUsesGlobalChrome) var usesGlobalChrome
    @AppStorage(appDirectionKey) var selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
    @AppStorage(appQuizHeartsKey) var collectedWorms = 0
    @AppStorage(appElumiWaterflohKey) var collectedWaterfloh = 0
    @AppStorage(appElumiAlgenkugelKey) var collectedAlgenkugel = 0
    @AppStorage(appElumiXPKey) var collectedXP = 0
    @AppStorage(appElumiCurrentStreakKey) var currentStreak = 0
    @AppStorage(appElumiBestStreakKey) var bestStreak = 0
    @AppStorage(appElumiLastRewardDayIndexKey) var lastRewardDayIndex = 0
    @ObservedObject var listStore: VocabularyListStore
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let sectionStyle: AppSectionStyle = .quiz

    @StateObject var session = QuizSessionController()
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
    @State var awardedHearts = 0
    @State var awardedWaterfloh = 0
    @State var awardedAlgenkugel = 0
    @State var awardedXP = 0
    @State var unlockedRewardLevels: [ElumiLevelTier] = []
    @State var didPersistHearts = false
    @State var advanceTask: DispatchWorkItem?

    var selectedAppDirection: Direction {
        (Direction(rawValue: selectedAppDirectionRaw) ?? .frenchToGerman).sanitizedForFrenchOnly
    }

    var availableQuizLists: [VocabularyList] {
        var lists: [VocabularyList] = [listStore.builtInList]
        if let aggregateList = listStore.allCustomVocabularyList {
            lists.append(aggregateList)
        }
        lists.append(contentsOf: listStore.sortedCustomLists)
        return lists
    }

    var selectedQuizLists: [VocabularyList] {
        availableQuizLists.filter { session.selectedListIDs.contains($0.id) }
    }

    var canStartQuiz: Bool {
        session.canStartQuiz
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
        if awardedXP > 0 {
            parts.append("+\(awardedXP) XP")
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
