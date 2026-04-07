import Foundation
import SwiftUI

@MainActor
final class QuizSessionController: ObservableObject {
    @Published var selectedListIDs: Set<UUID> = []
    @Published var questionCountOption: QuizQuestionCountOption = .five
    @Published var questions: [QuizQuestion] = []
    @Published var cachedMergedItems: [VocabularyItem] = []
    @Published var cachedCandidates: [QuizCandidate] = []
    @Published var currentQuestionIndex = 0
    @Published var answeredResults: [Bool] = []
    @Published var isShowingResult = false
    @Published var isPreparingQuiz = false
    @Published var preparedQuestions: [QuizQuestion] = []
    @Published var plannedQuestionCount = 0
    @Published var isLoadingRemainingQuestions = false

    var quizPreparationGeneration = 0
    var questionPrebuildGeneration = 0
    var quizMergeGeneration = 0
    var reusedCandidateIDs: Set<String> = []
    var lastMergedItemsRequest: MergeRequest?

    struct MergeRequest: Equatable {
        let listIDs: [UUID]
        let direction: Direction
    }
}
