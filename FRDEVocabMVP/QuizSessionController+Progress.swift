import Foundation

extension QuizSessionController {
    func completeCurrentQuestion(correct: Bool) {
        answeredResults.append(correct)

        if currentQuestionIndex + 1 >= questions.count {
            if isLoadingRemainingQuestions {
                currentQuestionIndex += 1
            } else {
                isShowingResult = true
            }
        } else {
            currentQuestionIndex += 1
        }
    }

    func resetToSetup() {
        if !questions.isEmpty {
            reusedCandidateIDs.formUnion(QuizBuildService.consumedCandidateIDs(from: questions))
        }
        quizPreparationGeneration += 1
        isPreparingQuiz = false
        questions = []
        currentQuestionIndex = 0
        answeredResults = []
        isShowingResult = false
        preparedQuestions = []
        plannedQuestionCount = 0
        isLoadingRemainingQuestions = false
    }
}
