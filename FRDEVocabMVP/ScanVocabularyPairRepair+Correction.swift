import Foundation

extension ScanVocabularyPairRepair {
    func correctedPairIfNeeded(
        source: String,
        target: String,
        sourceLanguage: StudyLanguage
    ) -> (String, String) {
        if let templatePair = canonicalTemplatePairIfNeeded(
            source: source,
            target: target,
            sourceLanguage: sourceLanguage
        ) {
            return templatePair
        }

        let rawCleanedSource = canonicalizedSourceTermIfNeeded(
            normalizedSourceTermForCorrection(
                dependencies.extractedDisplayTerm(source),
                sourceLanguage: sourceLanguage
            ),
            sourceLanguage: sourceLanguage
        )
        let cleanedTarget = dependencies.extractedDisplayTerm(target)

        guard let localMatch = bestLocalTranslationMatch(for: rawCleanedSource, sourceLanguage: sourceLanguage) else {
            return (source, target)
        }

        let cleanedSource = localMatch.sourceTerm
        let suggestions = localMatch.suggestions
        let cardType = dependencies.inferredCardType(cleanedSource, cleanedTarget)
        let prioritizedSuggestions = prioritizedGermanSuggestions(
            suggestions,
            forSource: cleanedSource,
            cardType: cardType
        )

        guard !cleanedSource.isEmpty, !cleanedTarget.isEmpty, !suggestions.isEmpty else {
            return (source, target)
        }

        if let reverseMatch = bestReverseFrenchLexiconMatch(
            forGermanTarget: cleanedTarget,
            cardType: cardType
        ), shouldPreferReverseFrenchLexiconMatch(
            reverseMatch,
            currentSource: cleanedSource,
            currentTarget: cleanedTarget,
            sourceLanguage: sourceLanguage,
            cardType: cardType
        ) {

            return (reverseMatch.sourceTerm, reverseMatch.targetTerm)
        }

        let preferredSource: String
        if localMatch.matchDistance <= 0.18 &&
            !shouldPreserveScannedSourceText(
                source,
                insteadOf: cleanedSource,
                sourceLanguage: sourceLanguage
            ) {
            preferredSource = cleanedSource
        } else {
            preferredSource = source
        }

        let assessment = makeExistingTargetAssessment(
            cleanedSource: cleanedSource,
            cleanedTarget: cleanedTarget,
            sourceLanguage: sourceLanguage,
            cardType: cardType,
            prioritizedSuggestions: prioritizedSuggestions
        )

        if !assessment.normalizedTarget.isEmpty &&
            assessment.normalizedSuggestionSet.contains(assessment.normalizedTarget) {

            return (preferredSource, assessment.normalizedExistingTarget)
        }

        guard shouldUseSuggestedTarget(
            assessment,
            localMatchDistance: localMatch.matchDistance
        ) else {

            return (preferredSource, assessment.normalizedExistingTarget)
        }


        return (preferredSource, assessment.bestSuggestedTarget)
    }
}
