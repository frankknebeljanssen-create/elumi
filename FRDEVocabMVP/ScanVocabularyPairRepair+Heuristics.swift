import Foundation

extension ScanVocabularyPairRepair {
    func isLikelyMarkerNoise(_ text: String) -> Bool {
        let normalized = dependencies.normalizedLookupText(text)
        guard !normalized.isEmpty else { return true }

        let exactNoise = [
            "to", "co", "eil", "ii", "il", "io", "lo", "do", "go", "no", "so",
            "fam", "adj", "adv", "inv", "fig", "form", "ugs", "hist", "pl",
            "adjinv", "adjinvfam", "invfam", "adjfam", "nopl",
            "fom", "fon", "fqm", "f0m", "adjinvfom", "invfom", "adjfom"
        ]

        if exactNoise.contains(normalized) {
            return true
        }

        if normalized.range(of: #"^[a-z]{1,2}$"#, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    func looksLikeLowQualitySourceTail(_ text: String) -> Bool {
        let normalized = dependencies.normalizedLookupText(text)
        guard !normalized.isEmpty else { return false }

        let compact = normalized.replacingOccurrences(of: " ", with: "")
        guard !compact.isEmpty else { return false }

        let vowelCount = compact.filter { "aeiouyàâäæéèêëîïôöœùûü".contains($0) }.count
        let consonantCount = compact.filter { $0.isLetter }.count - vowelCount
        let tokens = normalized.split(separator: " ").map(String.init)

        if compact.range(of: #"^[a-z]{5,}$"#, options: .regularExpression) != nil &&
            consonantCount >= 4 &&
            vowelCount <= 1 {
            return true
        }

        if compact.range(of: #"^(?:adj|inv|fam|form|fom|fon){2,}[a-z]*$"#, options: .regularExpression) != nil {
            return true
        }

        if tokens.count <= 2 &&
            tokens.allSatisfy({
                isLikelyMarkerNoise($0) ||
                isLikelyOCRCorruptedWordToken($0) ||
                ($0.count >= 5 && $0.filter { "aeiouy".contains($0) }.count <= 1)
            }) {
            return true
        }

        return false
    }

    func isLikelyOCRCorruptedWordToken(_ text: String) -> Bool {
        let normalized = dependencies.normalizedLookupText(text)
        guard !normalized.isEmpty else { return false }

        let tokens = normalized.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return false }

        return tokens.contains { token in
            let digitCount = token.filter(\.isNumber).count
            let letterCount = token.filter(\.isLetter).count

            guard digitCount >= 1, letterCount >= 1, token.count >= 2 else { return false }
            guard token.range(of: #"^[a-z0-9]+$"#, options: .regularExpression) != nil else { return false }

            if digitCount >= 2 && token.count >= 4 {
                return true
            }

            if digitCount == 1 && letterCount == 1 && token.count == 2 {
                return true
            }

            let digitRatio = Double(digitCount) / Double(token.count)
            return digitRatio >= 0.34
        }
    }

    func cognateSimilarityScore(source: String, target: String) -> Double {
        let left = dependencies.normalizedWords(source).joined()
        let right = dependencies.normalizedWords(target).joined()
        guard !left.isEmpty, !right.isEmpty else { return 0 }

        let distance = scanLevenshtein(left, right)
        let maxLength = max(left.count, right.count)
        guard maxLength > 0 else { return 0 }

        let similarity = 1.0 - (Double(distance) / Double(maxLength))
        return max(0, similarity) * 0.9
    }

    func normalizedLookupWords(_ text: String) -> [String] {
        dependencies.normalizedLookupText(text)
            .split(separator: " ")
            .map(String.init)
    }
}
