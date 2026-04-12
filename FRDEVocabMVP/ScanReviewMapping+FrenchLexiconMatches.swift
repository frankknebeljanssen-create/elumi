import Foundation

extension ScanReviewMapper {
    static func bestFrenchLexiconMatch(
        forSource source: String
    ) -> (sourceTerm: String, suggestions: [String], distance: Double)? {
        let lookupKey = mapperNormalizedLookupText(source)
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

    static func bestTrimmedFrenchLexiconMatch(
        forSource source: String
    ) -> (sourceTerm: String, suggestions: [String], distance: Double)? {
        let tokens = mapperNormalizedWords(source)
        guard tokens.count >= 2 else { return nil }

        for prefixLength in stride(from: tokens.count - 1, through: 1, by: -1) {
            let candidate = tokens.prefix(prefixLength).joined(separator: " ")
            let trailing = tokens.dropFirst(prefixLength).joined(separator: " ")
            guard mapperTrailingLooksSuspicious(trailing) else { continue }
            guard let match = bestFrenchLexiconMatch(forSource: candidate) else { continue }
            if match.distance <= 0.2 {
                return match
            }
        }

        return nil
    }

    static func shouldForceFrenchLexiconReplacement(
        sourceText: String,
        targetText: String,
        sourceMatch: (sourceTerm: String, suggestions: [String], distance: Double)
    ) -> Bool {
        guard let firstSuggestion = sourceMatch.suggestions.first, !firstSuggestion.isEmpty else {
            return false
        }

        // Don't replace if punctuation mismatch (ça va ≠ Ça va?)
        if LexiconTextUtility.hasTerminalPunctuation(sourceMatch.sourceTerm)
            != LexiconTextUtility.hasTerminalPunctuation(sourceText) { return false }

        if targetMatchesSuggestions(targetText, suggestions: sourceMatch.suggestions) {
            return false
        }

        let sourceWordCount = max(1, mapperNormalizedWords(sourceMatch.sourceTerm).count)
        let targetWordCount = mapperNormalizedWords(targetText).count
        let suggestionWordCount = max(1, mapperNormalizedWords(firstSuggestion).count)

        if sourceMatch.distance <= 0.08 && sourceWordCount <= 2 {
            return true
        }

        if targetLooksSuspicious(
            targetText,
            canonicalSource: sourceMatch.sourceTerm,
            firstSuggestion: firstSuggestion
        ) {
            return true
        }

        if sourceWordCount == 1 && suggestionWordCount == 1 && targetWordCount >= 2 {
            return true
        }

        return false
    }

    static func bestReverseFrenchLexiconMatch(
        forGermanTarget target: String,
        cardType: CardType
    ) -> (sourceTerm: String, targetTerm: String, distance: Double)? {
        let lookupKey = mapperNormalizedLookupText(target)
        let compactTarget = mapperCompactLookupKey(target)
        guard !lookupKey.isEmpty else { return nil }

        let frenchEntries = DataStore.internalLexiconEntries.filter {
            $0.sourceLanguage == .french && $0.cardType == cardType
        }

        if let exact = frenchEntries.first(where: {
            mapperNormalizedLookupText($0.targetTerm) == lookupKey ||
            mapperCompactLookupKey($0.targetTerm) == compactTarget
        }) {
            return (exact.sourceTerm, exact.targetTerm, 0)
        }

        return frenchEntries
            .compactMap { lexiconEntry -> (sourceTerm: String, targetTerm: String, distance: Double)? in
                let candidateKey = mapperNormalizedLookupText(lexiconEntry.targetTerm)
                let candidateCompact = mapperCompactLookupKey(lexiconEntry.targetTerm)
                guard !candidateKey.isEmpty, !candidateCompact.isEmpty else { return nil }

                let sharesPrefix =
                    candidateKey.hasPrefix(String(lookupKey.prefix(2))) ||
                    lookupKey.hasPrefix(String(candidateKey.prefix(2))) ||
                    candidateCompact.hasPrefix(String(compactTarget.prefix(3))) ||
                    compactTarget.hasPrefix(String(candidateCompact.prefix(3)))

                guard sharesPrefix else { return nil }

                let distance = mapperLevenshtein(lookupKey, candidateKey)
                let compactDistance = mapperLevenshtein(compactTarget, candidateCompact)
                let maxLength = max(lookupKey.count, candidateKey.count)
                let maxCompactLength = max(compactTarget.count, candidateCompact.count)
                guard maxLength > 0, maxCompactLength > 0 else { return nil }

                let ratio = Double(distance) / Double(maxLength)
                let compactRatio = Double(compactDistance) / Double(maxCompactLength)
                let effectiveRatio = min(ratio, compactRatio * 0.92)
                guard effectiveRatio <= 0.34 || compactRatio <= 0.28 else { return nil }

                return (lexiconEntry.sourceTerm, lexiconEntry.targetTerm, effectiveRatio)
            }
            .sorted {
                if $0.distance == $1.distance {
                    return $0.targetTerm.count < $1.targetTerm.count
                }
                return $0.distance < $1.distance
            }
            .first
    }

    static func shouldForceReverseFrenchLexiconReplacement(
        sourceText: String,
        targetText: String,
        reverseMatch: (sourceTerm: String, targetTerm: String, distance: Double)
    ) -> Bool {
        if reverseMatch.distance > 0.26 {
            return false
        }

        // Short German targets (≤5 chars) are too prone to false fuzzy matches (Gelb↔Geld, Rot↔Rat)
        // Require exact reverse match for short words
        let targetLength = mapperNormalizedLookupText(targetText).count
        if targetLength <= 5 && reverseMatch.distance > 0.05 {
            return false
        }

        if targetMatchesSuggestions(targetText, suggestions: [reverseMatch.targetTerm]) {
            return false
        }

        let sourceMatch = bestFrenchLexiconMatch(forSource: sourceText)
        let sourceLooksWeak = sourceMatch == nil || sourceMatch?.distance ?? 1 > 0.22
        return sourceLooksWeak || targetLooksSuspicious(
            targetText,
            canonicalSource: reverseMatch.sourceTerm,
            firstSuggestion: reverseMatch.targetTerm
        )
    }
}
