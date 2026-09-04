import Foundation

struct ScanExtractedTermComponents: Equatable {
    let display: String
    let phonetic: String?
}

struct ScanOCRTermExtractorDependencies {
    let sanitizedLine: (String) -> String
    let cleanedQuizDisplayText: (String) -> String
    let normalizedLookupWords: (String) -> [String]
    let preservingTerminalSentencePunctuation: (String, String, CardType?) -> String
    let sourceLexiconCoverageScore: (String, StudyLanguage) -> Double
    let germanDictionaryCoverageScore: (String) -> Double
    let normalizedLookupText: (String) -> String
    let normalizedWords: (String) -> [String]
}

struct ScanOCRTermExtractor {
    let dependencies: ScanOCRTermExtractorDependencies

    func extractedDisplayTerm(
        from text: String,
        sourceLanguage: StudyLanguage
    ) -> String {
        extractedTermComponents(from: text, sourceLanguage: sourceLanguage).display
    }

    func extractedTermComponents(
        from text: String,
        sourceLanguage: StudyLanguage
    ) -> ScanExtractedTermComponents {
        let rawSanitized = dependencies.sanitizedLine(text)
        let cleaned = dependencies.cleanedQuizDisplayText(rawSanitized)
        guard !cleaned.isEmpty else {
            return ScanExtractedTermComponents(display: "", phonetic: nil)
        }

        let trimmedCleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if isLikelyPedagogicalAnnotationSegment(trimmedCleaned) {
            return ScanExtractedTermComponents(display: "", phonetic: nil)
        }

        if (trimmedCleaned.hasPrefix("[") || trimmedCleaned.hasPrefix("/")) &&
            isLikelyPhoneticSegment(trimmedCleaned, sourceLanguage: sourceLanguage) {
            return ScanExtractedTermComponents(display: "", phonetic: trimmedCleaned)
        }

        let pattern = #"\[[^\[\]]+\]|\/[^\/]+\/|\([^\(\)]+\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return ScanExtractedTermComponents(display: cleaned, phonetic: nil)
        }

        let nsRange = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
        let matches = regex.matches(in: cleaned, options: [], range: nsRange)
        guard !matches.isEmpty else {
            return ScanExtractedTermComponents(display: cleaned, phonetic: nil)
        }

        var display = cleaned
        var phoneticParts: [String] = []

        for match in matches.reversed() {
            guard let sourceRange = Range(match.range, in: cleaned) else { continue }
            let rawSegment = String(cleaned[sourceRange])
            let shouldStripAsPhonetic = isLikelyPhoneticSegment(
                rawSegment,
                sourceLanguage: sourceLanguage
            )
            let shouldStripAsPedagogicalMarker = isLikelyPedagogicalAnnotationSegment(rawSegment)
            guard shouldStripAsPhonetic || shouldStripAsPedagogicalMarker else { continue }

            if shouldStripAsPhonetic {
                let phonetic = rawSegment
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]()/ "))
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !phonetic.isEmpty {
                    phoneticParts.insert(phonetic, at: 0)
                }
            }

