import Foundation
import CoreGraphics

extension ScanColumnPairMatcher {
    func pairingVerticalTolerance(
        leftRows: [OCRLineBox],
        rightRows: [OCRLineBox],
        averageHeight: CGFloat
    ) -> CGFloat {
        let gapEstimate = combinedRowGapEstimate(leftRows: leftRows, rightRows: rightRows)
        let baseTolerance = max(averageHeight * 1.55, 0.028)

        guard gapEstimate > 0 else { return baseTolerance }
        return max(0.028, min(baseTolerance, gapEstimate * 0.78))
    }

    func combinedRowGapEstimate(leftRows: [OCRLineBox], rightRows: [OCRLineBox]) -> CGFloat {
        let leftEstimate = rowGapEstimate(for: leftRows)
        let rightEstimate = rowGapEstimate(for: rightRows)

        if leftEstimate > 0 && rightEstimate > 0 {
            return min(leftEstimate, rightEstimate)
        }

        return max(leftEstimate, rightEstimate)
    }

    func rowGapEstimate(for rows: [OCRLineBox]) -> CGFloat {
        guard rows.count >= 2 else { return 0 }

        let sortedRows = rows.sorted { $0.midY > $1.midY }
        let gaps = zip(sortedRows, sortedRows.dropFirst()).map { previous, current in
            abs(previous.midY - current.midY)
        }
        .filter { $0 > 0.008 }
        .sorted()

        guard !gaps.isEmpty else { return 0 }
        return gaps[gaps.count / 2]
    }

    func mergeBoxesIntoRows(_ boxes: [OCRLineBox]) -> [OCRLineBox] {
        let sortedBoxes = boxes.sorted {
            if abs($0.midY - $1.midY) > 0.018 {
                return $0.midY > $1.midY
            }
            return $0.minX < $1.minX
        }

        var rows: [OCRLineBox] = []

        for box in sortedBoxes {
            if let last = rows.last {
                let tolerance = max(last.height, box.height) * 0.7
                let horizontalGap = max(0, box.minX - last.maxX)
                let horizontalGapTolerance = max(max(last.width, box.width) * 0.7, 0.028)

                if abs(last.midY - box.midY) <= tolerance && horizontalGap <= horizontalGapTolerance {
                    let combinedText = [last.text, box.text]
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    let combinedRect = last.boundingBox.union(box.boundingBox)
                    rows[rows.count - 1] = OCRLineBox(text: combinedText, boundingBox: combinedRect)
                    continue
                }
            }

            rows.append(box)
        }

        return rows
    }

    func mergeWrappedContinuationRows(
        _ rows: [OCRLineBox],
        preferredLanguage: StudyLanguage?
    ) -> [OCRLineBox] {
        guard rows.count >= 2 else { return rows }

        let sortedRows = rows.sorted { $0.midY > $1.midY }
        var merged: [OCRLineBox] = []

        for row in sortedRows {
            if let last = merged.last,
               shouldMergeWrappedContinuation(
                previous: last,
                current: row,
                preferredLanguage: preferredLanguage
               ) {
                let combinedText = combinedContinuationTarget(last.text, continuation: row.text)
                let combinedRect = last.boundingBox.union(row.boundingBox)
                merged[merged.count - 1] = OCRLineBox(text: combinedText, boundingBox: combinedRect)
                continue
            }

            merged.append(row)
        }

        return merged
    }

    func shouldMergeWrappedContinuation(
        previous: OCRLineBox,
        current: OCRLineBox,
        preferredLanguage: StudyLanguage?
    ) -> Bool {
        let verticalGap = abs(previous.midY - current.midY)
        let verticalTolerance = max(max(previous.height, current.height) * 1.2, 0.045)
        guard verticalGap <= verticalTolerance else { return false }

        let alignmentDelta = abs(previous.minX - current.minX)
        let overlapWidth = max(0, min(previous.maxX, current.maxX) - max(previous.minX, current.minX))
        let overlapRatio = overlapWidth / max(min(previous.width, current.width), 0.0001)

        guard alignmentDelta <= 0.06 || overlapRatio >= 0.45 else { return false }

        let currentText = dependencies.extractedDisplayTerm(current.text)
        let previousText = dependencies.extractedDisplayTerm(previous.text)
        guard !currentText.isEmpty, !previousText.isEmpty else { return false }

        let currentLooksLikeContinuation = looksLikeTranslationContinuation(currentText)
        let currentWordCount = dependencies.normalizedWords(currentText).count
        let previousEndsOpen = !(previousText.hasSuffix(".") || previousText.hasSuffix("!") || previousText.hasSuffix("?"))
        let currentGermanCoverage = dependencies.germanDictionaryCoverageScore(currentText)

        if currentLooksLikeContinuation {
            return currentGermanCoverage >= 0.34 &&
                currentWordCount <= 5 &&
                current.width <= max(previous.width * 1.25, 0.18)
        }

        return previousEndsOpen &&
            currentWordCount <= 5 &&
            currentGermanCoverage >= 0.34 &&
            current.width <= max(previous.width * 1.25, 0.18)
    }
}
