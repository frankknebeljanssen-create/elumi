import Foundation

extension ScanImportView {
    func ocrConfusableSimilarityScore(_ lhs: String, _ rhs: String) -> Double {
        let maxLength = max(lhs.count, rhs.count)
        guard maxLength > 0 else { return 0 }

        let distance = ocrConfusableDistance(lhs, rhs)
        return max(0, 1.0 - (distance / Double(maxLength)))
    }

    func ocrConfusableDistance(_ lhs: String, _ rhs: String) -> Double {
        let left = Array(lhs)
        let right = Array(rhs)
        var dist = Array(
            repeating: Array(repeating: 0.0, count: right.count + 1),
            count: left.count + 1
        )

        for i in 0...left.count { dist[i][0] = Double(i) }
        for j in 0...right.count { dist[0][j] = Double(j) }

        guard !left.isEmpty, !right.isEmpty else {
            return Double(max(left.count, right.count))
        }

        for i in 1...left.count {
            for j in 1...right.count {
                let substitutionCost: Double
                if left[i - 1] == right[j - 1] {
                    substitutionCost = 0
                } else if areOCRConfusable(left[i - 1], right[j - 1]) {
                    substitutionCost = 0.22
                } else {
                    substitutionCost = 1
                }

                dist[i][j] = min(
                    dist[i - 1][j] + 1,
                    dist[i][j - 1] + 1,
                    dist[i - 1][j - 1] + substitutionCost
                )
            }
        }

        return dist[left.count][right.count]
    }

    func areOCRConfusable(_ lhs: Character, _ rhs: Character) -> Bool {
        lhs == rhs ||
        ocrConfusableAlternatives[lhs]?.contains(rhs) == true ||
        ocrConfusableAlternatives[rhs]?.contains(lhs) == true
    }

    var ocrConfusableAlternatives: [Character: Set<Character>] {
        [
            "0": ["o", "d"],
            "1": ["l", "i"],
            "2": ["z"],
            "3": ["a", "e"],
            "4": ["a"],
            "5": ["s"],
            "6": ["g"],
            "7": ["t"],
            "8": ["b"],
            "9": ["g", "q"],
            "o": ["0"],
            "d": ["0"],
            "l": ["1", "i"],
            "i": ["1", "l"],
            "z": ["2"],
            "a": ["3", "4"],
            "e": ["3"],
            "s": ["5"],
            "g": ["6", "9"],
            "t": ["7"],
            "b": ["8"],
            "q": ["9"]
        ]
    }
}
