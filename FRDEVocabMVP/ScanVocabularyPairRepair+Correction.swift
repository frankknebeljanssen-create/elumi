import Foundation

extension ScanVocabularyPairRepair {
    func correctedPairIfNeeded(
        source: String,
        target: String,
        sourceLanguage: StudyLanguage
    ) -> (String, String) {
        let isTracked = source.lowercased().contains("jaune") || target.lowercased().contains("gelb")

        if let templatePair = canonicalTemplatePairIfNeeded(
            source: source,
            target: target,
            sourceLanguage: sourceLanguage
        ) {
            if isTracked { print("📡 [Repair] '\(source) → \(target)' TEMPLATE → '\(templatePair.0) → \(templatePair.1)'") }
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
        if isTracked { print("📡 [Repair] '\(source) → \(target)' cleaned → '\(rawCleanedSource) → \(cleanedTarget)'") }

        guard let localMatch = bestLocalTranslationMatch(for: rawCleanedSource, sourceLanguage: sourceLanguage) else {
            if isTracked { print("📡 [Repair] '\(source)' no local match → keeping") }
            return (source, target)
        }

        let cleanedSource = localMatch.sourceTerm
        let suggestions = localMatch.suggestions
        if isTracked { print("📡 [Repair] localMatch: '\(rawCleanedSource)' → src='\(cleanedSource)' suggestions=\(suggestions) dist=\(localMatch.matchDistance)") }
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
            if isTracked { print("📡 [Repair] REVERSE REPLACE '\(source) → \(target)' WITH '\(reverseMatch.sourceTerm) → \(reverseMatch.targetTerm)'") }
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
            if isTracked { print("📡 [Repair] TARGET MATCHES suggestion → '\(preferredSource) → \(assessment.normalizedExistingTarget)'") }
            return (preferredSource, assessment.normalizedExistingTarget)
        }

        guard shouldUseSuggestedTarget(
            assessment,
            localMatchDistance: localMatch.matchDistance
        ) else {
            if isTracked { print("📡 [Repair] KEEP target → '\(preferredSource) → \(assessment.normalizedExistingTarget)'") }
            return (preferredSource, assessment.normalizedExistingTarget)
        }

        if isTracked { print("📡 [Repair] USE SUGGESTED → '\(preferredSource) → \(assessment.bestSuggestedTarget)'") }
        return (preferredSource, assessment.bestSuggestedTarget)
    }
}
