import Foundation

extension ScanVocabularyPairRepair {
    func shouldUseSuggestedTarget(
        _ assessment: ExistingTargetAssessment,
        localMatchDistance: Double
    ) -> Bool {
        let shouldPreferSuggestedTarget =
            !assessment.normalizedSuggestionSet.contains(assessment.normalizedTarget) &&
            localMatchDistance <= 0.34 &&
            assessment.suggestedPairScore > assessment.pairScore + 0.32

        let shouldForceDictionaryReplacement =
            localMatchDistance <= 0.34 &&
            (
                assessment.targetContainsEmbeddedSource ||
                assessment.targetLooksMixedLanguage ||
                (assessment.targetWordCount >= 2 && assessment.hasWeakGermanCoverage) ||
                assessment.targetLooksLikeSourceLanguage ||
                assessment.targetLooksLikeMarkerNoise ||
                assessment.targetLooksLikeOCRCorruption
            ) &&
            assessment.suggestedPairScore >= assessment.pairScore

        let shouldForceExactSourceLexiconReplacement =
            localMatchDistance <= 0.08 &&
            assessment.sourceWordCount <= 3 &&
            !assessment.normalizedSuggestionSet.contains(assessment.normalizedTarget) &&
            (
                assessment.targetLooksMixedLanguage ||
                assessment.targetLooksLikeSourceLanguage ||
                assessment.targetLooksLikeMarkerNoise ||
                assessment.targetLooksLikeOCRCorruption ||
                assessment.hasWeakGermanCoverage ||
                assessment.pairScore < 1.72 ||
                assessment.targetWordCount > assessment.sourceWordCount + 1 ||
                (
                    assessment.sourceWordCount == 1 &&
                    assessment.suggestedTargetWordCount == 1 &&
                    assessment.targetWordCount >= 2
                )
            ) &&
            assessment.suggestedPairScore >= assessment.pairScore - 0.12

        return
            assessment.pairScore < 1.1 ||
            assessment.isSuspiciousShortTarget ||
            assessment.isSuspiciousAllCapsTarget ||
            assessment.hasWeakGermanCoverage ||
            assessment.targetLooksLikeSourceLanguage ||
            assessment.targetLooksLikeMarkerNoise ||
            assessment.targetLooksLikeOCRCorruption ||
            assessment.targetContainsSourceLexiconWords ||
            shouldPreferSuggestedTarget ||
            shouldForceDictionaryReplacement ||
            shouldForceExactSourceLexiconReplacement
    }
}
