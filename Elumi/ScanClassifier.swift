import Foundation

struct ScanDocumentClassifier {
    func classify(
        analysis: ScanAnalysisResult,
        lineBoxes: [OCRLineBox]
    ) -> ScanDocumentType {
        guard !analysis.entries.isEmpty || !lineBoxes.isEmpty else {
            return .unknown
        }

        switch analysis.mode {
        case .list:
            if isLikelyTextbookTable(analysis: analysis, lineBoxes: lineBoxes) {
                return .textbookTable
            }
            return .vocabularyList
        case .text:
            if let posterOrCoverType = posterOrCoverType(lineBoxes: lineBoxes) {
                return posterOrCoverType
            }
            if isLikelyMixedLayout(lineBoxes: lineBoxes) {
                return .mixedLayout
            }
            return .freeText
        }
    }

    private func isLikelyTextbookTable(
        analysis: ScanAnalysisResult,
        lineBoxes: [OCRLineBox]
    ) -> Bool {
        let texts = cleanedTexts(from: lineBoxes)
        guard analysis.usedColumnPairing, !texts.isEmpty else { return false }

        let sentenceLikeRatio = ratio(of: texts) { isSentenceLike($0) }
        let headingLikeRatio = ratio(of: texts) { isHeadingLike($0) }
        let noteLikeRatio = ratio(of: texts) { isPedagogicalNote($0) }
        let lineDensity = Double(analysis.recognizedLineCount) / Double(max(analysis.entries.count, 1))

        return analysis.recognizedLineCount >= max(analysis.entries.count * 2, 10) &&
            (sentenceLikeRatio >= 0.16 || headingLikeRatio >= 0.08 || noteLikeRatio >= 0.14 || lineDensity >= 2.45)
    }

    private func isLikelyMixedLayout(lineBoxes: [OCRLineBox]) -> Bool {
        let texts = cleanedTexts(from: lineBoxes)
        guard texts.count >= 8 else { return false }

        let lengths = texts.map(\.count)
        let sentenceLikeRatio = ratio(of: texts) { isSentenceLike($0) }
        let headingLikeRatio = ratio(of: texts) { isHeadingLike($0) }
        let shortRatio = ratio(of: texts) { normalizedWords(in: $0).count <= 3 }
        let meanLength = Double(lengths.reduce(0, +)) / Double(max(lengths.count, 1))
        let variance = lengths.reduce(0.0) { partial, length in
            partial + pow(Double(length) - meanLength, 2)
        } / Double(max(lengths.count, 1))

        return sentenceLikeRatio >= 0.26 &&
            headingLikeRatio >= 0.06 &&
            shortRatio >= 0.16 &&
            variance >= 90
    }

    private func posterOrCoverType(lineBoxes: [OCRLineBox]) -> ScanDocumentType? {
        let texts = cleanedTexts(from: lineBoxes)
        guard texts.count <= 6, !texts.isEmpty else { return nil }

        let headingLikeCount = texts.filter { isHeadingLike($0) }.count
        let longTitleCount = texts.filter { $0.count >= 16 }.count
        let publicNoticeCount = texts.filter { isPublicNoticeLike($0) }.count
        let scheduleLikeCount = texts.filter { isScheduleLike($0) }.count

        if publicNoticeCount >= 1 || (headingLikeCount >= 2 && scheduleLikeCount >= 1) {
            return .poster
        }

        if headingLikeCount >= 1 && longTitleCount >= 1 {
            return .cover
        }

        return nil
    }

    private func cleanedTexts(from lineBoxes: [OCRLineBox]) -> [String] {
        lineBoxes
            .map(\.text)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func ratio(
        of texts: [String],
        where predicate: (String) -> Bool
    ) -> Double {
        guard !texts.isEmpty else { return 0 }
        return Double(texts.filter(predicate).count) / Double(texts.count)
    }

    private func normalizedWords(in text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    private func isSentenceLike(_ text: String) -> Bool {
        let words = normalizedWords(in: text).count
        return words >= 6 || text.contains("?") || text.contains("!") || text.contains(".")
    }

    private func isHeadingLike(_ text: String) -> Bool {
        let words = normalizedWords(in: text)
        guard !words.isEmpty else { return false }

        if text.contains("!") || text.contains(":") {
            return true
        }

        if words.count <= 5 && text.count >= 12 {
            return true
        }

        return false
    }

    private func isPublicNoticeLike(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let noticeMarkers = [
            "bienvenue", "merci", "respecter", "silence", "interdit", "attention",
            "défense", "defense", "prière", "priere", "sortie", "entrée", "entree",
            "pas de", "veuillez"
        ]
        return noticeMarkers.contains { lowered.contains($0) }
    }

    private func isScheduleLike(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let scheduleMarkers = [
            "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche",
            "heure", "heures", "office", "offices"
        ]

        return scheduleMarkers.contains(where: { lowered.contains($0) }) ||
            text.range(of: #"\b\d{1,2}[:h]\d{0,2}\b"#, options: .regularExpression) != nil
    }

    private func isPedagogicalNote(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("fam") ||
            lowered.contains("adj") ||
            lowered.contains("inv") ||
            lowered.contains("hier") ||
            lowered.contains("[")
    }
}
