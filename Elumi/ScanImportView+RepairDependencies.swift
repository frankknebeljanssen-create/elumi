import SwiftUI

extension ScanImportView {
    var freeTextPostProcessor: ScanFreeTextPostProcessor {
        ScanFreeTextPostProcessor(
            dependencies: ScanFreeTextPostProcessorDependencies(
                extractDisplayTerm: { extractedDisplayTerm(from: $0) },
                normalizedWords: { normalizedWords(in: $0) },
                normalizedLookupText: { normalizedLookupText($0) },
                deduplicatePreviewPairs: { deduplicatedPreviewPairs($0) },
                lexiconPreviewPairs: { text, sourceLanguage in
                    scanPreviewBuilder.lexiconPreviewPairs(from: text, sourceLanguage: sourceLanguage)
                },
                canonicalizeSourceTerm: { text, sourceLanguage in
                    canonicalizedSourceTermIfNeeded(text, sourceLanguage: sourceLanguage)
                },
                isLikelyHeadingOrMetaLine: { isLikelyHeadingOrMetaLine($0) }
            )
        )
    }

    var scanVocabularyPairRepair: ScanVocabularyPairRepair {
        ScanVocabularyPairRepair(
            dependencies: ScanVocabularyPairRepairDependencies(
                extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
                isLikelyHeadingOrMetaLine: { isLikelyHeadingOrMetaLine($0) },
                sourceLanguageScore: { text, language in
                    sourceLanguageScore(for: text, language: language)
                },
                germanScore: { germanScore(for: $0) },
                dictionaryCoverageScore: { text, language in
                    dictionaryCoverageScore(for: text, language: language)
                },
                germanDictionaryCoverageScore: { germanDictionaryCoverageScore(for: $0) },
                sourceLexiconCoverageScore: { text, language in
                    sourceLexiconCoverageScore(for: text, language: language)
                },
                normalizedLookupText: { normalizedLookupText($0) },
                normalizedWords: { normalizedWords(in: $0) },
                inferredCardType: { source, target in
                    inferredCardType(forSource: source, target: target)
                },
                canonicalizedGermanTargetIfNeeded: { target, source, cardType, sourceLanguage in
                    canonicalizedGermanTargetIfNeeded(
                        target,
                        source: source,
                        cardType: cardType,
                        sourceLanguage: sourceLanguage
                    )
                },
                germanDisplayText: { text, cardType, sourceHint in
                    germanDisplayText(text, cardType: cardType, sourceHint: sourceHint)
                },
                normalizedEnglishVerbMarker: { normalizedEnglishVerbMarker(in: $0) },
                scanStopWords: { scanStopWords(for: $0) },
                detectedTerminalSentencePunctuation: { detectedTerminalSentencePunctuation(from: $0) },
                inferredGermanTerminalSentencePunctuation: { text, cardType in
                    inferredGermanTerminalSentencePunctuation(text, cardType: cardType)
                }
            )
        )
    }

    var scanImportNormalizer: ScanImportNormalizer {
        ScanImportNormalizer(
            dependencies: ScanImportNormalizerDependencies(
                extractedDisplayTerm: { extractedDisplayTerm(from: $0) },
                preservingTerminalSentencePunctuation: { original, candidate, cardType in
                    preservingTerminalSentencePunctuation(
                        from: original,
                        in: candidate,
                        style: .neutral,
                        cardType: cardType
                    )
                },
                canonicalizedSourceTermIfNeeded: { text, sourceLanguage in
                    canonicalizedSourceTermIfNeeded(text, sourceLanguage: sourceLanguage)
                },
                germanDisplayText: { text, cardType, sourceHint in
                    germanDisplayText(text, cardType: cardType, sourceHint: sourceHint)
                },
                bestLocalTranslationMatch: { source, sourceLanguage in
                    bestLocalTranslationMatch(for: source, sourceLanguage: sourceLanguage)
                },
                shouldPreserveScannedGermanTargetText: { original, canonical in
                    shouldPreserveScannedGermanTargetText(original, insteadOf: canonical)
                },
                normalizedLookupText: { normalizedLookupText($0) },
                compactLookupKey: { compactLookupKey($0) },
                isLikelyOCRCorruptedWordToken: { isLikelyOCRCorruptedWordToken($0) },
                germanDictionaryCoverageScore: { germanDictionaryCoverageScore(for: $0) },
                ocrConfusableSimilarityScore: { lhs, rhs in
                    ocrConfusableSimilarityScore(lhs, rhs)
                },
                vocabularyPairScore: { source, target, sourceLanguage in
                    vocabularyPairScore(
                        source: source,
                        target: target,
                        sourceLanguage: sourceLanguage
                    )
                },
                sourceLanguageScore: { text, sourceLanguage in
                    sourceLanguageScore(for: text, language: sourceLanguage)
                },
                germanScore: { germanScore(for: $0) },
                isLikelyMarkerNoise: { isLikelyMarkerNoise($0) },
                sourceLexiconCoverageScore: { text, sourceLanguage in
                    sourceLexiconCoverageScore(for: text, language: sourceLanguage)
                },
                looksLikeEnglishInfinitiveMarker: { looksLikeEnglishInfinitiveMarker($0) },
                normalizedEnglishVerbMarker: { normalizedEnglishVerbMarker(in: $0) },
                sourceDisplayText: { text, sourceLanguage in
                    sourceDisplayText(text, sourceLanguage: sourceLanguage)
                },
                detectedTerminalSentencePunctuation: { detectedTerminalSentencePunctuation(from: $0) },
                applyingTerminalSentencePunctuation: { punctuation, text, style in
                    applyingTerminalSentencePunctuation(punctuation, to: text, style: style)
                },
                inferredGermanTerminalSentencePunctuation: { text, cardType in
                    inferredGermanTerminalSentencePunctuation(text, cardType: cardType)
                }
            )
        )
    }

    var scanVocabularyItemFactory: ScanVocabularyItemFactory {
        ScanVocabularyItemFactory(
            dependencies: ScanVocabularyItemFactoryDependencies(
                extractedTermComponents: { extractedTermComponents(from: $0) },
                normalizedSourceImportTerm: { normalizedSourceImportTerm($0) },
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

    var scanLanguageScorer: ScanLanguageScorer {
        ScanLanguageScorer()
    }
}
