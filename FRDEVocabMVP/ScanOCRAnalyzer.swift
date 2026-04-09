import Foundation

struct ScanOCRAnalyzerDependencies {
    typealias LinePair = (String, String)

    let sourceLanguage: StudyLanguage
    let filteredVocabularyBoxes: ([OCRLineBox]) -> [OCRLineBox]
    let makeColumnPairs: ([OCRLineBox], StudyLanguage?) -> [LinePair]
    let pairCandidateSelectionScore: ([LinePair], StudyLanguage?) -> Double
    let listModePreviewPairs: ([OCRLineBox], StudyLanguage) -> [ImportPreviewPair]
    let textModePreviewPairs: ([String], StudyLanguage) -> [ImportPreviewPair]
    let extractedDisplayTerm: (String) -> String
    let deduplicatePreviewPairs: ([ImportPreviewPair]) -> [ImportPreviewPair]
}

struct ScanOCRAnalyzer {
    let dependencies: ScanOCRAnalyzerDependencies

    func analyze(
        from lineBoxes: [OCRLineBox],
        preferredMode: ScanMode?
    ) -> ScanAnalysisResult {
        let modeWasPreselected = preferredMode != nil
        let filteredBoxes = dependencies.filteredVocabularyBoxes(lineBoxes)
        let rawPairs = dependencies.makeColumnPairs(lineBoxes, nil)
        let filteredPairs = dependencies.makeColumnPairs(filteredBoxes, nil)
        let rawPairScore = dependencies.pairCandidateSelectionScore(rawPairs, nil)
        let filteredPairScore = dependencies.pairCandidateSelectionScore(filteredPairs, nil)

        let shouldUseRawBoxes: Bool
        if filteredPairs.isEmpty {
            shouldUseRawBoxes = !rawPairs.isEmpty
        } else if rawPairs.isEmpty {
            shouldUseRawBoxes = false
        } else {
            shouldUseRawBoxes =
                rawPairScore > filteredPairScore + 1.2 &&
                rawPairs.count >= filteredPairs.count + 2
        }

        let boxesForImport = shouldUseRawBoxes ? lineBoxes : (filteredBoxes.count >= 2 ? filteredBoxes : lineBoxes)
        let initialPairedLines = shouldUseRawBoxes ? rawPairs : dependencies.makeColumnPairs(boxesForImport, nil)
        let detectedSourceLanguage = dependencies.sourceLanguage

        let listEntries = ScanReviewMapper.makeReviewEntries(
            from: dependencies.listModePreviewPairs(boxesForImport, detectedSourceLanguage)
        )
        let structuredLines = structuredOCRLines(from: boxesForImport)
        let mode = preferredMode ?? autoDetectedScanMode(
            from: structuredLines,
            listEntries: listEntries,
            hasColumnPairs: !initialPairedLines.isEmpty
        )

        let analyzedEntries: [ScanReviewEntry]
        switch mode {
        case .list:
            analyzedEntries = !listEntries.isEmpty
                ? listEntries
                : ScanReviewMapper.makeReviewEntries(
                    from: dependencies.textModePreviewPairs(structuredLines, detectedSourceLanguage)
                )
        case .text:
            let textEntries = ScanReviewMapper.makeReviewEntries(
                from: dependencies.textModePreviewPairs(structuredLines, detectedSourceLanguage)
            )
            analyzedEntries = !textEntries.isEmpty ? textEntries : listEntries
        }

        let entries = ScanReviewMapper.deduplicatedReviewEntries(
            analyzedEntries,
            deduplicatePreviewPairs: dependencies.deduplicatePreviewPairs
        )
        let completeCount = entries.filter {
            !$0.french.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.german.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count

        let summary: String
        let importMessage: String
        if completeCount == 0 {
            summary = mode == .text
                ? "Der Text wurde erkannt, aber es konnten noch keine passenden Lern-Einträge gefunden werden."
                : "Die Struktur wirkt wie eine Liste, aber es konnten noch keine sauberen Paare gebildet werden."
            importMessage = "Bitte prüfe den Zuschnitt oder wechsle im Review kurz zwischen Liste und Text."
        } else if mode == .list {
            summary = modeWasPreselected
                ? "Die Vorlage wurde als Vokabelliste verarbeitet."
                : "\(detectedSourceLanguage.rawValue)-Deutsch als strukturierte Liste erkannt."
            importMessage = "\(completeCount) Einträge vorbereitet. Prüfe kurz und importiere dann die Liste."
        } else {
            summary = modeWasPreselected
                ? "Die Vorlage wurde als freier Text verarbeitet."
                : "\(detectedSourceLanguage.rawValue)-Deutsch als freier Text erkannt."
            importMessage = "\(completeCount) lernbare Einträge aus dem Text vorbereitet. Prüfe kurz und importiere dann die Liste."
        }

        return ScanAnalysisResult(
            mode: mode,
            sourceLanguage: detectedSourceLanguage,
            entries: entries,
            summary: summary,
            importMessage: importMessage,
            analysisPath: .ocrOnly,
            usedColumnPairing: !initialPairedLines.isEmpty,
            recognizedLineCount: structuredLines.count,
            recognizedLines: structuredLines
        )
    }

    private func structuredOCRLines(from boxes: [OCRLineBox]) -> [String] {
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

    private func autoDetectedScanMode(
        from lines: [String],
        listEntries: [ScanReviewEntry],
        hasColumnPairs: Bool = false
    ) -> ScanMode {
        guard !lines.isEmpty else { return .list }

        let lineLengths = lines.map(\.count)
        let wordCounts = lines.map { words(in: $0).count }
        let separatorRatio = Double(lines.filter { splitLine($0) != nil }.count) / Double(lines.count)
        let shortLineRatio = Double(zip(lineLengths, wordCounts).filter { $0 <= 24 || $1 <= 4 }.count) / Double(lines.count)
        let sentenceLikeRatio = Double(lines.filter {
            let words = words(in: $0).count
            return words >= 7 || $0.contains(".") || $0.contains("!") || $0.contains("?")
        }.count) / Double(lines.count)

        let meanLength = Double(lineLengths.reduce(0, +)) / Double(max(lineLengths.count, 1))
        let variance = lineLengths.reduce(0.0) { partial, length in
            partial + pow(Double(length) - meanLength, 2)
        } / Double(max(lineLengths.count, 1))
        let pairDensity = Double(listEntries.count) / Double(max(lines.count, 1))

        // Column pairs detected via spatial clustering → strong list signal
        if hasColumnPairs && listEntries.count >= 2 {
            return .list
        }

        if listEntries.count >= 3 && (pairDensity >= 0.34 || separatorRatio >= 0.14 || shortLineRatio >= 0.55) {
            return .list
        }

        if sentenceLikeRatio >= 0.38 && variance >= 70 {
            return .text
        }

        if separatorRatio >= 0.2 || shortLineRatio >= 0.7 || hasColumnPairs {
            return .list
        }

        return sentenceLikeRatio > 0.32 ? .text : (listEntries.count >= 2 ? .list : .text)
    }

    private func words(in text: String) -> [Substring] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
    }

    private func splitLine(_ text: String) -> (String, String)? {
        let separators = [" - ", " – ", " — ", " = ", " : ", "\t"]

        for separator in separators {
            let parts = text.components(separatedBy: separator)
            if parts.count == 2 {
                let left = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                let right = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if !left.isEmpty && !right.isEmpty {
                    return (left, right)
                }
            }
        }

        return nil
    }
}
