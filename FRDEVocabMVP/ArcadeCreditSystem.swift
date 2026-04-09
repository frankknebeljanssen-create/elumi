import Foundation

/// Credits earned from learning activities, spent to play the Arcade game.
///
/// Earning:
/// - Perfect/Complete session = 3 credits
/// - Good effort (>50% correct) = 2 credits
/// - At least tried (any activity) = 1 credit
///
/// Spending:
/// - 1 credit = 1 Arcade game (3 lives)
enum ArcadeCreditSystem {
    /// Calculate credits earned from a training/quiz/flashcard session
    static func creditsEarned(
        totalQuestions: Int,
        correctAnswers: Int,
        wrongAnswers: Int,
        isPerfect: Bool
    ) -> Int {
        guard totalQuestions > 0 else { return 0 }

        // Must have answered at least 3 questions to earn credits
        let totalAnswered = correctAnswers + wrongAnswers
        guard totalAnswered >= 3 else { return 0 }

        if isPerfect || wrongAnswers == 0 {
            return 3  // Perfect!
        }

        let ratio = Double(correctAnswers) / Double(totalAnswered)
        if ratio >= 0.5 {
            return 2  // Good effort
        }

        return 1  // At least tried
    }

    /// Credits from speed round
    static func speedRoundCredits(score: Int) -> Int {
        if score >= 25 { return 3 }
        if score >= 15 { return 2 }
        if score >= 5 { return 1 }
        return 0
    }

    /// Credits from flashcard mastery session
    static func flashcardCredits(
        masteredCount: Int,
        totalCount: Int,
        wrongCount: Int
    ) -> Int {
        guard masteredCount > 0 else { return 0 }

        if masteredCount == totalCount && wrongCount == 0 {
            return 3
        }

        let ratio = Double(masteredCount) / Double(max(1, totalCount))
        if ratio >= 0.5 {
            return 2
        }

        return 1
    }

    /// Cost to play one arcade game
    static let gamesCost = 1
}
