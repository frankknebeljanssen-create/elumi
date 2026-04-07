import Foundation

extension ScanPreviewBuilder {
    func pairCandidateSelectionScore(
        _ pairs: [LinePair],
        preferredLanguage: StudyLanguage?
    ) -> Double {
        let completeCount = completePreviewPairCount(for: pairs)
        let semanticScore = semanticPairScore(for: pairs, preferredLanguage: preferredLanguage)
        let suspiciousPenalty = Double(max(0, pairs.count - completeCount)) * 1.35
        return Double(completeCount) * 4.2
            + Double(pairs.count) * 0.85
            + semanticScore * 3.6
            - suspiciousPenalty
    }

    func completePreviewPairCount(for pairs: [LinePair]) -> Int {
        let cleanedText = pairs
            .map { "\($0.0) = \($0.1)" }
            .joined(separator: "\n")

        return dependencies.parsePreviewPairs(cleanedText)
            .filter { pair in
                !dependencies.sanitizedLine(pair.french).isEmpty &&
                !dependencies.sanitizedLine(pair.german).isEmpty
            }
            .count
    }

    func semanticPairScore(
        for pairs: [LinePair],
        preferredLanguage: StudyLanguage?
    ) -> Double {
        guard !pairs.isEmpty else { return -Double.infinity }

        let semanticSum = pairs.reduce(0.0) { partial, pair in
            partial + dependencies.bestVocabularyPairScore(pair.0, pair.1, preferredLanguage)
        }

        return semanticSum / Double(pairs.count)
    }

    func bestPairCandidate(
        from candidates: [[LinePair]],
        preferredLanguage: StudyLanguage?
    ) -> [LinePair] {
        candidates
            .filter { !$0.isEmpty }
            .max { lhs, rhs in
                let lhsScore = pairCandidateSelectionScore(lhs, preferredLanguage: preferredLanguage)
                let rhsScore = pairCandidateSelectionScore(rhs, preferredLanguage: preferredLanguage)
                if lhsScore != rhsScore {
                    return lhsScore < rhsScore
                }

                let lhsSemantic = semanticPairScore(for: lhs, preferredLanguage: preferredLanguage)
                let rhsSemantic = semanticPairScore(for: rhs, preferredLanguage: preferredLanguage)
                if lhsSemantic != rhsSemantic {
                    return lhsSemantic < rhsSemantic
                }

                return lhs.count < rhs.count
            } ?? []
    }
}
