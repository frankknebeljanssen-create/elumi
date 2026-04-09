import Foundation
import CoreGraphics

extension ScanColumnPairMatcher {
    func candidateColumnGroups(for boxes: [OCRLineBox]) -> [[[OCRLineBox]]] {
        var candidates: [[[OCRLineBox]]] = []

        let grouped = columnGroups(for: boxes)
        if grouped.count >= 2 {
            candidates.append(grouped)
        }

        if let medianSplit = medianSplitColumnGroups(for: boxes) {
            candidates.append(medianSplit)
        }

        if let largestGapSplit = largestGapColumnGroups(for: boxes) {
            candidates.append(largestGapSplit)
        }

        return candidates
    }

    func columnGroups(for boxes: [OCRLineBox]) -> [[OCRLineBox]] {
        let sortedBoxes = boxes.sorted { $0.midX < $1.midX }
        let averageWidth = sortedBoxes.map(\.width).reduce(0, +) / CGFloat(sortedBoxes.count)
        let threshold = max(averageWidth * 1.15, 0.10)

        var groups: [[OCRLineBox]] = []

        for box in sortedBoxes {
            if let lastIndex = groups.indices.last {
                let currentGroup = groups[lastIndex]
                let currentCenter = currentGroup.map(\.midX).reduce(0, +) / CGFloat(currentGroup.count)
                if abs(box.midX - currentCenter) <= threshold {
                    groups[lastIndex].append(box)
                } else {
                    groups.append([box])
                }
            } else {
                groups.append([box])
            }
        }

        return groups
            .filter { !$0.isEmpty }
            .sorted {
                ($0.map(\.midX).reduce(0, +) / CGFloat($0.count)) < ($1.map(\.midX).reduce(0, +) / CGFloat($1.count))
            }
    }

    func isLikelyAuxiliaryColumn(_ rows: [OCRLineBox]) -> Bool {
        guard !rows.isEmpty else { return true }

        let cleanedRows = rows.map { row in
            dependencies.extractedDisplayTerm(row.text).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let meaningfulRows = cleanedRows.filter {
            !$0.isEmpty && !dependencies.isLikelyHeadingOrMetaLine($0)
        }
        let meaningfulRatio = Double(meaningfulRows.count) / Double(rows.count)
        let averageWidth = rows.map(\.width).reduce(0, +) / CGFloat(rows.count)

        if meaningfulRows.isEmpty {
            return true
        }

        if averageWidth <= 0.11 && meaningfulRatio <= 0.55 {
            return true
        }

        if averageWidth <= 0.08 && meaningfulRatio <= 0.75 {
            return true
        }

        // Very sparse column (phonetics, numbering, etc.)
        if meaningfulRatio < 0.3 {
            return true
        }

        // Narrow column with only short items (pronunciation, indices)
        let shortItemCount = cleanedRows.filter { $0.count <= 8 }.count
        if averageWidth <= 0.15 && shortItemCount > rows.count * 2 / 3 {
            return true
        }

        return false
    }

    func medianSplitColumnGroups(for boxes: [OCRLineBox]) -> [[OCRLineBox]]? {
        guard boxes.count >= 4 else { return nil }

        let sortedMidX = boxes.map(\.midX).sorted()
        let median = sortedMidX[sortedMidX.count / 2]
        let left = boxes.filter { $0.midX <= median }.sorted { $0.midX < $1.midX }
        let right = boxes.filter { $0.midX > median }.sorted { $0.midX < $1.midX }

        guard !left.isEmpty, !right.isEmpty else { return nil }
        return [left, right]
    }

    func largestGapColumnGroups(for boxes: [OCRLineBox]) -> [[OCRLineBox]]? {
        guard boxes.count >= 4 else { return nil }

        let sortedBoxes = boxes.sorted { $0.midX < $1.midX }
        var bestGap: CGFloat = 0
        var splitIndex: Int?

        for index in 0..<(sortedBoxes.count - 1) {
            let gap = sortedBoxes[index + 1].midX - sortedBoxes[index].midX
            if gap > bestGap {
                bestGap = gap
                splitIndex = index
            }
        }

        guard let splitIndex, bestGap >= 0.08 else { return nil }

        let left = Array(sortedBoxes[...splitIndex])
        let right = Array(sortedBoxes[(splitIndex + 1)...])
        guard !left.isEmpty, !right.isEmpty else { return nil }
        return [left, right]
    }
}
