import Foundation

extension AIScanProvider {
    func bestFrenchLexiconMatch(
        forSource source: String
    ) -> (sourceTerm: String, suggestions: [String], distance: Double)? {
        let lookupKey = aiNormalizedLookupText(source)
        guard !lookupKey.isEmpty else { return nil }

        if let direct = DataStore.localTranslationLookup[.french]?[lookupKey], !direct.isEmpty {
            return (
                DataStore.cachedCanonicalSourceTerm(
                    for: lookupKey,
                    sourceLanguage: .french
                ) ?? source,
                direct,
                0
            )
        }

        guard let approximate = DataStore.cachedApproximateTranslationSuggestions(
            for: lookupKey,
            sourceLanguage: .french
        ), approximate.distance <= 0.24 else {
            return nil
        }

        return (
            DataStore.cachedCanonicalSourceTerm(
                for: approximate.lookupKey,
                sourceLanguage: .french
            ) ?? source,
            approximate.suggestions,
            approximate.distance
        )
    }

    func bestTrimmedFrenchLexiconMatch(
        forSource source: String
    ) -> (sourceTerm: String, suggestions: [String], distance: Double)? {
        let tokens = aiNormalizedWords(source)
        guard tokens.count >= 2 else { return nil }

        for prefixLength in stride(from: tokens.count - 1, through: 1, by: -1) {
            let candidate = tokens.prefix(prefixLength).joined(separator: " ")
            let trailing = tokens.dropFirst(prefixLength).joined(separator: " ")
            guard aiTrailingLooksSuspicious(trailing) else { continue }
            guard let match = bestFrenchLexiconMatch(forSource: candidate) else { continue }
            if match.distance <= 0.2 {
                return match
            }
        }

        return nil
    }

    func bestReverseFrenchLexiconMatch(
        forGermanTarget target: String,
        cardType: CardType
    ) -> (sourceTerm: String, targetTerm: String, distance: Double)? {
        let lookupKey = aiNormalizedLookupText(target)
        let compactTarget = aiCompactLookupKey(target)
        guard !lookupKey.isEmpty else { return nil }

        let frenchEntries = DataStore.internalLexiconEntries.filter {
            $0.sourceLanguage == .french && $0.cardType == cardType
        }

        if let exact = frenchEntries.first(where: {
            aiNormalizedLookupText($0.targetTerm) == lookupKey ||
            aiCompactLookupKey($0.targetTerm) == compactTarget
        }) {
            return (exact.sourceTerm, exact.targetTerm, 0)
        }

        return frenchEntries
            .compactMap { entry -> (sourceTerm: String, targetTerm: String, distance: Double)? in
                let candidateKey = aiNormalizedLookupText(entry.targetTerm)
                let candidateCompact = aiCompactLookupKey(entry.targetTerm)
                guard !candidateKey.isEmpty, !candidateCompact.isEmpty else { return nil }

                let sharesPrefix =
                    candidateKey.hasPrefix(String(lookupKey.prefix(2))) ||
                    lookupKey.hasPrefix(String(candidateKey.prefix(2))) ||
                    candidateCompact.hasPrefix(String(compactTarget.prefix(3))) ||
                    compactTarget.hasPrefix(String(candidateCompact.prefix(3)))

                guard sharesPrefix else { return nil }

                let distance = aiLevenshtein(lookupKey, candidateKey)
                let compactDistance = aiLevenshtein(compactTarget, candidateCompact)
                let maxLength = max(lookupKey.count, candidateKey.count)
                let maxCompactLength = max(compactTarget.count, candidateCompact.count)
                guard maxLength > 0, maxCompactLength > 0 else { return nil }

                let ratio = Double(distance) / Double(maxLength)
                let compactRatio = Double(compactDistance) / Double(maxCompactLength)
                let effectiveRatio = min(ratio, compactRatio * 0.92)
                guard effectiveRatio <= 0.34 || compactRatio <= 0.28 else { return nil }

                return (entry.sourceTerm, entry.targetTerm, effectiveRatio)
            }
            .sorted {
                if $0.distance == $1.distance {
                    return $0.targetTerm.count < $1.targetTerm.count
                }
                return $0.distance < $1.distance
            }
            .first
    }
}
