import Foundation

struct ScanImportNormalizerDependencies {
    typealias TranslationMatch = (sourceTerm: String, suggestions: [String], matchDistance: Double)

    let extractedDisplayTerm: (String) -> String
    let preservingTerminalSentencePunctuation: (String, String, CardType) -> String
    let canonicalizedSourceTermIfNeeded: (String, StudyLanguage) -> String
    let germanDisplayText: (String, CardType, String) -> String
    let bestLocalTranslationMatch: (String, StudyLanguage) -> TranslationMatch?
    let shouldPreserveScannedGermanTargetText: (String, String) -> Bool
    let normalizedLookupText: (String) -> String
    let compactLookupKey: (String) -> String
    let isLikelyOCRCorruptedWordToken: (String) -> Bool
    let germanDictionaryCoverageScore: (String) -> Double
    let ocrConfusableSimilarityScore: (String, String) -> Double
    let vocabularyPairScore: (String, String, StudyLanguage) -> Double
    let sourceLanguageScore: (String, StudyLanguage) -> Double
    let germanScore: (String) -> Double
    let isLikelyMarkerNoise: (String) -> Bool
    let sourceLexiconCoverageScore: (String, StudyLanguage) -> Double
    let looksLikeEnglishInfinitiveMarker: (String) -> Bool
    let normalizedEnglishVerbMarker: (String) -> String
    let sourceDisplayText: (String, StudyLanguage) -> String
    let detectedTerminalSentencePunctuation: (String) -> String?
    let applyingTerminalSentencePunctuation: (String, String, SentenceTerminalPunctuationStyle) -> String
    let inferredGermanTerminalSentencePunctuation: (String, CardType?) -> String?
}

struct ScanImportNormalizer {
    let dependencies: ScanImportNormalizerDependencies
}
