import Foundation

extension ScanReviewMapper {
    static func targetLooksSuspicious(
        _ target: String,
        canonicalSource: String,
        firstSuggestion: String
    ) -> Bool {
        let normalizedTarget = mapperNormalizedLookupText(target)
        guard !normalizedTarget.isEmpty else { return true }

        let compactTarget = mapperCompactLookupKey(target)
        let compactSource = mapperCompactLookupKey(canonicalSource)
        let targetWords = mapperNormalizedWords(target)
        let suggestionWords = mapperNormalizedWords(firstSuggestion)

        if target.rangeOfCharacter(from: .decimalDigits) != nil {
            return true
        }

        if mapperLooksLikeMarkerNoise(normalizedTarget) || mapperLooksLikeOCRCorruptedWordToken(normalizedTarget) {
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

    static func targetMatchesSuggestions(
        _ target: String,
        suggestions: [String]
    ) -> Bool {
        let normalizedTarget = mapperNormalizedLookupText(target)
        let compactTarget = mapperCompactLookupKey(target)
        guard !normalizedTarget.isEmpty else { return false }

        return suggestions.contains {
            mapperNormalizedLookupText($0) == normalizedTarget ||
            (!compactTarget.isEmpty && mapperCompactLookupKey($0) == compactTarget)
        }
    }

    static func mapperTrailingLooksSuspicious(_ trailing: String) -> Bool {
        let normalized = mapperNormalizedLookupText(trailing)
        guard !normalized.isEmpty else { return false }

        let tokens = normalized.split(separator: " ").map(String.init)
        let compact = normalized.replacingOccurrences(of: " ", with: "")
        let vowelCount = compact.filter { "aeiouyàâäæéèêëîïôöœùûü".contains($0) }.count
        let consonantCount = compact.filter(\.isLetter).count - vowelCount

        if tokens.allSatisfy({ mapperLooksLikeMarkerNoise($0) || mapperLooksLikeOCRCorruptedWordToken($0) }) {
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

    static func mapperLooksLikeMarkerNoise(_ text: String) -> Bool {
        let normalized = mapperNormalizedLookupText(text)
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

    static func mapperLooksLikeOCRCorruptedWordToken(_ text: String) -> Bool {
        let normalized = mapperNormalizedLookupText(text)
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
