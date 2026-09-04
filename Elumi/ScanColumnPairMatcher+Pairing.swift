import Foundation
import CoreGraphics

extension ScanColumnPairMatcher {
    func matchedPairs(
        leftRows: [OCRLineBox],
        rightRows: [OCRLineBox],
        preferredLanguage: StudyLanguage?
    ) -> [PositionedLinePair] {
        guard !leftRows.isEmpty, !rightRows.isEmpty else { return [] }

        let averageHeight = (leftRows + rightRows).map(\.height).reduce(0, +) / CGFloat(leftRows.count + rightRows.count)
        let sortedLeftRows = leftRows.sorted(by: { $0.midY > $1.midY })
        let sortedRightRows = rightRows.sorted(by: { $0.midY > $1.midY })
        let pairTolerance = Double(pairingVerticalTolerance(
            leftRows: sortedLeftRows,
            rightRows: sortedRightRows,
            averageHeight: averageHeight
        ))
        let skipPenalty = pairTolerance * 0.58
        let leftCount = sortedLeftRows.count
        let rightCount = sortedRightRows.count

        var dp = Array(
            repeating: Array(repeating: Double.infinity, count: rightCount + 1),
            count: leftCount + 1
        )
        var decision = Array(
            repeating: Array(repeating: PairDecision.skipRight, count: rightCount + 1),
            count: leftCount + 1
        )

        dp[leftCount][rightCount] = 0

        for leftIndex in stride(from: leftCount, through: 0, by: -1) {
            for rightIndex in stride(from: rightCount, through: 0, by: -1) {
                if leftIndex == leftCount, rightIndex == rightCount {
                    continue
                }

                if leftIndex == leftCount {
                    dp[leftIndex][rightIndex] = Double(rightCount - rightIndex) * skipPenalty
                    decision[leftIndex][rightIndex] = .skipRight
                    continue
                }

                if rightIndex == rightCount {
                    dp[leftIndex][rightIndex] = Double(leftCount - leftIndex) * skipPenalty
                    decision[leftIndex][rightIndex] = .skipLeft
                    continue
                }

                let leftRow = sortedLeftRows[leftIndex]
                let rightRow = sortedRightRows[rightIndex]
                let distance = Double(abs(leftRow.midY - rightRow.midY))
                let indexDrift = abs(leftIndex - rightIndex)
                let indexPenalty = Double(indexDrift) * max(pairTolerance * 0.22, 0.018)
                    + Double(max(0, indexDrift - 1)) * max(pairTolerance * 0.82, 0.038)
                let semanticScore = dependencies.bestVocabularyPairScore(
                    leftRow.text,
                    rightRow.text,
                    preferredLanguage
                )
                let semanticPenalty = dependencies.vocabularyPairPenalty(
                    semanticScore,
                    pairTolerance
                )
                let blocksFarJump =
                    indexDrift >= 3 &&
                    distance > pairTolerance * 0.55 &&
                    semanticScore < 2.1

                var bestCost = skipPenalty + dp[leftIndex + 1][rightIndex]
                var bestDecision: PairDecision = .skipLeft

                let skipRightCost = skipPenalty + dp[leftIndex][rightIndex + 1]
                if skipRightCost < bestCost {
                    bestCost = skipRightCost
                    bestDecision = .skipRight
                }

                if distance <= pairTolerance && !blocksFarJump {
                    let pairCost = distance + indexPenalty + semanticPenalty + dp[leftIndex + 1][rightIndex + 1]
                    if pairCost <= bestCost {
                        bestCost = pairCost
                        bestDecision = .pair
                    }
                }

                dp[leftIndex][rightIndex] = bestCost
                decision[leftIndex][rightIndex] = bestDecision
            }
        }

        var pairs: [PositionedLinePair] = []
        var leftIndex = 0
        var rightIndex = 0

        while leftIndex < leftCount, rightIndex < rightCount {
            switch decision[leftIndex][rightIndex] {
            case .pair:
                let leftRow = sortedLeftRows[leftIndex]
                let rightRow = sortedRightRows[rightIndex]
                pairs.append((leftRow.text, rightRow.text, max(leftRow.midY, rightRow.midY)))
                leftIndex += 1
                rightIndex += 1
            case .skipLeft:
                leftIndex += 1
            case .skipRight:
                let skippedRightRow = sortedRightRows[rightIndex]
                if let previousPair = pairs.last,
                   shouldAppendContinuationRow(
                    skippedRightRow,
                    to: previousPair,
                    nextLeftRow: leftIndex < leftCount ? sortedLeftRows[leftIndex] : nil,
                    averageHeight: averageHeight,
                    preferredLanguage: preferredLanguage
                   ) {
                    let combinedTarget = combinedContinuationTarget(previousPair.1, continuation: skippedRightRow.text)
                    pairs[pairs.count - 1] = (previousPair.0, combinedTarget, max(previousPair.2, skippedRightRow.midY))
                }
                rightIndex += 1
            }
        }

        return pairs
    }
}
