import Foundation

extension AIScanProvider {
    func shouldForceFrenchLexiconReplacement(
        _ entry: ScanAIResponseEntry,
        sourceMatch: (sourceTerm: String, suggestions: [String], distance: Double),
        sourceWasTrimmed: Bool
    ) -> Bool {
        guard let firstSuggestion = sourceMatch.suggestions.first, !firstSuggestion.isEmpty else {
            return false
        }

        if targetMatchesSuggestions(entry.target, suggestions: sourceMatch.suggestions) {
            return sourceWasTrimmed
        }

        let sourceWordCount = max(1, aiNormalizedWords(sourceMatch.sourceTerm).count)
        let targetWordCount = aiNormalizedWords(entry.target).count
        let suggestionWordCount = max(1, aiNormalizedWords(firstSuggestion).count)

        if sourceWasTrimmed {
            return true
        }

        if sourceMatch.distance <= 0.08 && sourceWordCount <= 2 {
            return true
        }

        if targetLooksSuspicious(
            entry.target,
            canonicalSource: sourceMatch.sourceTerm,
            firstSuggestion: firstSuggestion
        ) {
            return true
        }

        if sourceWordCount == 1 && suggestionWordCount == 1 && targetWordCount >= 2 {
            return true
        }

        return false
    }

    func targetLooksSuspicious(
        _ target: String,
        canonicalSource: String,
        firstSuggestion: String
    ) -> Bool {
        let normalizedTarget = aiNormalizedLookupText(target)
        guard !normalizedTarget.isEmpty else { return true }

        let compactTarget = aiCompactLookupKey(target)
        let compactSource = aiCompactLookupKey(canonicalSource)
        let targetWords = aiNormalizedWords(target)
        let suggestionWords = aiNormalizedWords(firstSuggestion)

        if target.rangeOfCharacter(from: .decimalDigits) != nil {
            return true
        }

        if aiLooksLikeMarkerNoise(normalizedTarget) || aiLooksLikeOCRCorruptedWordToken(normalizedTarget) {
            return true
        }

        if !compactSource.isEmpty && compactTarget.contains(compactSource) {
            return true
        }

        if targetWords.count >= suggestionWords.count + 2 {
            return true
        }

        return false
    }

    func targetMatchesSuggestions(
        _ target: String,
        suggestions: [String]
    ) -> Bool {
        let normalizedTarget = aiNormalizedLookupText(target)
        let compactTarget = aiCompactLookupKey(target)
        guard !normalizedTarget.isEmpty else { return false }

        return suggestions.contains {
            aiNormalizedLookupText($0) == normalizedTarget ||
            (!compactTarget.isEmpty && aiCompactLookupKey($0) == compactTarget)
        }
    }

    func shouldForceReverseFrenchLexiconReplacement(
        _ entry: ScanAIResponseEntry,
        reverseMatch: (sourceTerm: String, targetTerm: String, distance: Double)
    ) -> Bool {
        if reverseMatch.distance > 0.26 {
            return false
        }

        if targetMatchesSuggestions(entry.target, suggestions: [reverseMatch.targetTerm]) {
            return false
        }

        let sourceMatch = bestFrenchLexiconMatch(forSource: entry.source)
        let sourceLooksWeak = sourceMatch == nil || sourceMatch?.distance ?? 1 > 0.22
        return sourceLooksWeak || targetLooksSuspicious(
            entry.target,
            canonicalSource: reverseMatch.sourceTerm,
            firstSuggestion: reverseMatch.targetTerm
        )
    }

    func aiTrailingLooksSuspicious(_ trailing: String) -> Bool {
        let normalized = aiNormalizedLookupText(trailing)
        guard !normalized.isEmpty else { return false }

        let tokens = normalized.split(separator: " ").map(String.init)
        let compact = normalized.replacingOccurrences(of: " ", with: "")
        let vowelCount = compact.filter { "aeiouyàâäæéèêëîïôöœùûü".contains($0) }.count
        let consonantCount = compact.filter(\.isLetter).count - vowelCount

        if tokens.allSatisfy({ aiLooksLikeMarkerNoise($0) || aiLooksLikeOCRCorruptedWordToken($0) }) {
            return true
        }

        if compact.range(of: #"^(?:adj|inv|fam|form|fom|fon){2,}[a-z]*$"#, options: .regularExpression) != nil {
            return true
        }

        if compact.count >= 5 && consonantCount >= 4 && vowelCount <= 1 {
            return true
        }

        return false
    }

    func aiLooksLikeMarkerNoise(_ text: String) -> Bool {
        let normalized = aiNormalizedLookupText(text)
        guard !normalized.isEmpty else { return true }

        let exactNoise = [
            "fam", "adj", "adv", "inv", "fig", "form", "ugs", "hist", "pl",
            "adjinv", "adjinvfam", "invfam", "adjfam", "nopl",
            "fom", "fon", "fqm", "f0m", "adjinvfom", "invfom", "adjfom"
        ]

        if exactNoise.contains(normalized) {
            return true
        }

        return normalized.range(of: #"^[a-z]{1,2}$"#, options: .regularExpression) != nil
    }

    func aiLooksLikeOCRCorruptedWordToken(_ text: String) -> Bool {
        let normalized = aiNormalizedLookupText(text)
        guard !normalized.isEmpty else { return false }

        return normalized
            .split(separator: " ")
            .map(String.init)
            .contains { token in
                let digitCount = token.filter(\.isNumber).count
                let letterCount = token.filter(\.isLetter).count

                guard digitCount >= 1, letterCount >= 1, token.count >= 2 else { return false }
                guard token.range(of: #"^[a-z0-9]+$"#, options: .regularExpression) != nil else { return false }
                if digitCount >= 2 && token.count >= 4 { return true }
                let digitRatio = Double(digitCount) / Double(token.count)
                return digitRatio >= 0.34
            }
    }
}
