import Foundation

extension ScanImportNormalizer {
    func normalizedSourceImportTerm(
        _ text: String,
        sourceLanguage: StudyLanguage
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let normalizedSource: String
        if sourceLanguage == .english || dependencies.looksLikeEnglishInfinitiveMarker(trimmed) {
            normalizedSource = dependencies.normalizedEnglishVerbMarker(trimmed)
        } else {
            normalizedSource = trimmed
        }

        let canonicalized = dependencies.canonicalizedSourceTermIfNeeded(
            normalizedSource,
            sourceLanguage
        )

        guard sourceLanguage == .french else { return canonicalized }
        let inferredDisplay = dependencies.sourceDisplayText(canonicalized, .french)
        if let punctuation = dependencies.detectedTerminalSentencePunctuation(text) {
            return dependencies.applyingTerminalSentencePunctuation(
                punctuation,
                inferredDisplay,
                .french
            )
        }
        return inferredDisplay
    }
}
