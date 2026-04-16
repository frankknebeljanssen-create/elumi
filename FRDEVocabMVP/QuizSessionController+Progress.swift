import Foundation

extension QuizSessionController {
    func completeCurrentQuestion(correct: Bool) {
        answeredResults.append(correct)

        // Combo-Tracking für ProgressService-Bonus (alle 5 richtig in Folge).
        if correct {
            sessionCurrentCombo += 1
            sessionLongestCombo = max(sessionLongestCombo, sessionCurrentCombo)
            GamificationFeedbackPresenter.shared.noteComboProgress(currentCombo: sessionCurrentCombo)
        } else {
            sessionCurrentCombo = 0
        }

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
        // Combo-Tracking zurücksetzen, damit nächste Session sauber startet.
        sessionCurrentCombo = 0
        sessionLongestCombo = 0
        sessionRewardConsumed = false
    }
}
