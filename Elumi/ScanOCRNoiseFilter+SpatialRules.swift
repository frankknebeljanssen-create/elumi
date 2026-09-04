import Foundation

extension ScanOCRNoiseFilter {
    func isLikelyEdgeNoiseBox(_ box: OCRLineBox, text: String, wordCount: Int) -> Bool {
        let isEdge = box.midY > 0.92 || box.midY < 0.08
        let isNearEdge = box.midY > 0.87 || box.midY < 0.12
        let sourceCoverage = dependencies.sourceLexiconCoverageScore(text)
        let germanCoverage = dependencies.germanDictionaryCoverageScore(text)
        let looksLikeRealContent =
            max(sourceCoverage, germanCoverage) >= 0.8 ||
            (sourceCoverage >= 0.62 && (text.contains("?") || text.contains("!") || text.contains(".")))

        if isEdge && box.width > 0.82 && wordCount >= 3 && !looksLikeRealContent {
            return true
        }

        if isNearEdge && box.width > 0.72 && wordCount >= 5 && !looksLikeRealContent {
            return true
        }

        if isNearEdge && box.width > 0.68 && isLikelyHeadingOrMetaLine(text) {
            return true
        }

        return false
    }

    func isLikelySideNoiseBox(_ box: OCRLineBox, text: String, wordCount: Int) -> Bool {
        let normalized = dependencies.normalizedLookupText(text)
        guard !normalized.isEmpty else { return true }

        let isHardSide = box.maxX >= 0.968 || box.minX <= 0.032
        let isNearSide = box.maxX >= 0.945 || box.minX <= 0.055
        let isTinyBox = box.width <= 0.06
        let isCompactBox = box.width <= 0.08
        let isVeryShort = normalized.count <= 3
        let germanCoverage = dependencies.germanDictionaryCoverageScore(text)
        let sourceCoverage = dependencies.sourceLexiconCoverageScore(text)
        let looksLikeNoise = dependencies.isLikelyMarkerNoise(text)
        let allCapsShort = text.range(of: #"^[A-ZÄÖÜ]{1,4}$"#, options: .regularExpression) != nil

        if isHardSide && isTinyBox && wordCount <= 1 && (looksLikeNoise || allCapsShort || isVeryShort) {
            return true
        }

        if isNearSide &&
            isCompactBox &&
            wordCount <= 1 &&
            isVeryShort &&
            germanCoverage < 0.34 &&
            sourceCoverage < 0.24 &&
            (looksLikeNoise || allCapsShort) {
            return true
        }

        return false
    }

    func isLikelyWorkbookHeaderBox(_ box: OCRLineBox, text: String, wordCount: Int) -> Bool {
        let isTopZone = box.midY >= 0.72
        guard isTopZone else { return false }
        let sourceCoverage = dependencies.sourceLexiconCoverageScore(text)
        let germanCoverage = dependencies.germanDictionaryCoverageScore(text)
        let looksLikeRealContent =
            max(sourceCoverage, germanCoverage) >= 0.76 ||
            (sourceCoverage >= 0.58 && wordCount <= 4)

        if box.width >= 0.26 && wordCount >= 3 && isLikelyHeadingOrMetaLine(text) {
            return true
        }

        if looksLikeRealContent {
            return false
        }

        if box.width >= 0.5 && wordCount >= 8 {
            return true
        }

        return box.width >= 0.42 &&
            wordCount >= 6 &&
            sourceCoverage < 0.44 &&
            germanCoverage < 0.44
    }

    func isLikelyExampleSentenceBox(_ box: OCRLineBox, text: String, wordCount: Int) -> Bool {
        guard box.minX >= 0.57 || box.midX >= 0.69 else { return false }
        guard wordCount >= 2 else { return false }

        let sourceStrength = dependencies.sourceLanguageScore(text)
        let germanStrength = dependencies.germanScore(text)
        let hasDialogueCue =
            text.contains("?") ||
            text.contains("!") ||
            text.contains(":") ||
            text.contains("—") ||
            text.contains(" - ")

        if hasDialogueCue && sourceStrength > germanStrength + 0.12 {
            return true
        }

        if box.minX >= 0.62 &&
            wordCount >= 2 &&
            sourceStrength > germanStrength + 0.08 &&
            (hasDialogueCue || text.contains("'") || text.contains("’")) {
            return true
        }

        if box.minX >= 0.7 &&
            wordCount >= 4 &&
            sourceStrength > germanStrength + 0.2 {
            return true
        }

        return false
    }
}
