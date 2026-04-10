import Foundation

extension ScanImportNormalizer {
    func canonicalizedGermanTargetIfNeeded(
        _ target: String,
        source: String,
        cardType: CardType,
        sourceLanguage: StudyLanguage
    ) -> String {
        let cleanedTarget = dependencies.extractedDisplayTerm(target)
        guard !cleanedTarget.isEmpty else { return "" }

        func preservingOriginalTargetPunctuation(_ candidate: String) -> String {
            dependencies.preservingTerminalSentencePunctuation(target, candidate, cardType)
        }

        let canonicalSource = dependencies.canonicalizedSourceTermIfNeeded(source, sourceLanguage)
        let formattedTarget = preservingOriginalTargetPunctuation(
            dependencies.germanDisplayText(cleanedTarget, cardType, canonicalSource)
        )

        guard sourceLanguage == .french else { return formattedTarget }
        guard let localMatch = dependencies.bestLocalTranslationMatch(canonicalSource, sourceLanguage),
              !localMatch.suggestions.isEmpty else {
            return formattedTarget
        }

        // Skip vocabulary override if source has terminal punctuation (? . !)
        // The vocabulary lookup strips punctuation → "Ça va?" and "Ça va." match the same entry
        // but have completely different meanings. Trust Haiku's translation instead.
        let trimmedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSource.hasSuffix("?") || trimmedSource.hasSuffix(".") || trimmedSource.hasSuffix("!") {
            return formattedTarget
        }
        let prioritizedSuggestions = prioritizedGermanSuggestions(
            localMatch.suggestions,
            forSource: canonicalSource,
            cardType: cardType
        )

        if let matchedSuggestion = canonicalSuggestion(
            matching: formattedTarget,
            in: prioritizedSuggestions,
            cardType: cardType,
            sourceHint: canonicalSource
        ) {
            let preservedSuggestion = preservingOriginalTargetPunctuation(matchedSuggestion)
            if dependencies.shouldPreserveScannedGermanTargetText(cleanedTarget, preservedSuggestion) {
                return formattedTarget
            }
            return preservedSuggestion
        }

        guard shouldPreferCanonicalGermanSuggestion(
            currentTarget: formattedTarget,
            source: canonicalSource,
            sourceLanguage: sourceLanguage,
            matchDistance: localMatch.matchDistance
        ) else {
            return formattedTarget
        }

        let suggestedTarget = preservingOriginalTargetPunctuation(
            dependencies.germanDisplayText(prioritizedSuggestions[0], cardType, canonicalSource)
        )
        if dependencies.shouldPreserveScannedGermanTargetText(cleanedTarget, suggestedTarget) {
            return formattedTarget
        }
        return suggestedTarget
    }

    private func canonicalSuggestion(
        matching target: String,
        in suggestions: [String],
        cardType: CardType,
        sourceHint: String
    ) -> String? {
        let normalizedTarget = dependencies.normalizedLookupText(target)
        let compactTarget = dependencies.compactLookupKey(target)
        guard !normalizedTarget.isEmpty else { return nil }

        return suggestions.first {
            let normalizedSuggestion = dependencies.normalizedLookupText($0)
            return normalizedSuggestion == normalizedTarget ||
                (!compactTarget.isEmpty && dependencies.compactLookupKey($0) == compactTarget)
        }
        .map {
            dependencies.germanDisplayText($0, cardType, sourceHint)
        }
        ?? bestOCRConfusableGermanSuggestion(
            matching: target,
            in: suggestions,
            cardType: cardType,
            sourceHint: sourceHint
        )
    }

    private func bestOCRConfusableGermanSuggestion(
        matching target: String,
        in suggestions: [String],
        cardType: CardType,
        sourceHint: String
    ) -> String? {
        let compactTarget = dependencies.compactLookupKey(target)
        guard !compactTarget.isEmpty else { return nil }

        let shouldTryOCRConfusableMatch =
            dependencies.isLikelyOCRCorruptedWordToken(target) ||
            dependencies.germanDictionaryCoverageScore(target) < 0.36 ||
            target.rangeOfCharacter(from: .decimalDigits) != nil

        guard shouldTryOCRConfusableMatch else { return nil }

        let bestSuggestion = suggestions
            .map { suggestion -> (suggestion: String, similarity: Double) in
                (
                    suggestion,
                    dependencies.ocrConfusableSimilarityScore(
                        compactTarget,
                        dependencies.compactLookupKey(suggestion)
                    )
                )
            }
            .filter { candidate in
                let compactSuggestion = dependencies.compactLookupKey(candidate.suggestion)
                guard !compactSuggestion.isEmpty else { return false }

                let maxLength = max(compactTarget.count, compactSuggestion.count)
                let minimumSimilarity: Double = maxLength <= 3 ? 0.55 : 0.68
                return candidate.similarity >= minimumSimilarity
            }
            .max { lhs, rhs in
                lhs.similarity < rhs.similarity
            }

        return bestSuggestion.map {
            dependencies.germanDisplayText($0.suggestion, cardType, sourceHint)
        }
    }

    private func shouldPreferCanonicalGermanSuggestion(
        currentTarget: String,
        source: String,
        sourceLanguage: StudyLanguage,
        matchDistance: Double
    ) -> Bool {
        let pairScore = dependencies.vocabularyPairScore(
            source,
            currentTarget,
            sourceLanguage
        )
        let targetWordCount = normalizedWords(in: currentTarget).count
        let hasWeakGermanCoverage = dependencies.germanDictionaryCoverageScore(currentTarget) < 0.42
        let targetLooksLikeSourceLanguage =
            dependencies.sourceLanguageScore(currentTarget, sourceLanguage) >
            dependencies.germanScore(currentTarget) + 0.08
        let targetLooksLikeMarkerNoise = dependencies.isLikelyMarkerNoise(currentTarget)
        let targetLooksLikeOCRCorruption = dependencies.isLikelyOCRCorruptedWordToken(currentTarget)
        let targetContainsSourceLexiconWords =
            dependencies.sourceLexiconCoverageScore(currentTarget, sourceLanguage) > 0.22
        let isSuspiciousShortTarget = targetWordCount == 1 && currentTarget.count <= 3
        let isSuspiciousAllCapsTarget = currentTarget.range(
            of: #"^[A-ZÄÖÜ]{2,4}$"#,
            options: .regularExpression
        ) != nil

        if pairScore < 1.1 || isSuspiciousShortTarget || isSuspiciousAllCapsTarget {
            return true
        }

        if targetLooksLikeMarkerNoise ||
            targetLooksLikeOCRCorruption ||
            targetLooksLikeSourceLanguage ||
            targetContainsSourceLexiconWords {
            return true
        }

        if matchDistance <= 0.12 && hasWeakGermanCoverage {
            return true
        }

        return false
    }

    private func prioritizedGermanSuggestions(
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

    private func germanSuggestionPunctuationScore(
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

    private func normalizedWords(in text: String) -> [String] {
        dependencies.normalizedLookupText(text)
            .split(separator: " ")
            .map(String.init)
    }
}
