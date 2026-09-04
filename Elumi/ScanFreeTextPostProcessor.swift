import Foundation

struct ScanFreeTextPostProcessorDependencies {
    let extractDisplayTerm: (String) -> String
    let normalizedWords: (String) -> [String]
    let normalizedLookupText: (String) -> String
    let deduplicatePreviewPairs: ([ImportPreviewPair]) -> [ImportPreviewPair]
    let lexiconPreviewPairs: (String, StudyLanguage) -> [ImportPreviewPair]
    let canonicalizeSourceTerm: (String, StudyLanguage) -> String
    let isLikelyHeadingOrMetaLine: (String) -> Bool
}

struct ScanFreeTextPostProcessor {
    let dependencies: ScanFreeTextPostProcessorDependencies

    func prepareReviewEntries(
        seedEntries: [ImportPreviewPair],
        recognizedLines: [String],
        sourceLanguage: StudyLanguage
    ) -> [ScanFreeTextReviewEntry] {
        let cleanedLines = recognizedLines
            .map(dependencies.extractDisplayTerm)
            .filter { !$0.isEmpty }
        let meaningUnits = freeTextMeaningUnits(from: cleanedLines)
        let learningUnits = meaningUnits.filter { !isLikelyFreeTextScheduleOrMetaLine($0) }
        let freeText = learningUnits.joined(separator: " ")
        let sentences = learningUnits.filter { dependencies.normalizedWords($0).count >= 1 }

        let textEntries = freeTextContextReviewEntries(
            from: sentences,
            seedEntries: seedEntries
        )
        let contextSourceKeys = Set(
            textEntries.map { dependencies.normalizedLookupText($0.sourceText) }
        )

        let phraseEntries = prioritizedPhraseEntries(
            freeTextPhraseReviewEntries(
                from: sentences,
                seedEntries: seedEntries,
                sourceLanguage: sourceLanguage
            ),
            contextSourceKeys: contextSourceKeys
        )

        let verbEntries = prioritizedVerbEntries(
            freeTextVerbReviewEntries(
                from: freeText,
                seedEntries: seedEntries,
                sourceLanguage: sourceLanguage
            )
        )

        let grammarEntries = prioritizedGrammarEntries(
            freeTextGrammarReviewEntries(
                from: sentences,
                sourceLanguage: sourceLanguage
            )
        )

        return resolvedBucketConflicts(
            deduplicatedReviewEntries(textEntries + verbEntries + phraseEntries + grammarEntries)
        )
    }

    func prepare(
        seedEntries: [ImportPreviewPair],
        recognizedLines: [String],
        sourceLanguage: StudyLanguage
    ) -> [ImportPreviewPair] {
        makePreviewPairs(
            from: prepareReviewEntries(
                seedEntries: seedEntries,
                recognizedLines: recognizedLines,
                sourceLanguage: sourceLanguage
            )
        )
    }

    func makePreviewPairs(
        from reviewEntries: [ScanFreeTextReviewEntry]
    ) -> [ImportPreviewPair] {
        reviewEntries.map { entry in
            ImportPreviewPair(
                id: entry.id,
                french: entry.sourceText,
                german: entry.targetText,
                cardType: entry.cardType,
                learningCategory: entry.category,
                note: entry.note,
                isImportable: entry.isImportable
            )
        }
    }

    func reviewEntries(
        from previewPairs: [ImportPreviewPair]
    ) -> [ScanFreeTextReviewEntry] {
        previewPairs.map { pair in
            ScanFreeTextReviewEntry(
                id: pair.id,
                sourceText: pair.french,
                targetText: pair.german,
                cardType: pair.cardType,
                category: pair.learningCategory ?? inferredCategory(for: pair),
                note: pair.note,
                isImportable: pair.isImportable
            )
        }
    }

    func reviewSummary(
        from pairs: [ImportPreviewPair],
        fallback: String
    ) -> String {
        reviewSummary(from: reviewEntries(from: pairs), fallback: fallback)
    }

    func reviewSummary(
        from reviewEntries: [ScanFreeTextReviewEntry],
        fallback: String
    ) -> String {
        let verbs = reviewEntries.filter { $0.category == .verbs }.count
        let phrases = reviewEntries.filter { $0.category == .phrases }.count
        let grammar = reviewEntries.filter { $0.category == .grammar }.count

        guard verbs + phrases + grammar > 0 else { return fallback }

        return "Freitext aufbereitet: \(verbs) Verben, \(phrases) Phrasen und \(grammar) Grammatikpunkte als Lerninhalt."
    }
}