            if let displayRange = Range(match.range, in: display) {
                display.removeSubrange(displayRange)
            }
        }

        let cleanedDisplay = strippingPedagogicalUsageNotes(
            from: dependencies.cleanedQuizDisplayText(
                removingBracketedPedagogicalSegments(
                    from: display
                )
                    .replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ",;")))
            )
        )

        guard !isStandalonePedagogicalMarker(cleanedDisplay) else {
            return ScanExtractedTermComponents(
                display: "",
                phonetic: phoneticParts.isEmpty ? nil : phoneticParts.joined(separator: " ")
            )
        }

        let displayCardTypeHint: CardType? =
            dependencies.normalizedLookupWords(cleanedDisplay).count > 1 ? .phrases : .words
        let punctuatedDisplay = dependencies.preservingTerminalSentencePunctuation(
            rawSanitized,
            cleanedDisplay,
            displayCardTypeHint
        )

        return ScanExtractedTermComponents(
            display: punctuatedDisplay,
            phonetic: phoneticParts.isEmpty ? nil : phoneticParts.joined(separator: " ")
        )
    }

    func isLikelyPhoneticSegment(
        _ segment: String,
        sourceLanguage: StudyLanguage
    ) -> Bool {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 3 else { return false }

        let stripped = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]()/ "))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stripped.isEmpty else { return false }

        if trimmed.hasPrefix("[") || trimmed.hasPrefix("/") {
            return true
        }

        let phoneticHintPattern = #"[ˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ]"#
        if trimmed.range(of: phoneticHintPattern, options: .regularExpression) != nil {
            return true
        }

        let isParenthesized = trimmed.hasPrefix("(") && trimmed.hasSuffix(")")
        guard isParenthesized else { return false }

        let tokenCount = stripped.split(separator: " ").count
        let hasDigits = stripped.rangeOfCharacter(from: .decimalDigits) != nil
        let lowercaseLike = stripped == stripped.lowercased()
        let sourceCoverage = dependencies.sourceLexiconCoverageScore(stripped, sourceLanguage)
        let germanCoverage = dependencies.germanDictionaryCoverageScore(stripped)
        let transcriptionLikePattern = #"^[a-zàâçéèêëîïôùûüÿœæəɑɔɛɪʊʃʒɲˈˌ' -]+$"#

        return !hasDigits &&
            lowercaseLike &&
            tokenCount <= 3 &&
            sourceCoverage < 0.18 &&
            germanCoverage < 0.18 &&
            stripped.range(of: transcriptionLikePattern, options: .regularExpression) != nil
    }

    func isStandalonePedagogicalMarker(_ text: String) -> Bool {
        isLikelyPedagogicalAnnotationSegment(text)
    }

    func strippingPedagogicalUsageNotes(from text: String) -> String {
        guard !text.isEmpty else { return text }

        return removingBracketedPedagogicalSegments(from: text)
            .replacingOccurrences(
                of: #"(?iu)^\s*hier:\s*"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?iu)\s+(?:(?:adj|adv|inv|fam|form|fig|ugs|hist|no\s*pl|pl)\.?\s*)+$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?iu)\s+(?:adj\.\s*inv\.?\s*fam\.?|adj\.\s*inv\.?|inv\.?\s*fam\.?)$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?iu)^\s*(?:(?:adj|adv|inv|fam|form|fig|ugs|hist|no\s*pl|pl)\.?\s*)+$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?iu)\s*[,;:]\s*(?:(?:adj|adv|inv|fam|form|fig|ugs|hist|no\s*pl|n\s*pl|pl)\.?\s*)+$"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isLikelyPedagogicalAnnotationSegment(_ text: String) -> Bool {
        let stripped = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]()/.,;: "))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let normalizedCompact = dependencies.normalizedLookupText(stripped)
            .replacingOccurrences(of: " ", with: "")
        guard !normalizedCompact.isEmpty else { return true }

        let exactMarkers: Set<String> = [
            "fam", "adj", "adv", "inv", "fig", "form", "ugs", "hist",
            "pl", "nopl", "npl", "adjinv", "adjinvfam", "invfam", "adjfam"
        ]

        if exactMarkers.contains(normalizedCompact) {
            return true
        }

        let tokens = dependencies.normalizedWords(stripped)
        guard !tokens.isEmpty else { return true }

        let markerTokens: Set<String> = [
            "fam", "adj", "adv", "inv", "fig", "form", "ugs", "hist", "pl", "no", "n"
        ]

        return tokens.count <= 5 && tokens.allSatisfy { markerTokens.contains($0) }
    }

    private func removingBracketedPedagogicalSegments(from text: String) -> String {
        let pattern = #"\[[^\[\]]+\]|\([^\(\)]+\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        var result = text
        let nsRange = NSRange(result.startIndex..<result.endIndex, in: result)
        let matches = regex.matches(in: result, options: [], range: nsRange)

        for match in matches.reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let segment = String(result[range])
            guard isLikelyPedagogicalAnnotationSegment(segment) else { continue }
            result.removeSubrange(range)
        }

        return result
    }
}
