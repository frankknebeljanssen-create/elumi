import Foundation

extension ScanImportView {
    func isSourceColumnFirst(first: String, second: String) -> Bool {
        scanLanguageScorer.isSourceColumnFirst(
            first: first,
            second: second,
            sourceLanguage: scanSourceLanguage
        )
    }

    func sourceLanguageScore(for text: String) -> Double {
        scanLanguageScorer.sourceLanguageScore(
            for: text,
            language: scanSourceLanguage
        )
    }

    func sourceLanguageScore(for text: String, language: StudyLanguage) -> Double {
        scanLanguageScorer.sourceLanguageScore(for: text, language: language)
    }

    func germanScore(for text: String) -> Double {
        scanLanguageScorer.germanScore(for: text)
    }

    func normalizedWords(in text: String) -> [String] {
        scanLanguageScorer.normalizedWords(in: text)
    }

    func isLikelyHeadingOrMetaLine(_ text: String) -> Bool {
        scanOCRNoiseFilter.isLikelyHeadingOrMetaLine(text)
    }

    func dictionaryCoverageScore(for text: String, language: StudyLanguage) -> Double {
        scanLanguageScorer.dictionaryCoverageScore(
            for: text,
            language: language
        )
    }

    func germanDictionaryCoverageScore(for text: String) -> Double {
        scanLanguageScorer.germanDictionaryCoverageScore(for: text)
    }

    func sourceLexiconCoverageScore(for text: String, language: StudyLanguage) -> Double {
        scanLanguageScorer.sourceLexiconCoverageScore(
            for: text,
            language: language
        )
    }
}
