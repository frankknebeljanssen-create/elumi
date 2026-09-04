import Foundation

extension ScanPreviewBuilder {
    func textModePreviewPairs(
        from lines: [String],
        sourceLanguage: StudyLanguage
    ) -> [ImportPreviewPair] {
        let text = normalizedFreeText(from: lines)
        guard !text.isEmpty else { return [] }

        let sentences = sentenceUnits(from: text)
        var entries: [ImportPreviewPair] = []

        for sentence in sentences {
            entries.append(contentsOf: lexiconPreviewPairs(from: sentence, sourceLanguage: sourceLanguage))
        }

        if entries.count < 3 {
            entries.append(contentsOf: lexiconPreviewPairs(from: text, sourceLanguage: sourceLanguage))
        }

        return dependencies.deduplicatePreviewPairs(entries)
    }

    func lexiconPreviewPairs(
        from text: String,
        sourceLanguage: StudyLanguage
    ) -> [ImportPreviewPair] {
        let tokens = sourceTokens(from: text)
        guard !tokens.isEmpty else { return [] }

        let stopWords = dependencies.stopWords(sourceLanguage)
        var pairs: [ImportPreviewPair] = []
        var index = 0

        while index < tokens.count {
            var matchedPair: ImportPreviewPair?
            var matchedLength = 0
            let maxWindow = min(4, tokens.count - index)

            for window in stride(from: maxWindow, through: 1, by: -1) {
                let sourceCandidate = tokens[index..<(index + window)].joined(separator: " ")
                let normalizedSource = normalizedSourceTermForScanExtraction(
                    sourceCandidate,
                    sourceLanguage: sourceLanguage
                )
                let normalizedLookup = dependencies.normalizedLookupText(normalizedSource)

                guard !normalizedSource.isEmpty else { continue }
                if window == 1 &&
                    (
                        (normalizedLookup.count <= 2 &&
                         !allowsShortSingleWordLexiconMatch(
                            normalizedSource,
                            in: text,
                            sourceLanguage: sourceLanguage
                         )) ||
                        stopWords.contains(normalizedLookup)
                    ) {
                    continue
                }

                guard let translation = dependencies.bestLexiconTranslation(normalizedSource, sourceLanguage),
                      !translation.isEmpty else {
                    continue
                }

                matchedPair = ImportPreviewPair(
                    french: normalizedSource,
                    german: translation,
                    cardType: window == 1 ? .words : .phrases
                )
                matchedLength = window
                break
            }

            if let matchedPair {
                pairs.append(dependencies.normalizedPreviewPair(matchedPair))
                index += matchedLength
            } else {
                index += 1
            }
        }

        return pairs
    }
}
