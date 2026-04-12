import Foundation

extension ScanReviewMapper {
    static func makeAnalysisResult(from result: ScanProviderResult) -> ScanAnalysisResult {
        let reviewEntries = result.entries.map { entry in
            let reviewMetadata = resolvedReviewMetadata(for: entry)
            let reviewEntry = ScanReviewEntry(
                sourceText: entry.source,
                targetText: entry.target,
                cardType: entry.cardType,
                reviewMetadata: reviewMetadata
            )

            return normalizedReviewEntry(
                reviewEntry,
                mode: result.mode,
                sourceLanguage: result.sourceLanguage
            )
        }

        return ScanAnalysisResult(
            mode: result.mode,
            sourceLanguage: result.sourceLanguage,
            entries: reviewEntries,
            summary: result.summary,
            importMessage: result.importMessage,
            analysisPath: result.path,
            usedColumnPairing: result.usedColumnPairing,
            recognizedLineCount: result.recognizedLineCount,
            recognizedLines: result.recognizedBoxes.map(\.text)
        )
    }

    static func makeProviderResult(
        from analysis: ScanAnalysisResult,
        lineBoxes: [OCRLineBox],
        classifier: ScanDocumentClassifier,
        path: ScanAnalysisPath = .ocrOnly,
        warnings: [String] = [],
        confidence: Double = 0
    ) -> ScanProviderResult {
        ScanProviderResult(
            documentType: classifier.classify(analysis: analysis, lineBoxes: lineBoxes),
            path: path,
            mode: analysis.mode,
            sourceLanguage: analysis.sourceLanguage,
            entries: analysis.entries.map { entry in
                ScanExtractionEntry(
                    source: entry.french,
                    target: entry.german,
                    cardType: entry.cardType,
                    sourcePhonetic: nil,
                    targetPhonetic: nil,
                    confidence: confidence,
                    reviewMetadata: ScanEntryReviewMetadata(
                        learningCategory: entry.learningCategory,
                        note: entry.note,
                        isImportable: entry.isImportable
                    ),
                    notes: []
                )
            },
            blocks: [],
            warnings: warnings,
            summary: analysis.summary,
            importMessage: analysis.importMessage,
            confidence: confidence,
            usedColumnPairing: analysis.usedColumnPairing,
            recognizedLineCount: analysis.recognizedLineCount,
            recognizedBoxes: lineBoxes
        )
    }

    static func resolvedReviewMetadata(
        for entry: ScanExtractionEntry
    ) -> ScanEntryReviewMetadata {
        ScanEntryReviewMetadata.resolved(
            explicitCategory: entry.reviewMetadata.learningCategory,
            explicitNote: entry.reviewMetadata.note,
            explicitImportable: entry.reviewMetadata.isImportable,
            notes: entry.notes,
            fallbackCardType: entry.cardType
        )
    }

    static func normalizedReviewEntry(
        _ entry: ScanReviewEntry,
        mode: ScanMode,
        sourceLanguage: StudyLanguage
    ) -> ScanReviewEntry {
        guard mode == .list, sourceLanguage == .french else { return entry }
        guard entry.isImportable else { return entry }

        // Skip lexicon replacement if source has terminal punctuation (Ça va? ≠ Ça va.)
        // Punctuation is meaning-bearing — trust the AI's translation
        let trimmedSource = entry.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedSource.hasSuffix("?") || trimmedSource.hasSuffix(".") || trimmedSource.hasSuffix("!") {
            return entry
        }

        if let trimmedMatch = bestTrimmedFrenchLexiconMatch(forSource: entry.sourceText) {
            return ScanReviewEntry(
                id: entry.id,
                sourceText: trimmedMatch.sourceTerm,
                targetText: trimmedMatch.suggestions[0],
                cardType: entry.cardType,
                reviewMetadata: entry.reviewMetadata
            )
        }

        if let sourceMatch = bestFrenchLexiconMatch(forSource: entry.sourceText),
           shouldForceFrenchLexiconReplacement(
                sourceText: entry.sourceText,
                targetText: entry.targetText,
                sourceMatch: sourceMatch
           ) {
            return ScanReviewEntry(
                id: entry.id,
                sourceText: sourceMatch.sourceTerm,
                targetText: sourceMatch.suggestions[0],
                cardType: entry.cardType,
                reviewMetadata: entry.reviewMetadata
            )
        }

        if let reverseMatch = bestReverseFrenchLexiconMatch(
            forGermanTarget: entry.targetText,
            cardType: entry.cardType
        ), shouldForceReverseFrenchLexiconReplacement(
            sourceText: entry.sourceText,
            targetText: entry.targetText,
            reverseMatch: reverseMatch
        ) {
            return ScanReviewEntry(
                id: entry.id,
                sourceText: reverseMatch.sourceTerm,
                targetText: reverseMatch.targetTerm,
                cardType: entry.cardType,
                reviewMetadata: entry.reviewMetadata
            )
        }

        return entry
    }
}
