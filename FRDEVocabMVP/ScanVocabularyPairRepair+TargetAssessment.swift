import Foundation

extension ScanVocabularyPairRepair {
    struct ExistingTargetAssessment {
        let normalizedExistingTarget: String
        let normalizedSuggestionSet: Set<String>
        let bestSuggestedTarget: String
        let pairScore: Double
        let suggestedPairScore: Double
        let normalizedSource: String
        let normalizedTarget: String
        let sourceWordCount: Int
        let targetWordCount: Int
        let suggestedTargetWordCount: Int
        let isSuspiciousShortTarget: Bool
        let isSuspiciousAllCapsTarget: Bool
        let hasWeakGermanCoverage: Bool
        let targetLooksLikeSourceLanguage: Bool
        let targetLooksLikeMarkerNoise: Bool
        let targetLooksLikeOCRCorruption: Bool
        let targetContainsSourceLexiconWords: Bool
        let targetContainsEmbeddedSource: Bool
        let targetLooksMixedLanguage: Bool
    }

    func makeExistingTargetAssessment(
        cleanedSource: String,
        cleanedTarget: String,
        sourceLanguage: StudyLanguage,
        cardType: CardType,
        prioritizedSuggestions: [String]
    ) -> ExistingTargetAssessment {
        let normalizedExistingTarget = dependencies.canonicalizedGermanTargetIfNeeded(
            cleanedTarget,
            cleanedSource,
            cardType,
            sourceLanguage
        )

        let pairScore = vocabularyPairScore(
            source: cleanedSource,
            target: normalizedExistingTarget,
            sourceLanguage: sourceLanguage
        )
        let normalizedSource = dependencies.normalizedLookupText(cleanedSource)
        let normalizedTarget = dependencies.normalizedLookupText(normalizedExistingTarget)
        let normalizedSuggestionSet = Set(prioritizedSuggestions.map(dependencies.normalizedLookupText))
        let normalizedTargetWords = dependencies.normalizedWords(normalizedExistingTarget)
        let targetWordCount = normalizedTargetWords.count
        let isSuspiciousShortTarget =
            targetWordCount == 1 && normalizedExistingTarget.count <= 3
        let isSuspiciousAllCapsTarget =
            normalizedExistingTarget.range(
                of: #"^[A-ZÄÖÜ][A-ZÄÖÜa-zäöü]{1,3}$"#,
                options: .regularExpression
            ) != nil
        let hasWeakGermanCoverage =
            dependencies.germanDictionaryCoverageScore(normalizedExistingTarget) < 0.35
        let targetLooksLikeSourceLanguage =
            dependencies.sourceLanguageScore(normalizedExistingTarget, sourceLanguage)
            > dependencies.germanScore(normalizedExistingTarget) + 0.1
        let targetLooksLikeMarkerNoise = isLikelyMarkerNoise(normalizedExistingTarget)
        let targetLooksLikeOCRCorruption = isLikelyOCRCorruptedWordToken(normalizedExistingTarget)
        let targetContainsSourceLexiconWords =
            dependencies.sourceLexiconCoverageScore(normalizedExistingTarget, sourceLanguage) > 0.22
        let targetContainsEmbeddedSource =
            !normalizedSource.isEmpty && normalizedTarget.contains(normalizedSource)
        let targetLooksMixedLanguage =
            targetWordCount >= 2 &&
            (targetContainsSourceLexiconWords || targetContainsEmbeddedSource) &&
            dependencies.germanDictionaryCoverageScore(normalizedExistingTarget) < 0.68
        let sourceWordCount = max(1, dependencies.normalizedWords(cleanedSource).count)
        let bestSuggestedTarget = dependencies.germanDisplayText(
            prioritizedSuggestions[0],
            cardType,
            cleanedSource
        )
        let suggestedTargetWordCount = max(1, dependencies.normalizedWords(bestSuggestedTarget).count)
        let suggestedPairScore = vocabularyPairScore(
            source: cleanedSource,
            target: bestSuggestedTarget,
            sourceLanguage: sourceLanguage
        )

        return ExistingTargetAssessment(
            normalizedExistingTarget: normalizedExistingTarget,
            normalizedSuggestionSet: normalizedSuggestionSet,
            bestSuggestedTarget: bestSuggestedTarget,
            pairScore: pairScore,
            suggestedPairScore: suggestedPairScore,
            normalizedSource: normalizedSource,
            normalizedTarget: normalizedTarget,
            sourceWordCount: sourceWordCount,
            targetWordCount: targetWordCount,
            suggestedTargetWordCount: suggestedTargetWordCount,
            isSuspiciousShortTarget: isSuspiciousShortTarget,
            isSuspiciousAllCapsTarget: isSuspiciousAllCapsTarget,
            hasWeakGermanCoverage: hasWeakGermanCoverage,
            targetLooksLikeSourceLanguage: targetLooksLikeSourceLanguage,
            targetLooksLikeMarkerNoise: targetLooksLikeMarkerNoise,
            targetLooksLikeOCRCorruption: targetLooksLikeOCRCorruption,
            targetContainsSourceLexiconWords: targetContainsSourceLexiconWords,
            targetContainsEmbeddedSource: targetContainsEmbeddedSource,
            targetLooksMixedLanguage: targetLooksMixedLanguage
        )
    }
}
