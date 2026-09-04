import SwiftUI
import Vision
import VisionKit
import UIKit

extension ScanImportView {
    var scanOCRNoiseFilter: ScanOCRNoiseFilter {
        ScanOCRNoiseFilter(
            dependencies: ScanOCRNoiseFilterDependencies(
                extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
                isStandalonePedagogicalMarker: { isStandalonePedagogicalMarker($0) },
                normalizedWords: { normalizedWords(in: $0) },
                normalizedLookupText: { normalizedLookupText($0) },
                germanDictionaryCoverageScore: { germanDictionaryCoverageScore(for: $0) },
                sourceLexiconCoverageScore: {
                    sourceLexiconCoverageScore(for: $0, language: scanSourceLanguage)
                },
                isLikelyMarkerNoise: { isLikelyMarkerNoise($0) },
                sourceLanguageScore: { sourceLanguageScore(for: $0, language: scanSourceLanguage) },
                germanScore: { germanScore(for: $0) }
            )
        )
    }

    var scanColumnPairMatcher: ScanColumnPairMatcher {
        ScanColumnPairMatcher(
            dependencies: ScanColumnPairMatcherDependencies(
                bestVocabularyPairScore: { source, target, preferredLanguage in
                    bestVocabularyPairScore(
                        source: source,
                        target: target,
                        preferredLanguage: preferredLanguage
                    )
                },
                vocabularyPairPenalty: { semanticScore, pairTolerance in
                    vocabularyPairPenalty(for: semanticScore, pairTolerance: pairTolerance)
                },
                extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
                isLikelyHeadingOrMetaLine: { isLikelyHeadingOrMetaLine($0) },
                normalizedLookupText: { normalizedLookupText($0) },
                normalizedWords: { normalizedWords(in: $0) },
                germanDictionaryCoverageScore: { germanDictionaryCoverageScore(for: $0) }
            )
        )
    }

    var scanOCRAnalyzer: ScanOCRAnalyzer {
        ScanOCRAnalyzer(
            dependencies: ScanOCRAnalyzerDependencies(
                sourceLanguage: scanSourceLanguage,
                filteredVocabularyBoxes: { filteredVocabularyBoxes(from: $0) },
                makeColumnPairs: { boxes, preferredLanguage in
                    makeColumnPairs(from: boxes, preferredLanguage: preferredLanguage)
                },
                pairCandidateSelectionScore: { pairs, preferredLanguage in
                    scanPreviewBuilder.pairCandidateSelectionScore(
                        pairs,
                        preferredLanguage: preferredLanguage
                    )
                },
                listModePreviewPairs: { boxes, sourceLanguage in
                    scanPreviewBuilder.listModePreviewPairs(
                        from: boxes,
                        sourceLanguage: sourceLanguage
                    )
                },
                textModePreviewPairs: { lines, sourceLanguage in
                    scanPreviewBuilder.textModePreviewPairs(
                        from: lines,
                        sourceLanguage: sourceLanguage
                    )
                },
                extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
                deduplicatePreviewPairs: { deduplicatedPreviewPairs($0) }
            )
        )
    }

    var scanOCRLineExtractor: ScanOCRLineExtractor {
        ScanOCRLineExtractor(
            dependencies: ScanOCRLineExtractorDependencies(
                sanitizedLine: { sanitizedLine($0) }
            )
        )
    }

    var scanOCRImagePreprocessor: ScanOCRImagePreprocessor {
        ScanOCRImagePreprocessor()
    }

    var scanOCRTextSanitizer: ScanOCRTextSanitizer {
        ScanOCRTextSanitizer()
    }

    var scanOCRTermExtractor: ScanOCRTermExtractor {
        ScanOCRTermExtractor(
            dependencies: ScanOCRTermExtractorDependencies(
                sanitizedLine: { sanitizedLine($0) },
                cleanedQuizDisplayText: { cleanedQuizDisplayText($0) },
                normalizedLookupWords: { normalizedLookupWords($0) },
                preservingTerminalSentencePunctuation: { original, text, cardType in
                    preservingTerminalSentencePunctuation(
                        from: original,
                        in: text,
                        style: .neutral,
                        cardType: cardType
                    )
                },
                sourceLexiconCoverageScore: { text, language in
                    sourceLexiconCoverageScore(for: text, language: language)
                },
                germanDictionaryCoverageScore: { germanDictionaryCoverageScore(for: $0) },
                normalizedLookupText: { normalizedLookupText($0) },
                normalizedWords: { normalizedWords(in: $0) }
            )
        )
    }

    func extractOCRLineBoxes(
        from image: UIImage,
        sourceLanguage: StudyLanguage,
        includeGermanTargetLanguage: Bool,
        recognitionLevel: VNRequestTextRecognitionLevel,
        usesLanguageCorrection: Bool,
        customWordsLimit: Int
    ) -> [OCRLineBox] {
        scanOCRLineExtractor.extractLineBoxes(
            from: image,
            sourceLanguage: sourceLanguage,
            includeGermanTargetLanguage: includeGermanTargetLanguage,
            recognitionLevel: recognitionLevel,
            usesLanguageCorrection: usesLanguageCorrection,
            customWordsLimit: customWordsLimit
        )
    }
}
