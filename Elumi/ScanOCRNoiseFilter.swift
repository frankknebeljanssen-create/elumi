import Foundation

struct ScanOCRNoiseFilterDependencies {
    let extractedDisplayTerm: (String) -> String
    let isStandalonePedagogicalMarker: (String) -> Bool
    let normalizedWords: (String) -> [String]
    let normalizedLookupText: (String) -> String
    let germanDictionaryCoverageScore: (String) -> Double
    let sourceLexiconCoverageScore: (String) -> Double
    let isLikelyMarkerNoise: (String) -> Bool
    let sourceLanguageScore: (String) -> Double
    let germanScore: (String) -> Double
}

struct ScanOCRNoiseFilter {
    let dependencies: ScanOCRNoiseFilterDependencies

    func filteredVocabularyBoxes(from boxes: [OCRLineBox]) -> [OCRLineBox] {
        boxes.filter { box in
            let text = box.text.lowercased()
            let hasLetters = text.rangeOfCharacter(from: .letters) != nil
            guard hasLetters else { return false }

            let extracted = dependencies.extractedDisplayTerm(box.text)
            guard !extracted.isEmpty, !dependencies.isStandalonePedagogicalMarker(extracted) else {
                return false
            }

            if isLikelyHeadingOrMetaLine(text) {
                return false
            }

            if text.contains("www.") || text.contains("http") || text.contains(".de") || text.contains(".fr") || text.contains(".com") {
                return false
            }

            if text.range(of: #"^(seite|page)\s*\d+$"#, options: .regularExpression) != nil {
                return false
            }

            if text.range(of: #"^(p|pp|s)\.?\s*\d+$"#, options: .regularExpression) != nil {
                return false
            }

            if text.range(of: #"^(no\s*pl\.?|n\.\s*pl\.?|no\s*plural)$"#, options: .regularExpression) != nil {
                return false
            }

            if text.range(of: #"^\d+([\/\-]\d+)?$"#, options: .regularExpression) != nil {
                return false
            }

            let wordCount = dependencies.normalizedWords(text).count
            if isLikelyEdgeNoiseBox(box, text: text, wordCount: wordCount) {
                return false
            }

            if isLikelySideNoiseBox(box, text: text, wordCount: wordCount) {
                return false
            }

            if isLikelyWorkbookHeaderBox(box, text: text, wordCount: wordCount) {
                return false
            }

            if isLikelyExampleSentenceBox(box, text: text, wordCount: wordCount) {
                return false
            }

            return true
        }
    }
}
