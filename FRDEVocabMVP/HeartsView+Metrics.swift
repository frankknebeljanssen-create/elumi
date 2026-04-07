import SwiftUI

extension HeartsView {
    var displayName: String {
        firstName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var currentLevel: ElumiLevelTier {
        elumiLevelTier(for: collectedXP)
    }

    var nextLevel: ElumiLevelTier? {
        nextElumiLevelTier(for: collectedXP)
    }

    var xpToNextLevel: Int {
        guard let nextLevel else { return 0 }
        return max(0, nextLevel.threshold - collectedXP)
    }

    var levelProgress: CGFloat {
        guard let nextLevel else { return 1 }
        let lowerBound = currentLevel.threshold
        let span = max(1, nextLevel.threshold - lowerBound)
        let progress = CGFloat(collectedXP - lowerBound) / CGFloat(span)
        return min(max(progress, 0), 1)
    }

    var activeMultiplier: Double {
        elumiStreakMultiplier(for: currentStreak)
    }

    var nextStreakMilestone: Int? {
        if currentStreak < 7 {
            return 7
        }
        if currentStreak < 30 {
            return 30
        }
        return nil
    }

    var totalWordsCount: Int {
        listStore.allLists
            .flatMap(\.items)
            .filter { $0.cardType == .words }
            .count
    }

    var totalPhrasesCount: Int {
        listStore.allLists
            .flatMap(\.items)
            .filter { $0.cardType == .phrases }
            .count
    }

    var heroSubtitle: String {
        if let nextLevel {
            return "Noch \(xpToNextLevel) XP bis \(nextLevel.title)"
        }

        return "Level 5 erreicht. Elumi ist beeindruckt."
    }

    var introSubtitle: String {
        if displayName.isEmpty {
            return "Dein Spielstand und dein Lernfortschritt."
        }

        return "Dein Spielstand und dein Lernfortschritt, \(displayName)."
    }

    var streakSubtitle: String {
        if let nextStreakMilestone {
            return "Noch \(max(0, nextStreakMilestone - currentStreak)) Tage bis zum nächsten Streak-Meilenstein"
        }

        return "30+ Tage Streak. Würmchen-Multiplikator ist maximal."
    }
}
