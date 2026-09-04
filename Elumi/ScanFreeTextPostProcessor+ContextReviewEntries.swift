import Foundation

extension ScanFreeTextPostProcessor {
    func freeTextContextReviewEntries(
        from sentences: [String],
        seedEntries: [ImportPreviewPair]
    ) -> [ScanFreeTextReviewEntry] {
        let seedLookup = seedEntries
            .filter { dependencies.normalizedWords($0.french).count >= 4 && !$0.german.isEmpty }
            .reduce(into: [String: String]()) { partialResult, pair in
                let key = dependencies.normalizedLookupText(pair.french)
                guard !key.isEmpty, partialResult[key] == nil else { return }
                partialResult[key] = pair.german
            }

        let preferredSentences = sentences.filter(isMeaningfulContextSentence(_:))
        let selectedSentences = preferredSentences.isEmpty
            ? Array(sentences.prefix(2))
            : Array(preferredSentences.prefix(4))

        return selectedSentences
            .prefix(4)
            .map { sentence in
                ScanFreeTextReviewEntry(
                    sourceText: sentence,
                    targetText: seedLookup[dependencies.normalizedLookupText(sentence)] ?? "",
                    cardType: .phrases,
                    category: .recognizedText,
                    note: "Kontext aus dem Scan",
                    isImportable: false
                )
            }
    }
}
