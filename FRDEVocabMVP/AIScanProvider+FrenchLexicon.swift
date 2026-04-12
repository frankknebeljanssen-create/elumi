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
        // Skip lexicon replacement if punctuation mismatch (ça va ≠ Ça va?)
        // Terminal punctuation is meaning-bearing — trust the AI's translation
        let trimmedSource = entry.source.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceHasPunctuation = trimmedSource.hasSuffix("?") || trimmedSource.hasSuffix(".") || trimmedSource.hasSuffix("!")
        if sourceHasPunctuation { return entry }

        if let trimmedSourceMatch = bestTrimmedFrenchLexiconMatch(forSource: entry.source),
           shouldForceFrenchLexiconReplacement(
                entry,
                sourceMatch: trimmedSourceMatch,
                sourceWasTrimmed: true
           ) {
            print("📡 [Lexicon] REPLACE (trimmed) '\(entry.source) → \(entry.target)' WITH '\(trimmedSourceMatch.sourceTerm) → \(trimmedSourceMatch.suggestions[0])' dist=\(trimmedSourceMatch.distance)")
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
            print("📡 [Lexicon] REPLACE (source) '\(entry.source) → \(entry.target)' WITH '\(sourceMatch.sourceTerm) → \(sourceMatch.suggestions[0])' dist=\(sourceMatch.distance)")
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
            print("📡 [Lexicon] REPLACE (reverse) '\(entry.source) → \(entry.target)' WITH '\(reverseMatch.sourceTerm) → \(reverseMatch.targetTerm)' dist=\(reverseMatch.distance)")
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
