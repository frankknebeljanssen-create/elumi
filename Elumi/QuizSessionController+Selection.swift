import Foundation

extension QuizSessionController {
    var canStartQuiz: Bool {
        cachedMergedItems.count >= 2
    }

    var currentQuestion: QuizQuestion? {
        guard questions.indices.contains(currentQuestionIndex) else { return nil }
        return questions[currentQuestionIndex]
    }

    var displayedQuestionCount: Int {
        max(plannedQuestionCount, questions.count)
    }

    var correctCount: Int {
        answeredResults.filter { $0 }.count
    }

    var wrongCount: Int {
        answeredResults.count - correctCount
    }
}
