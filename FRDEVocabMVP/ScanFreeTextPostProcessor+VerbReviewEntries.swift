import Foundation

extension ScanFreeTextPostProcessor {
    func prioritizedVerbEntries(
        _ entries: [ScanFreeTextReviewEntry]
    ) -> [ScanFreeTextReviewEntry] {
        deduplicatedReviewEntries(entries)
            .sorted { lhs, rhs in
                verbPriorityScore(for: lhs) > verbPriorityScore(for: rhs)
            }
            .prefix(8)
            .map { $0 }
    }

    func verbPriorityScore(for entry: ScanFreeTextReviewEntry) -> Int {
        let wordCount = dependencies.normalizedWords(entry.sourceText).count
        var score = 0

        if wordCount == 1 {
            score += 10
        }
        if !entry.targetText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            score += 8
        }
        if entry.note?.contains("Grundform") == true {
            score += 6
        }
        score += min(entry.sourceText.count, 12)
        return score
    }

    func freeTextVerbReviewEntries(
        from text: String,
        seedEntries: [ImportPreviewPair],
        sourceLanguage: StudyLanguage
    ) -> [ScanFreeTextReviewEntry] {
        var verbEntries = seedEntries.compactMap { pair -> ScanFreeTextReviewEntry? in
            guard pair.learningCategory == .verbs else { return nil }
            return reviewEntry(
                from: pair,
                defaultCategory: .verbs,
                defaultNote: pair.note ?? "Verb aus dem Text",
                defaultImportable: true
            )
        }

        var existingKeys = Set(verbEntries.map { dependencies.normalizedLookupText($0.sourceText) })
        let detectedVerbs = detectedVerbCandidates(in: text, sourceLanguage: sourceLanguage)

        for candidate in detectedVerbs {
            let displaySource = dependencies.canonicalizeSourceTerm(candidate.surface, sourceLanguage)
            let sourceKey = dependencies.normalizedLookupText(displaySource)
            guard !sourceKey.isEmpty, !existingKeys.contains(sourceKey) else { continue }

            let translation = DataStore.bestLexiconTranslation(for: displaySource, sourceLanguage: sourceLanguage)
                ?? candidate.lemma.flatMap { DataStore.bestLexiconTranslation(for: $0, sourceLanguage: sourceLanguage) }
            guard let translation, !translation.isEmpty else { continue }

            let note: String?
            if let lemma = candidate.lemma,
               !lemma.isEmpty,
               dependencies.normalizedLookupText(lemma) != dependencies.normalizedLookupText(displaySource) {
                note = "Verb · Grundform: \(lemma)"
            } else {
                note = "Verb aus dem Text"
            }

            verbEntries.append(
                ScanFreeTextReviewEntry(
                    sourceText: displaySource,
                    targetText: translation,
                    cardType: .words,
                    category: .verbs,
                    note: note,
                    isImportable: true
                )
            )
            existingKeys.insert(sourceKey)
        }

        return deduplicatedReviewEntries(verbEntries)
            .prefix(8)
            .map { $0 }
    }
}
