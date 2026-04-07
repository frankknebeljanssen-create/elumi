import Foundation

extension ScanVocabularyPairRepair {
    func prioritizedGermanSuggestions(
        _ suggestions: [String],
        forSource source: String,
        cardType: CardType
    ) -> [String] {
        guard suggestions.count > 1 else { return suggestions }
        guard let sourcePunctuation = dependencies.detectedTerminalSentencePunctuation(source) else {
            return suggestions
        }

        return suggestions.sorted { lhs, rhs in
            let lhsScore = germanSuggestionPunctuationScore(
                lhs,
                matching: sourcePunctuation,
                cardType: cardType
            )
            let rhsScore = germanSuggestionPunctuationScore(
                rhs,
                matching: sourcePunctuation,
                cardType: cardType
            )

            if lhsScore == rhsScore {
                return lhs.count < rhs.count
            }
            return lhsScore > rhsScore
        }
    }

    func germanSuggestionPunctuationScore(
        _ suggestion: String,
        matching sourcePunctuation: String,
        cardType: CardType
    ) -> Int {
        let detectedSuggestionPunctuation = dependencies.detectedTerminalSentencePunctuation(suggestion)
        let inferredSuggestionPunctuation = dependencies.inferredGermanTerminalSentencePunctuation(
            suggestion,
            cardType
        )

        if sourcePunctuation.contains("?") {
            if detectedSuggestionPunctuation?.contains("?") == true { return 6 }
            if inferredSuggestionPunctuation?.contains("?") == true { return 5 }
            if detectedSuggestionPunctuation?.contains(".") == true { return 1 }
            return 0
        }

        if sourcePunctuation.contains("!") {
            if detectedSuggestionPunctuation?.contains("!") == true { return 6 }
            if inferredSuggestionPunctuation?.contains("!") == true { return 5 }
            if detectedSuggestionPunctuation?.contains("?") == true { return 1 }
            return 0
        }

        if sourcePunctuation.contains(".") {
            if detectedSuggestionPunctuation?.contains(".") == true { return 6 }
            if inferredSuggestionPunctuation?.contains(".") == true { return 5 }
            if detectedSuggestionPunctuation?.contains("?") == true { return 1 }
            return 0
        }

        return 0
    }
}
