import Foundation

enum ScanReviewMapper {
    struct PreparedAnalysisApplication {
        let preparedPreviewPairs: [ImportPreviewPair]
        let mergedPreviewPairs: [ImportPreviewPair]
        let reviewSummary: String
    }

    static func makeReviewEntry(from previewPair: ImportPreviewPair) -> ScanReviewEntry {
        ScanReviewEntry(
            id: previewPair.id,
            sourceText: previewPair.french,
            targetText: previewPair.german,
            cardType: previewPair.cardType,
            reviewMetadata: ScanEntryReviewMetadata(
                learningCategory: previewPair.learningCategory,
                note: previewPair.note,
                isImportable: previewPair.isImportable
            )
        )
    }

    static func makePreviewPair(from reviewEntry: ScanReviewEntry) -> ImportPreviewPair {
        ImportPreviewPair(
            id: reviewEntry.id,
            french: reviewEntry.sourceText,
            german: reviewEntry.targetText,
            cardType: reviewEntry.cardType,
            learningCategory: reviewEntry.learningCategory,
            note: reviewEntry.note,
            isImportable: reviewEntry.isImportable,
            wordClass: reviewEntry.wordClass
        )
    }

    static func makeReviewEntries(from previewPairs: [ImportPreviewPair]) -> [ScanReviewEntry] {
        previewPairs.map(makeReviewEntry)
    }

    static func makePreviewPairs(from reviewEntries: [ScanReviewEntry]) -> [ImportPreviewPair] {
        reviewEntries.map(makePreviewPair)
    }

    static func deduplicatedReviewEntries(
        _ entries: [ScanReviewEntry],
        deduplicatePreviewPairs: ([ImportPreviewPair]) -> [ImportPreviewPair]
    ) -> [ScanReviewEntry] {
        makeReviewEntries(from: deduplicatePreviewPairs(makePreviewPairs(from: entries)))
    }

    // Faltet Case + Whitespace zusammen damit visuell identische
    // Pairs ("manger"/"Essen" vs "Manger"/"essen") als Duplikat
    // erkannt werden. Punktuation und Akzente bleiben bewusst
    // signifikant (Ça va? ≠ Ça va., où ≠ ou). cardType ist NICHT
    // Teil des Keys damit LLM-cardType-Inkonsistenzen bei sonst
    // identischen Pairs zusammengeführt werden.
    private static func dedupNormalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func deduplicatedPreviewPairs(
        _ pairs: [ImportPreviewPair],
        normalizedPreviewPair: (ImportPreviewPair) -> ImportPreviewPair,
        normalizedLookupText: (String) -> String,
        extractedDisplayTerm: (String) -> String
    ) -> [ImportPreviewPair] {
        var seen = Set<String>()

        return pairs.compactMap { pair in
            let normalizedPair = normalizedPreviewPair(
                ImportPreviewPair(
                    id: pair.id,
                    french: extractedDisplayTerm(pair.french),
                    german: extractedDisplayTerm(pair.german),
                    cardType: pair.cardType,
                    learningCategory: pair.learningCategory,
                    note: pair.note,
                    isImportable: pair.isImportable,
                    isReviewed: pair.isReviewed,
                    wordClass: pair.wordClass
                )
            )

            // Dedup-Key: case/whitespace-gefaltet (siehe `dedupNormalize`),
            // Punktuation signifikant (Ça va? ≠ Ça va.).
            let exactFrench = normalizedPair.french.trimmingCharacters(in: .whitespaces)
            let exactGerman = normalizedPair.german.trimmingCharacters(in: .whitespaces)
            guard !exactFrench.isEmpty || !exactGerman.isEmpty else { return nil }

            let key = "\(dedupNormalize(exactFrench))|\(dedupNormalize(exactGerman))"
            guard seen.insert(key).inserted else { return nil }

            // FINAL fix: force German lowercase on non-nouns AFTER all normalization
            let fixedGerman = ClaudeHaikuScanAIClient.forceGermanLowercase(normalizedPair.german)
            if fixedGerman != normalizedPair.german {
                return ImportPreviewPair(
                    id: normalizedPair.id,
                    french: normalizedPair.french,
                    german: fixedGerman,
                    cardType: normalizedPair.cardType,
                    learningCategory: normalizedPair.learningCategory,
                    note: normalizedPair.note,
                    isImportable: normalizedPair.isImportable,
                    isReviewed: normalizedPair.isReviewed,
                    wordClass: normalizedPair.wordClass
                )
            }
            return normalizedPair
        }
    }

    static func makePreparedPreviewPairs(
        from entries: [ScanReviewEntry],
        mode: ScanMode,
        recognizedLines: [String],
        sourceLanguage: StudyLanguage,
        deduplicatePreviewPairs: ([ImportPreviewPair]) -> [ImportPreviewPair],
        prepareFreeTextPreviewPairs: ([ImportPreviewPair], [String], StudyLanguage) -> [ImportPreviewPair]
    ) -> [ImportPreviewPair] {
        let normalizedEntries = deduplicatePreviewPairs(makePreviewPairs(from: entries))
        guard mode == .text else { return normalizedEntries }
        return prepareFreeTextPreviewPairs(normalizedEntries, recognizedLines, sourceLanguage)
    }

    static func makePreparedAnalysisApplication(
        from analysis: ScanAnalysisResult,
        existingPreviewPairs: [ImportPreviewPair],
        appending: Bool,
        deduplicatePreviewPairs: ([ImportPreviewPair]) -> [ImportPreviewPair],
        prepareFreeTextPreviewPairs: ([ImportPreviewPair], [String], StudyLanguage) -> [ImportPreviewPair],
        freeTextReviewSummary: ([ImportPreviewPair], String) -> String
    ) -> PreparedAnalysisApplication {
        let preparedPreviewPairs = makePreparedPreviewPairs(
            from: analysis.entries,
            mode: analysis.mode,
            recognizedLines: analysis.recognizedLines,
            sourceLanguage: analysis.sourceLanguage,
            deduplicatePreviewPairs: deduplicatePreviewPairs,
            prepareFreeTextPreviewPairs: prepareFreeTextPreviewPairs
        )

        let mergedPreviewPairs = appending
            ? deduplicatePreviewPairs(existingPreviewPairs + preparedPreviewPairs)
            : deduplicatePreviewPairs(preparedPreviewPairs)

        let reviewSummary = analysis.mode == .text
            ? freeTextReviewSummary(mergedPreviewPairs, analysis.summary)
            : analysis.summary

        return PreparedAnalysisApplication(
            preparedPreviewPairs: preparedPreviewPairs,
            mergedPreviewPairs: mergedPreviewPairs,
            reviewSummary: reviewSummary
        )
    }
}
