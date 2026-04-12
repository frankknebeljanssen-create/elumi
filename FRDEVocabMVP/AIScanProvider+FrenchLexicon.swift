import Foundation

extension AIScanProvider {
    func normalizedResponsePayload(
        _ response: ScanAIResponsePayload
    ) -> ScanAIResponsePayload {
        guard response.sourceLanguage == .french else { return response }

        let normalizedEntries = response.entries.map(normalizedFrenchEntry(_:))
        return ScanAIResponsePayload(
            documentType: response.documentType,
            mode: response.mode,
            sourceLanguage: response.sourceLanguage,
            entries: normalizedEntries,
            warnings: response.warnings,
            summary: response.summary,
            importMessage: response.importMessage,
            confidence: response.confidence,
            usedColumnPairing: response.usedColumnPairing,
            recognizedLineCount: response.recognizedLineCount
        )
    }

    private func normalizedFrenchEntry(
        _ entry: ScanAIResponseEntry
    ) -> ScanAIResponseEntry {
        // Skip lexicon replacement if source has terminal punctuation — trust AI
        if LexiconTextUtility.hasTerminalPunctuation(entry.source) { return entry }

        if let trimmedSourceMatch = bestTrimmedFrenchLexiconMatch(forSource: entry.source),
           shouldForceFrenchLexiconReplacement(
                entry,
                sourceMatch: trimmedSourceMatch,
                sourceWasTrimmed: true
           ) {

            return replacing(
                entry,
                source: trimmedSourceMatch.sourceTerm,
                target: trimmedSourceMatch.suggestions[0]
            )
        }

        if let sourceMatch = bestFrenchLexiconMatch(forSource: entry.source),
           shouldForceFrenchLexiconReplacement(
                entry,
                sourceMatch: sourceMatch,
                sourceWasTrimmed: false
           ) {

            return replacing(
                entry,
                source: sourceMatch.sourceTerm,
                target: sourceMatch.suggestions[0]
            )
        }

        if let reverseMatch = bestReverseFrenchLexiconMatch(
            forGermanTarget: entry.target,
            cardType: entry.cardType
        ), shouldForceReverseFrenchLexiconReplacement(entry, reverseMatch: reverseMatch) {

            return replacing(
                entry,
                source: reverseMatch.sourceTerm,
                target: reverseMatch.targetTerm
            )
        }

        return entry
    }

    private func replacing(
        _ entry: ScanAIResponseEntry,
        source: String,
        target: String
    ) -> ScanAIResponseEntry {
        ScanAIResponseEntry(
            source: source,
            target: target,
            cardType: entry.cardType,
            sourcePhonetic: entry.sourcePhonetic,
            targetPhonetic: entry.targetPhonetic,
            confidence: entry.confidence,
            reviewMetadata: entry.reviewMetadata,
            notes: entry.notes
        )
    }
}
