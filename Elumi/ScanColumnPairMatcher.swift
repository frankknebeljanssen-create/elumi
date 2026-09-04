import Foundation
import CoreGraphics

struct ScanColumnPairMatcherDependencies {
    let bestVocabularyPairScore: (String, String, StudyLanguage?) -> Double
    let vocabularyPairPenalty: (Double, Double) -> Double
    let extractedDisplayTerm: (String) -> String
    let isLikelyHeadingOrMetaLine: (String) -> Bool
    let normalizedLookupText: (String) -> String
    let normalizedWords: (String) -> [String]
    let germanDictionaryCoverageScore: (String) -> Double
}

struct ScanColumnPairMatcher {
    enum PairDecision {
        case pair
        case skipLeft
        case skipRight
    }

    typealias PositionedLinePair = (String, String, CGFloat)

    let dependencies: ScanColumnPairMatcherDependencies

    func makeColumnPairs(
        from boxes: [OCRLineBox],
        preferredLanguage: StudyLanguage? = nil
    ) -> [(String, String)] {
        guard boxes.count >= 2 else { return [] }

        let columnCandidates = candidateColumnGroups(for: boxes)
        var bestPairs: [PositionedLinePair] = []
        var bestScore = -Double.infinity

        for columns in columnCandidates where columns.count >= 2 {
            let candidateResults = candidatePairResults(
                from: columns,
                preferredLanguage: preferredLanguage
            )

            for pairs in candidateResults {
                let score = pairResultScore(pairs, preferredLanguage: preferredLanguage)
                if score > bestScore {
                    bestScore = score
                    bestPairs = pairs
                }
            }
        }

        return bestPairs
            .sorted { $0.2 > $1.2 }
            .map { ($0.0, $0.1) }
    }

    func candidatePairResults(
        from columns: [[OCRLineBox]],
        preferredLanguage: StudyLanguage?
    ) -> [[PositionedLinePair]] {
        let rowColumns = columns.map { column in
            mergeWrappedContinuationRows(
                mergeBoxesIntoRows(column),
                preferredLanguage: preferredLanguage
            )
        }
        var results: [[PositionedLinePair]] = []

        let sequentialPairs = sequentialPairResult(
            from: rowColumns,
            preferredLanguage: preferredLanguage
        )
        if !sequentialPairs.isEmpty {
            results.append(sequentialPairs)
        }

        for index in 0..<(rowColumns.count - 1) {
            let adjacentPairs = pairResult(
                leftRows: rowColumns[index],
                rightRows: rowColumns[index + 1],
                preferredLanguage: preferredLanguage
            )
            if !adjacentPairs.isEmpty {
                results.append(adjacentPairs)
            }
        }

        guard rowColumns.count >= 3 else { return results }

        for index in 0..<(rowColumns.count - 2) {
            let middleColumn = rowColumns[index + 1]
            guard isLikelyAuxiliaryColumn(middleColumn) else { continue }

            let bridgedPairs = pairResult(
                leftRows: rowColumns[index],
                rightRows: rowColumns[index + 2],
                preferredLanguage: preferredLanguage
            )
            if !bridgedPairs.isEmpty {
                results.append(bridgedPairs)
            }
        }

        return results
    }

    func sequentialPairResult(
        from rowColumns: [[OCRLineBox]],
        preferredLanguage: StudyLanguage?
    ) -> [PositionedLinePair] {
        var pairs: [PositionedLinePair] = []
        var columnIndex = 0

        while columnIndex + 1 < rowColumns.count {
            pairs.append(contentsOf: pairResult(
                leftRows: rowColumns[columnIndex],
                rightRows: rowColumns[columnIndex + 1],
                preferredLanguage: preferredLanguage
            ))
            columnIndex += 2
        }

        return pairs
    }

    func pairResult(
        leftRows: [OCRLineBox],
        rightRows: [OCRLineBox],
        preferredLanguage: StudyLanguage?
    ) -> [PositionedLinePair] {
        let dynamicPairs = matchedPairs(
            leftRows: leftRows,
            rightRows: rightRows,
            preferredLanguage: preferredLanguage
        )
        let relaxedPairs = relaxedNearestPairs(
            leftRows: leftRows,
            rightRows: rightRows,
            preferredLanguage: preferredLanguage
        )

        return betterPairResult(
            primary: dynamicPairs,
            fallback: relaxedPairs,
            preferredLanguage: preferredLanguage
        )
    }
}
