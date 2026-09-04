import Foundation
import CoreGraphics

extension ScanColumnPairMatcher {
    func relaxedNearestPairs(
        leftRows: [OCRLineBox],
        rightRows: [OCRLineBox],
        preferredLanguage: StudyLanguage?
    ) -> [PositionedLinePair] {
        guard !leftRows.isEmpty, !rightRows.isEmpty else { return [] }

        let sortedLeftRows = leftRows.sorted(by: { $0.midY > $1.midY })
        var remainingRightRows = rightRows.sorted(by: { $0.midY > $1.midY })
        let averageHeight = (leftRows + rightRows).map(\.height).reduce(0, +) / CGFloat(leftRows.count + rightRows.count)
        let pairTolerance = pairingVerticalTolerance(
            leftRows: sortedLeftRows,
            rightRows: remainingRightRows,
            averageHeight: averageHeight
        )
        var pairs: [PositionedLinePair] = []

        for leftRow in sortedLeftRows {
            guard !remainingRightRows.isEmpty else { break }

            let bestIndex = remainingRightRows.enumerated().min { lhs, rhs in
                abs(lhs.element.midY - leftRow.midY) < abs(rhs.element.midY - leftRow.midY)
            }?.offset

            guard let bestIndex else { continue }
            let rightRow = remainingRightRows.remove(at: bestIndex)
            let verticalDistance = abs(rightRow.midY - leftRow.midY)
            let semanticScore = dependencies.bestVocabularyPairScore(
                leftRow.text,
                rightRow.text,
                preferredLanguage
            )
            guard verticalDistance <= pairTolerance || semanticScore >= 2.0 else { continue }
            pairs.append((leftRow.text, rightRow.text, max(leftRow.midY, rightRow.midY)))
        }

        return pairs
    }

    func betterPairResult(
        primary: [PositionedLinePair],
        fallback: [PositionedLinePair],
        preferredLanguage: StudyLanguage?
    ) -> [PositionedLinePair] {
        let primaryScore = pairResultScore(primary, preferredLanguage: preferredLanguage)
        let fallbackScore = pairResultScore(fallback, preferredLanguage: preferredLanguage)

        if fallback.count >= primary.count + 3 {
            return fallback
        }

        if fallback.count > primary.count, fallbackScore >= primaryScore - 0.35 {
            return fallback
        }

        return primaryScore >= fallbackScore ? primary : fallback
    }

    func pairResultScore(
        _ pairs: [PositionedLinePair],
        preferredLanguage: StudyLanguage?
    ) -> Double {
        guard !pairs.isEmpty else { return -Double.infinity }

        let semanticSum = pairs.reduce(0.0) { partial, pair in
            partial + dependencies.bestVocabularyPairScore(pair.0, pair.1, preferredLanguage)
        }

        let averageSemantic = semanticSum / Double(pairs.count)
        return Double(pairs.count) * 2.8 + averageSemantic
    }
}
