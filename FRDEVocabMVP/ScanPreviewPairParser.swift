import Foundation

struct ScanPreviewPairParserDependencies {
    let extractedDisplayTerm: (String) -> String
    let isStandalonePedagogicalMarker: (String) -> Bool
    let isLikelyHeadingOrMetaLine: (String) -> Bool
    let inferredCardType: (String, String) -> CardType
    let isSourceColumnFirst: (String, String) -> Bool
    let isLikelyOrphanTargetPreviewLine: (String, StudyLanguage) -> Bool
    let sanitizedLine: (String) -> String
    let normalizedSourceImportTerm: (String, StudyLanguage) -> String
    let canonicalizedGermanTargetIfNeeded: (String, String, CardType, StudyLanguage) -> String
    let synchronizedPairTerminalSentencePunctuation: (String, String, StudyLanguage, CardType) -> (String, String)
}

struct ScanPreviewPairParser {
    let dependencies: ScanPreviewPairParserDependencies

    func makePreviewPair(
        first: String,
        second: String,
        sourceLanguage: StudyLanguage
    ) -> ImportPreviewPair? {
        let left = dependencies.extractedDisplayTerm(first)
        let right = dependencies.extractedDisplayTerm(second)
        guard !left.isEmpty, !right.isEmpty else { return nil }
        guard !dependencies.isStandalonePedagogicalMarker(left),
              !dependencies.isStandalonePedagogicalMarker(right) else { return nil }
        guard !dependencies.isLikelyHeadingOrMetaLine(left),
              !dependencies.isLikelyHeadingOrMetaLine(right) else { return nil }

        let inferredCardType = dependencies.inferredCardType(left, right)
        let sourceText = dependencies.isSourceColumnFirst(left, right) ? left : right
        let targetText = sourceText == left ? right : left

        return normalizedPreviewPair(
            ImportPreviewPair(french: sourceText, german: targetText, cardType: inferredCardType),
            sourceLanguage: sourceLanguage
        )
    }

    func makeIncompletePreviewPair(
        from line: String,
        sourceLanguage: StudyLanguage
    ) -> ImportPreviewPair? {
        let cleanedLine = dependencies.extractedDisplayTerm(line)
        guard !cleanedLine.isEmpty, !dependencies.isLikelyHeadingOrMetaLine(cleanedLine) else { return nil }
        guard !dependencies.isStandalonePedagogicalMarker(cleanedLine) else { return nil }
        guard !dependencies.isLikelyOrphanTargetPreviewLine(cleanedLine, sourceLanguage) else { return nil }

        return normalizedPreviewPair(
            ImportPreviewPair(
                french: cleanedLine,
                german: "",
                cardType: dependencies.inferredCardType(cleanedLine, "")
            ),
            sourceLanguage: sourceLanguage
        )
    }

    func parsePreviewPairs(
        from rawText: String,
        sourceLanguage: StudyLanguage
    ) -> [ImportPreviewPair] {
        let rawLines = rawText
            .components(separatedBy: .newlines)
            .map(dependencies.sanitizedLine)
            .filter { !$0.isEmpty }

        var explicitPairs: [ImportPreviewPair] = []
        var unmatchedLines: [String] = []

        for line in rawLines {
            if let pair = splitLine(line),
               let previewPair = makePreviewPair(
                    first: pair.0,
                    second: pair.1,
                    sourceLanguage: sourceLanguage
               ) {
                explicitPairs.append(previewPair)
            } else {
                unmatchedLines.append(line)
            }
        }

        if !explicitPairs.isEmpty {
            return explicitPairs + unmatchedLines.compactMap {
                makeIncompletePreviewPair(
                    from: $0,
                    sourceLanguage: sourceLanguage
                )
            }
        }

        var fallbackPairs: [ImportPreviewPair] = []
        var index = 0
        while index + 1 < rawLines.count {
            if let pair = makePreviewPair(
                first: rawLines[index],
                second: rawLines[index + 1],
                sourceLanguage: sourceLanguage
            ) {
                fallbackPairs.append(pair)
            }
            index += 2
        }

        if index < rawLines.count,
           let previewPair = makeIncompletePreviewPair(
                from: rawLines[index],
                sourceLanguage: sourceLanguage
           ) {
            fallbackPairs.append(previewPair)
        }

        return fallbackPairs
    }

    func splitLine(_ line: String) -> (String, String)? {
        let separators = ["→", "=", ";", "\t", " - ", ":"]

        for separator in separators {
            guard let range = line.range(of: separator) else { continue }
            let left = String(line[..<range.lowerBound])
            let right = String(line[range.upperBound...])
            return (left, right)
        }

        if let range = line.range(of: #" {2,}"#, options: .regularExpression) {
            let left = String(line[..<range.lowerBound])
            let right = String(line[range.upperBound...])
            return (left, right)
        }

        return nil
    }

    func normalizedPreviewPair(
        _ pair: ImportPreviewPair,
        sourceLanguage: StudyLanguage
    ) -> ImportPreviewPair {
        let normalizedFrench = dependencies.normalizedSourceImportTerm(pair.french, sourceLanguage)
        let normalizedGerman = dependencies.canonicalizedGermanTargetIfNeeded(
            pair.german,
            normalizedFrench.isEmpty ? pair.french : normalizedFrench,
            pair.cardType,
            sourceLanguage
        )
        let synchronizedPair = dependencies.synchronizedPairTerminalSentencePunctuation(
            normalizedFrench,
            normalizedGerman,
            sourceLanguage,
            pair.cardType
        )
        return ImportPreviewPair(
            id: pair.id,
            french: synchronizedPair.0,
            german: synchronizedPair.1,
            cardType: pair.cardType,
            learningCategory: pair.learningCategory,
            note: pair.note,
            isImportable: pair.isImportable,
            isReviewed: pair.isReviewed
        )
    }
}
