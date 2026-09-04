import Foundation

extension ScanVocabularyPairRepair {
    func bestReverseFrenchLexiconMatch(
        forGermanTarget target: String,
        cardType: CardType
    ) -> (sourceTerm: String, targetTerm: String, distance: Double)? {
        let lookupKey = dependencies.normalizedLookupText(target)
        let compactTarget = lookupKey.replacingOccurrences(of: " ", with: "")
        guard !lookupKey.isEmpty else { return nil }

        let frenchEntries = DataStore.internalLexiconEntries.filter {
            $0.sourceLanguage == .french && $0.cardType == cardType
        }

        if let exact = frenchEntries.first(where: {
            dependencies.normalizedLookupText($0.targetTerm) == lookupKey ||
            dependencies.normalizedLookupText($0.targetTerm).replacingOccurrences(of: " ", with: "") == compactTarget
        }) {
            return (exact.sourceTerm, exact.targetTerm, 0)
        }

        let candidates = frenchEntries.compactMap { entry -> (String, String, Double)? in
            let candidateKey = dependencies.normalizedLookupText(entry.targetTerm)
            let candidateCompact = candidateKey.replacingOccurrences(of: " ", with: "")
            guard !candidateKey.isEmpty, !candidateCompact.isEmpty else { return nil }

            let sharesPrefix =
                candidateKey.hasPrefix(String(lookupKey.prefix(2))) ||
                lookupKey.hasPrefix(String(candidateKey.prefix(2))) ||
                candidateCompact.hasPrefix(String(compactTarget.prefix(3))) ||
                compactTarget.hasPrefix(String(candidateCompact.prefix(3)))

            guard sharesPrefix else { return nil }

            let distance = scanLevenshtein(lookupKey, candidateKey)
            let compactDistance = scanLevenshtein(compactTarget, candidateCompact)
            let maxLength = max(lookupKey.count, candidateKey.count)
            let maxCompactLength = max(compactTarget.count, candidateCompact.count)
            guard maxLength > 0, maxCompactLength > 0 else { return nil }

            let ratio = Double(distance) / Double(maxLength)
            let compactRatio = Double(compactDistance) / Double(maxCompactLength)
            let effectiveRatio = min(ratio, compactRatio * 0.92)

            guard effectiveRatio <= 0.34 || compactRatio <= 0.28 else { return nil }
            return (entry.sourceTerm, entry.targetTerm, effectiveRatio)
        }
        .sorted { lhs, rhs in
            if lhs.2 == rhs.2 {
                return lhs.1.count < rhs.1.count
            }
            return lhs.2 < rhs.2
        }

        guard let best = candidates.first else { return nil }
        return best
    }

    func shouldPreferReverseFrenchLexiconMatch(
        _ reverseMatch: (sourceTerm: String, targetTerm: String, distance: Double),
        currentSource: String,
        currentTarget: String,
        sourceLanguage: StudyLanguage,
        cardType: CardType
    ) -> Bool {
        guard sourceLanguage == .french else { return false }

        let sourceCoverage = dependencies.dictionaryCoverageScore(currentSource, sourceLanguage)
        let targetCoverage = dependencies.germanDictionaryCoverageScore(currentTarget)
        let sourceLooksSuspicious =
            sourceCoverage < 0.28 ||
            isLikelyMarkerNoise(currentSource) ||
            isLikelyOCRCorruptedWordToken(currentSource) ||
            dependencies.sourceLexiconCoverageScore(currentSource, sourceLanguage) < 0.18
        let currentPairScore = vocabularyPairScore(
            source: currentSource,
            target: currentTarget,
            sourceLanguage: sourceLanguage
        )
        let reversePairScore = vocabularyPairScore(
            source: reverseMatch.sourceTerm,
            target: reverseMatch.targetTerm,
            sourceLanguage: sourceLanguage
        )

        return reverseMatch.distance <= 0.24 &&
            targetCoverage >= 0.34 &&
            sourceLooksSuspicious &&
            reversePairScore >= currentPairScore + 0.18 &&
            cardType == .phrases
    }

    func scanLevenshtein(_ lhs: String, _ rhs: String) -> Int {
        LexiconTextUtility.levenshtein(lhs, rhs)
    }
}
