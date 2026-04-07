import Foundation

struct ScanVocabularyPairRepairDependencies {
    let extractedDisplayTerm: (String) -> String
    let isLikelyHeadingOrMetaLine: (String) -> Bool
    let sourceLanguageScore: (String, StudyLanguage) -> Double
    let germanScore: (String) -> Double
    let dictionaryCoverageScore: (String, StudyLanguage) -> Double
    let germanDictionaryCoverageScore: (String) -> Double
    let sourceLexiconCoverageScore: (String, StudyLanguage) -> Double
    let normalizedLookupText: (String) -> String
    let normalizedWords: (String) -> [String]
    let inferredCardType: (String, String) -> CardType
    let canonicalizedGermanTargetIfNeeded: (String, String, CardType, StudyLanguage) -> String
    let germanDisplayText: (String, CardType, String) -> String
    let normalizedEnglishVerbMarker: (String) -> String
    let scanStopWords: (StudyLanguage) -> Set<String>
    let detectedTerminalSentencePunctuation: (String) -> String?
    let inferredGermanTerminalSentencePunctuation: (String, CardType?) -> String?
}

struct ScanVocabularyPairRepair {
    let dependencies: ScanVocabularyPairRepairDependencies
}
