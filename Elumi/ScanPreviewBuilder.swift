import Foundation
import NaturalLanguage

struct ScanPreviewBuilderDependencies {
    typealias LinePair = (String, String)

    let filteredVocabularyBoxes: ([OCRLineBox]) -> [OCRLineBox]
    let makeColumnPairs: ([OCRLineBox], StudyLanguage?) -> [LinePair]
    let repairedVocabularyPairs: ([LinePair], StudyLanguage) -> [LinePair]
    let makePreviewPair: (String, String) -> ImportPreviewPair?
    let deduplicatePreviewPairs: ([ImportPreviewPair]) -> [ImportPreviewPair]
    let parsePreviewPairs: (String) -> [ImportPreviewPair]
    let extractedDisplayTerm: (String) -> String
    let normalizedLookupText: (String) -> String
    let normalizedPreviewPair: (ImportPreviewPair) -> ImportPreviewPair
    let canonicalizedSourceTermIfNeeded: (String, StudyLanguage) -> String
    let looksLikeEnglishInfinitiveMarker: (String) -> Bool
    let normalizedEnglishVerbMarker: (String) -> String
    let bestVocabularyPairScore: (String, String, StudyLanguage?) -> Double
    let sanitizedLine: (String) -> String
    let stopWords: (StudyLanguage) -> Set<String>
    let bestLexiconTranslation: (String, StudyLanguage) -> String?
}

struct ScanPreviewBuilder {
    typealias LinePair = ScanPreviewBuilderDependencies.LinePair

    let dependencies: ScanPreviewBuilderDependencies
}
