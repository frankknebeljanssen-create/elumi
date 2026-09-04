import Foundation

extension ScanPreviewBuilder {
    func listModePreviewPairs(
        from boxes: [OCRLineBox],
        sourceLanguage: StudyLanguage
    ) -> [ImportPreviewPair] {
        let filteredBoxes = dependencies.filteredVocabularyBoxes(boxes)
        let filteredPairs = dependencies.makeColumnPairs(
            filteredBoxes,
            sourceLanguage
        )
        let rawPairs = dependencies.makeColumnPairs(
            boxes,
            sourceLanguage
        )
        let repairedCandidates = [
            dependencies.repairedVocabularyPairs(filteredPairs, sourceLanguage),
            dependencies.repairedVocabularyPairs(rawPairs, sourceLanguage)
        ]
        let bestPairs = bestPairCandidate(
            from: repairedCandidates,
            preferredLanguage: sourceLanguage
        )

        if !bestPairs.isEmpty {
            let pairedPreviewPairs: [ImportPreviewPair] = bestPairs.compactMap {
                dependencies.makePreviewPair($0.0, $0.1)
            }
            let rescuedPreviewPairs: [ImportPreviewPair] = orphanLexiconRescuePairs(
                from: filteredBoxes,
                existingPairs: pairedPreviewPairs,
                sourceLanguage: sourceLanguage
            )
            return dependencies.deduplicatePreviewPairs(
                pairedPreviewPairs + rescuedPreviewPairs
            )
        }

        let fallbackText = structuredOCRLines(from: boxes).joined(separator: "\n")
        return dependencies.deduplicatePreviewPairs(
            dependencies.parsePreviewPairs(fallbackText)
        )
    }

    func structuredOCRLines(from boxes: [OCRLineBox]) -> [String] {
        boxes
            .sorted { lhs, rhs in
                if abs(lhs.midY - rhs.midY) > 0.018 {
                    return lhs.midY > rhs.midY
                }
                return lhs.minX < rhs.minX
            }
            .map(\.text)
            .map(dependencies.extractedDisplayTerm)
            .filter { !$0.isEmpty }
    }

    func orphanLexiconRescuePairs(
        from boxes: [OCRLineBox],
        existingPairs: [ImportPreviewPair],
        sourceLanguage: StudyLanguage
    ) -> [ImportPreviewPair] {
        let existingSourceKeys = Set(
            existingPairs.map { dependencies.normalizedLookupText($0.french) }
        )

        return structuredOCRLines(from: boxes).compactMap { line in
            let extracted = dependencies.extractedDisplayTerm(line)
            let normalizedSource = normalizedSourceTermForScanExtraction(
                extracted,
                sourceLanguage: sourceLanguage
            )
            let lookupKey = dependencies.normalizedLookupText(normalizedSource)
            let wordCount = lookupKey.split(separator: " ").count

            guard !lookupKey.isEmpty else { return nil }
            guard !existingSourceKeys.contains(lookupKey) else { return nil }
            guard isLikelyOrphanLexiconRescueCandidate(normalizedSource, wordCount: wordCount) else { return nil }
            guard let translation = dependencies.bestLexiconTranslation(normalizedSource, sourceLanguage),
                  !translation.isEmpty else {
                return nil
            }

            return dependencies.normalizedPreviewPair(
                ImportPreviewPair(
                    french: normalizedSource,
                    german: translation,
                    cardType: wordCount == 1 ? .words : .phrases
                )
            )
        }
    }

    func isLikelyOrphanLexiconRescueCandidate(
        _ source: String,
        wordCount: Int
    ) -> Bool {
        guard wordCount == 1 else { return false }

        let lookupKey = dependencies.normalizedLookupText(source)
        guard lookupKey.count >= 2, lookupKey.count <= 6 else { return false }

        return source.range(
            of: #"^[\p{L}][\p{L}'’\-]*[!?]?$"#,
            options: .regularExpression
        ) != nil
    }
}
