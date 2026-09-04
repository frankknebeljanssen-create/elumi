import Foundation

extension ScanFreeTextPostProcessor {
    func prioritizedPhraseEntries(
        _ entries: [ScanFreeTextReviewEntry],
        contextSourceKeys: Set<String>
    ) -> [ScanFreeTextReviewEntry] {
        deduplicatedReviewEntries(entries)
            .filter { entry in
                let sourceKey = dependencies.normalizedLookupText(entry.sourceText)
                guard !sourceKey.isEmpty else { return false }

                if contextSourceKeys.contains(sourceKey) {
                    let wordCount = dependencies.normalizedWords(entry.sourceText).count
                    return isLikelyPosterLearningPhrase(entry.sourceText) || wordCount <= 4
                }

                return true
            }
            .sorted { lhs, rhs in
                phrasePriorityScore(for: lhs) > phrasePriorityScore(for: rhs)
            }
            .prefix(10)
            .map { $0 }
    }

    func phrasePriorityScore(for entry: ScanFreeTextReviewEntry) -> Int {
        let wordCount = dependencies.normalizedWords(entry.sourceText).count
        var score = 0

        if isLikelyPosterLearningPhrase(entry.sourceText) {
            score += 40
        }
        if entry.note?.contains("Wichtige Textphrase") == true {
            score += 12
        }
        if !entry.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 10
        }
        if entry.sourceText.contains("?") || entry.sourceText.contains("!") {
            score += 6
        }
        if (2...5).contains(wordCount) {
            score += 8
        } else if wordCount == 1 {
            score += 2
        } else if wordCount > 8 {
            score -= 6
        }
        if isSentenceLikeReviewEntry(entry) {
            score -= 4
        }

        return score
    }

    func freeTextPhraseReviewEntries(
        from sentences: [String],
        seedEntries: [ImportPreviewPair],
        sourceLanguage: StudyLanguage
    ) -> [ScanFreeTextReviewEntry] {
        var phraseEntries = seedEntries.compactMap { pair -> ScanFreeTextReviewEntry? in
            if pair.learningCategory == .phrases {
                return reviewEntry(
                    from: pair,
                    defaultCategory: .phrases,
                    defaultNote: pair.note ?? "Sinnvolle Wendung aus dem Text",
                    defaultImportable: true
                )
            }
            let wordCount = dependencies.normalizedWords(pair.french).count
            let sentenceLike = isSentenceLikePreviewPair(pair)
            guard pair.isImportable &&
                pair.cardType == .phrases &&
                wordCount >= 2 &&
                (!sentenceLike || isLikelyPosterLearningPhrase(pair.french)) else {
                return nil
            }
            return reviewEntry(
                from: pair,
                defaultCategory: .phrases,
                defaultNote: pair.note ?? "Sinnvolle Wendung aus dem Text",
                defaultImportable: true
            )
        }

        if phraseEntries.count < 6 {
            for sentence in sentences {
                guard !isLikelyFreeTextScheduleOrMetaLine(sentence) else { continue }
                phraseEntries.append(contentsOf: dependencies.lexiconPreviewPairs(sentence, sourceLanguage).compactMap { pair in
                    let wordCount = dependencies.normalizedWords(pair.french).count
                    guard wordCount >= 1, wordCount <= 10 else { return nil }
                    guard pair.isImportable else { return nil }
                    guard !isLikelyFreeTextScheduleOrMetaLine(pair.french) else { return nil }
                    return ScanFreeTextReviewEntry(
                        id: pair.id,
                        sourceText: pair.french,
                        targetText: pair.german,
                        cardType: .phrases,
                        category: .phrases,
                        note: pair.note ?? "Sinnvolle Wendung aus dem Text",
                        isImportable: true
                    )
                })
            }
        }

        for sentence in sentences where isLikelyPosterLearningPhrase(sentence) {
            guard let translation = DataStore.bestLexiconTranslation(for: sentence, sourceLanguage: sourceLanguage),
                  !translation.isEmpty else { continue }
            phraseEntries.append(
                ScanFreeTextReviewEntry(
                    sourceText: sentence,
                    targetText: translation,
                    cardType: .phrases,
                    category: .phrases,
                    note: "Wichtige Textphrase",
                    isImportable: true
                )
            )
        }

        return deduplicatedReviewEntries(phraseEntries)
            .prefix(10)
            .map { $0 }
    }
}
