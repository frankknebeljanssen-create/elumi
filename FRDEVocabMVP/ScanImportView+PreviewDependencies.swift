import SwiftUI

extension ScanImportView {
    var scanPreviewBuilder: ScanPreviewBuilder {
        ScanPreviewBuilder(
            dependencies: ScanPreviewBuilderDependencies(
                filteredVocabularyBoxes: { filteredVocabularyBoxes(from: $0) },
                makeColumnPairs: { boxes, preferredLanguage in
                    makeColumnPairs(from: boxes, preferredLanguage: preferredLanguage)
                },
                repairedVocabularyPairs: { pairs, sourceLanguage in
                    repairedVocabularyPairs(pairs, sourceLanguage: sourceLanguage)
                },
                makePreviewPair: { first, second in
                    makePreviewPair(first: first, second: second)
                },
                deduplicatePreviewPairs: { deduplicatedPreviewPairs($0) },
                parsePreviewPairs: { parsePreviewPairs(from: $0) },
                extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
                normalizedLookupText: { normalizedLookupText($0) },
                normalizedPreviewPair: { normalizedPreviewPair($0) },
                canonicalizedSourceTermIfNeeded: { text, sourceLanguage in
                    canonicalizedSourceTermIfNeeded(text, sourceLanguage: sourceLanguage)
                },
                looksLikeEnglishInfinitiveMarker: { looksLikeEnglishInfinitiveMarker($0) },
                normalizedEnglishVerbMarker: { normalizedEnglishVerbMarker(in: $0) },
                bestVocabularyPairScore: { source, target, preferredLanguage in
                    bestVocabularyPairScore(
                        source: source,
                        target: target,
                        preferredLanguage: preferredLanguage
                    )
                },
                sanitizedLine: { sanitizedLine($0) },
                stopWords: { scanStopWords(for: $0) },
                bestLexiconTranslation: { text, sourceLanguage in
                    DataStore.bestLexiconTranslation(for: text, sourceLanguage: sourceLanguage)
                }
            )
        )
    }

    var scanPreviewPairParser: ScanPreviewPairParser {
        ScanPreviewPairParser(
            dependencies: ScanPreviewPairParserDependencies(
                extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
                isStandalonePedagogicalMarker: { isStandalonePedagogicalMarker($0) },
                isLikelyHeadingOrMetaLine: { isLikelyHeadingOrMetaLine($0) },
                inferredCardType: { source, target in
                    inferredCardType(forSource: source, target: target)
                },
                isSourceColumnFirst: { first, second in
                    isSourceColumnFirst(first: first, second: second)
                },
                isLikelyOrphanTargetPreviewLine: { line, sourceLanguage in
                    isLikelyOrphanTargetPreviewLine(line, sourceLanguage: sourceLanguage)
                },
                sanitizedLine: { sanitizedLine($0) },
                normalizedSourceImportTerm: { text, sourceLanguage in
                    normalizedSourceImportTerm(text, sourceLanguage: sourceLanguage)
                },
                canonicalizedGermanTargetIfNeeded: { target, source, cardType, sourceLanguage in
                    canonicalizedGermanTargetIfNeeded(
                        target,
                        source: source,
                        cardType: cardType,
                        sourceLanguage: sourceLanguage
                    )
                },
                synchronizedPairTerminalSentencePunctuation: { source, target, sourceLanguage, cardType in
                    synchronizedPairTerminalSentencePunctuation(
                        source: source,
                        target: target,
                        sourceLanguage: sourceLanguage,
                        cardType: cardType
                    )
                }
            )
        )
    }

    var scanPreviewTextBridge: ScanPreviewTextBridge {
        ScanPreviewTextBridge(
            dependencies: ScanPreviewTextBridgeDependencies(
                parsePreviewPairs: { parsePreviewPairs(from: $0) },
                normalizedPreviewPair: { normalizedPreviewPair($0) }
            )
        )
    }

    var scanPreviewAssessor: ScanPreviewAssessor {
        ScanPreviewAssessor(
            extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
            bestVocabularyPairScore: { source, target, sourceLanguage in
                bestVocabularyPairScore(
                    source: source,
                    target: target,
                    preferredLanguage: sourceLanguage
                )
            },
            sourceLanguageScore: { text, sourceLanguage in
                sourceLanguageScore(for: text, language: sourceLanguage)
            },
            germanScore: { germanScore(for: $0) },
            normalizedWords: { normalizedWords(in: $0) }
        )
    }
}
