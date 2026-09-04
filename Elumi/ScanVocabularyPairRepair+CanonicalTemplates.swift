import Foundation

extension ScanVocabularyPairRepair {
    func canonicalTemplatePairIfNeeded(
        source: String,
        target: String,
        sourceLanguage: StudyLanguage
    ) -> (String, String)? {
        guard sourceLanguage == .french else { return nil }

        let cleanedSource = dependencies.extractedDisplayTerm(source)
        let cleanedTarget = dependencies.extractedDisplayTerm(target)
        let normalizedSource = dependencies.normalizedLookupText(cleanedSource)
        let normalizedTarget = dependencies.normalizedLookupText(cleanedTarget)

        let sourceLooksLikeNameTemplate =
            normalizedSource.contains("appel") &&
            hasPlaceholderLikeToken(
                in: cleanedSource,
                candidates: sourcePlaceholderTokens(for: .french)
            )

        let targetLooksLikeNameTemplate =
            (normalizedTarget.contains("heiss") ||
             normalizedTarget.contains("heis") ||
             normalizedTarget.contains("heiß")) &&
            hasPlaceholderLikeToken(
                in: cleanedTarget,
                candidates: germanPlaceholderTokens
            )

        guard sourceLooksLikeNameTemplate || targetLooksLikeNameTemplate else { return nil }

        return (
            applyingTemplatePunctuation(
                from: sourceLooksLikeNameTemplate ? cleanedSource : source,
                to: "Je m'appelle + Name",
                isFrench: true
            ),
            applyingTemplatePunctuation(
                from: targetLooksLikeNameTemplate ? cleanedTarget : target,
                to: "Ich heiße + Name",
                isFrench: false
            )
        )
    }

    func applyingTemplatePunctuation(
        from original: String,
        to template: String,
        isFrench: Bool
    ) -> String {
        let trimmedTemplate = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTemplate.isEmpty else { return trimmedTemplate }

        if original.contains("?") {
            return isFrench ? trimmedTemplate + " ?" : trimmedTemplate + "?"
        }

        if original.contains("!") {
            return isFrench ? trimmedTemplate + " !" : trimmedTemplate + "!"
        }

        if original.contains(".") {
            return trimmedTemplate + "."
        }

        return trimmedTemplate
    }
}
