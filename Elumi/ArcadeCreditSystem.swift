import Foundation

/// Credits earned from learning activities, spent to play the Arcade game.
///
/// **Game Loop Philosophy (User-Spec):**
/// Spiel ist eine **Belohnung** für Lernen, kein Standard-Nebenprodukt.
/// Nicht jede Session gibt ein Spiel — Spiele entstehen über:
///   • seltenere XP-Meilensteine (`xpPerCredit = 250`, also ca. jede
///     zweite bis dritte Session ein Spiel),
///   • Level-Ups (Pauschal-Bonus pro Level),
///   • Streak-Milestones (nach 3/7/14/30 Tagen Streak),
///   • Daily-Challenge-Abschluss (pro abgeschlossener Challenge),
///   • seltene Variable-Reward-Events.
///
/// Die Session-basierte 1–3-Credit-Logik (`creditsEarned`, `speedRoundCredits`,
/// `flashcardCredits`) bleibt als API bestehen, wird im aktuellen
/// ProgressService aber **nicht** direkt auf die Balance geschrieben —
/// stattdessen kommen Credits über `bonusCreditsFromXP` und die oben
/// genannten Event-Quellen. Das entspricht der Spec „NICHT jede
/// Session gibt ein Spiel".
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

    /// Zieht Credits ab — über den `ProgressStore`, nicht direkt über
    /// `@AppStorage`.
    ///
    /// **Codeaudit 2026-09-03, Stufe 2** — vorher schrieben fünf Stellen
    /// (`arcadeCredits -= …` in Arcade-Overlays, PlayCredits und Word
    /// Runner) nur den nackten `@AppStorage`-Key. Der `ProgressStore`
    /// erfuhr davon nichts und behielt seinen alten, höheren Stand.
    /// Beim nächsten `mutate` — also bei jedem Session-Abschluss —
    /// spiegelte `persist()` diesen Stand zurück in beide Slots und
    /// machte den Abzug rückgängig: Credits wurden faktisch erstattet.
    ///
    /// Der Store ist die Single Source of Truth; sein `persist()`
    /// schreibt den Bare-Key gleich mit, sodass alle
    /// `@AppStorage(appArcadeCreditsKey)`-Leser (Footer-Badge, GameHub,
    /// Overlays) den neuen Wert unmittelbar sehen.
    ///
    /// - Returns: Der Kontostand nach dem Abzug — zum Spiegeln in die
    ///   lokale `@AppStorage`-Property der aufrufenden View.
    @discardableResult
    @MainActor
    static func spendCredits(_ amount: Int = gamesCost) -> Int {
        ProgressStore.shared.mutate { progress in
            progress.arcadeCredits = max(0, progress.arcadeCredits - amount)
        }
        return ProgressStore.shared.progress.arcadeCredits
    }

    /// XP-Schwelle pro verdientem Spiel. Delegiert an die zentrale
    /// `GamificationConfig.xpPerBonusCredit` (Single-Source-of-Truth),
    /// damit ProgressService, SessionSetupEstimate, GameHub und alle
    /// weiteren Reader **denselben** Wert sehen. Änderung dort — hier
    /// automatisch mit.
    static var xpPerCredit: Int { GamificationConfig.xpPerBonusCredit }

    /// Check if XP milestone crossed, return bonus credits earned
    static func bonusCreditsFromXP(previousXP: Int, newXP: Int) -> Int {
        let previousMilestones = previousXP / xpPerCredit
        let newMilestones = newXP / xpPerCredit
        return max(0, newMilestones - previousMilestones)
    }
}
