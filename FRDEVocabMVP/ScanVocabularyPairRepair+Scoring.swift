import Foundation

extension ScanVocabularyPairRepair {
    func repairedVocabularyPairs(
        _ pairs: [(String, String)],
        sourceLanguage: StudyLanguage
    ) -> [(String, String)] {
        guard pairs.count >= 2 else { return pairs }

        var repairedPairs = pairs
        var index = 0

        while index + 1 < repairedPairs.count {
            let current = repairedPairs[index]
            let next = repairedPairs[index + 1]

            let currentFirstScore = bestVocabularyPairScore(
                source: current.0,
                target: current.1,
                preferredLanguage: sourceLanguage
            )
            let currentSecondScore = bestVocabularyPairScore(
                source: next.0,
                target: next.1,
                preferredLanguage: sourceLanguage
            )
            let swappedFirstScore = bestVocabularyPairScore(
                source: current.0,
                target: next.1,
                preferredLanguage: sourceLanguage
            )
            let swappedSecondScore = bestVocabularyPairScore(
                source: next.0,
                target: current.1,
                preferredLanguage: sourceLanguage
            )

            let currentCombinedScore = currentFirstScore + currentSecondScore
            let swappedCombinedScore = swappedFirstScore + swappedSecondScore

            if swappedCombinedScore > currentCombinedScore + 0.4 &&
                min(currentFirstScore, currentSecondScore) < 1.6 {
                repairedPairs[index] = (current.0, next.1)
                repairedPairs[index + 1] = (next.0, current.1)
                index += 2
                continue
            }

            index += 1
        }

        return repairedPairs.map {
            correctedPairIfNeeded(
                source: $0.0,
                target: $0.1,
                sourceLanguage: sourceLanguage
            )
        }
    }

    func vocabularyPairScore(
        source: String,
        target: String,
        sourceLanguage: StudyLanguage
    ) -> Double {
        let cleanedSource = dependencies.extractedDisplayTerm(source)
        let cleanedTarget = dependencies.extractedDisplayTerm(target)

        guard !cleanedSource.isEmpty, !cleanedTarget.isEmpty else { return -10 }
        guard
            !dependencies.isLikelyHeadingOrMetaLine(cleanedSource),
            !dependencies.isLikelyHeadingOrMetaLine(cleanedTarget)
        else {
            return -8
        }

        let sourceScore =
            dependencies.sourceLanguageScore(cleanedSource, sourceLanguage)
            - dependencies.germanScore(cleanedSource) * 0.22
        let targetScore =
            dependencies.germanScore(cleanedTarget)
            - dependencies.sourceLanguageScore(cleanedTarget, sourceLanguage) * 0.38
        let bridgeScore = cognateSimilarityScore(source: cleanedSource, target: cleanedTarget)
        let sourceDictionaryScore = dependencies.dictionaryCoverageScore(cleanedSource, sourceLanguage)
        let targetDictionaryScore = dependencies.germanDictionaryCoverageScore(cleanedTarget)
        let localAgreementScore = localTranslationAgreementScore(
            source: cleanedSource,
            target: cleanedTarget,
            sourceLanguage: sourceLanguage
        )

        return sourceScore + targetScore + bridgeScore + sourceDictionaryScore + targetDictionaryScore + localAgreementScore
    }

    func bestVocabularyPairScore(
        source: String,
        target: String,
        preferredLanguage: StudyLanguage?
    ) -> Double {
        let englishScore = vocabularyPairScore(
            source: source,
            target: target,
            sourceLanguage: .english
        )
        let frenchScore = vocabularyPairScore(
            source: source,
            target: target,
            sourceLanguage: .french
        )

        guard let preferredLanguage else {
            return max(englishScore, frenchScore)
        }

        switch preferredLanguage {
        case .english:
            return max(englishScore, frenchScore - 0.12)
        case .french:
            return max(frenchScore, englishScore - 0.12)
        }
    }

    func vocabularyPairPenalty(for semanticScore: Double, pairTolerance: Double) -> Double {
        switch semanticScore {
        case ..<0.15:
            return pairTolerance * 0.95
        case ..<0.45:
            return pairTolerance * 0.6
        case ..<0.85:
            return pairTolerance * 0.25
        case 1.9...:
            return -pairTolerance * 0.95
        case 1.45...:
            return -pairTolerance * 0.65
        case 1.05...:
            return -pairTolerance * 0.35
        default:
            return 0
        }
    }
}
