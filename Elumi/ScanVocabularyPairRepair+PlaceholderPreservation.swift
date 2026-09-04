import Foundation

extension ScanVocabularyPairRepair {
    func shouldPreserveScannedSourceText(
        _ original: String,
        insteadOf canonical: String,
        sourceLanguage: StudyLanguage
    ) -> Bool {
        let normalizedOriginal = normalizedLookupWords(original)
        let normalizedCanonical = normalizedLookupWords(canonical)

        guard !normalizedOriginal.isEmpty, !normalizedCanonical.isEmpty else { return false }
        guard normalizedOriginal != normalizedCanonical else { return false }

        let placeholderTokens = sourcePlaceholderTokens(for: sourceLanguage)
        let sharedPrefixCount = zip(normalizedOriginal, normalizedCanonical)
            .prefix(while: { $0 == $1 })
            .count
        let trailingOriginal = Array(normalizedOriginal.dropFirst(sharedPrefixCount))
        let trailingCanonical = Array(normalizedCanonical.dropFirst(sharedPrefixCount))
        let compactOriginal = normalizedOriginal.joined()
        let compactCanonical = normalizedCanonical.joined()

        if !compactOriginal.isEmpty,
           compactOriginal == compactCanonical,
           normalizedOriginal != normalizedCanonical {
            return false
        }

        if isLikelyOCRCorruptedWordToken(original) {
            return false
        }

        if containsSourcePlaceholderTemplate(original, sourceLanguage: sourceLanguage),
           normalizedCanonical.contains(where: { isLikelyConcreteScanFillToken($0, sourceLanguage: sourceLanguage) }) {
            return true
        }

        if normalizedCanonical.contains(where: placeholderTokens.contains),
           normalizedOriginal.contains(where: { isLikelyConcreteScanFillToken($0, sourceLanguage: sourceLanguage) }) {
            return true
        }

        if !trailingOriginal.isEmpty,
           trailingOriginal.contains(where: { isLikelyConcreteScanFillToken($0, sourceLanguage: sourceLanguage) }) {
            if trailingCanonical.isEmpty {
                return true
            }

            if trailingCanonical.allSatisfy({
                placeholderTokens.contains($0) ||
                dependencies.scanStopWords(sourceLanguage).contains($0)
            }) {
                return true
            }
        }

        return false
    }

    func shouldPreserveScannedGermanTargetText(
        _ original: String,
        insteadOf canonical: String
    ) -> Bool {
        let normalizedOriginal = normalizedLookupWords(original)
        let normalizedCanonical = normalizedLookupWords(canonical)

        guard !normalizedOriginal.isEmpty, !normalizedCanonical.isEmpty else { return false }
        guard normalizedOriginal != normalizedCanonical else { return false }

        let sharedPrefixCount = zip(normalizedOriginal, normalizedCanonical)
            .prefix(while: { $0 == $1 })
            .count
        let trailingOriginal = Array(normalizedOriginal.dropFirst(sharedPrefixCount))
        let trailingCanonical = Array(normalizedCanonical.dropFirst(sharedPrefixCount))
        let compactOriginal = normalizedOriginal.joined()
        let compactCanonical = normalizedCanonical.joined()

        if !compactOriginal.isEmpty,
           compactOriginal == compactCanonical,
           normalizedOriginal != normalizedCanonical {
            return false
        }

        if isLikelyOCRCorruptedWordToken(original) {
            return false
        }

        let originalGermanCoverage = dependencies.germanDictionaryCoverageScore(original)
        let canonicalGermanCoverage = dependencies.germanDictionaryCoverageScore(canonical)
        if canonicalGermanCoverage > originalGermanCoverage + 0.18 &&
            !containsGermanPlaceholderTemplate(original) {
            return false
        }

        if containsGermanPlaceholderTemplate(original),
           normalizedCanonical.contains(where: isLikelyConcreteGermanFillToken(_:)) {
            return true
        }

        if normalizedCanonical.contains(where: germanPlaceholderTokens.contains),
           normalizedOriginal.contains(where: isLikelyConcreteGermanFillToken(_:)) {
            return true
        }

        if !trailingOriginal.isEmpty,
           trailingOriginal.contains(where: isLikelyConcreteGermanFillToken(_:)) {
            if trailingCanonical.isEmpty {
                return true
            }

            if trailingCanonical.allSatisfy({
                germanPlaceholderTokens.contains($0) ||
                germanPlaceholderStopWords.contains($0)
            }) {
                return true
            }
        }

        return false
    }

    func sourcePlaceholderTokens(for language: StudyLanguage) -> Set<String> {
        switch language {
        case .french:
            return ["name", "nom", "prenom", "prénom", "qqn", "quelquun", "personne"]
        case .english:
            return ["name", "someone", "somebody", "something"]
        }
    }

    var germanPlaceholderTokens: Set<String> {
        ["name", "vorname", "jemand", "person", "etwas"]
    }

    var germanPlaceholderStopWords: Set<String> {
        ["ich", "du", "er", "sie", "wir", "ihr", "und", "oder", "der", "die", "das", "ein", "eine", "mein", "dein"]
    }

    func isLikelyConcreteScanFillToken(_ token: String, sourceLanguage: StudyLanguage) -> Bool {
        let normalized = dependencies.normalizedLookupText(token)
        guard !normalized.isEmpty else { return false }
        guard !sourcePlaceholderTokens(for: sourceLanguage).contains(normalized) else { return false }
        guard !looksLikePlaceholderOCRVariant(normalized, candidates: sourcePlaceholderTokens(for: sourceLanguage)) else { return false }
        guard !dependencies.scanStopWords(sourceLanguage).contains(normalized) else { return false }
        guard !isLikelyMarkerNoise(normalized) else { return false }
        guard !isLikelyOCRCorruptedWordToken(normalized) else { return false }
        guard normalized.count >= 3 else { return false }
        return normalized.range(of: #"[a-zàâçéèêëîïôùûüÿœæ]"#, options: .regularExpression) != nil
    }

    func containsSourcePlaceholderTemplate(
        _ text: String,
        sourceLanguage: StudyLanguage
    ) -> Bool {
        let tokens = normalizedLookupWords(text)
        guard let last = tokens.last else { return false }
        guard sourcePlaceholderTokens(for: sourceLanguage).contains(last) else { return false }

        switch sourceLanguage {
        case .french:
            return tokens.contains(where: { $0.hasPrefix("appel") })
        case .english:
            return false
        }
    }

    func isLikelyConcreteGermanFillToken(_ token: String) -> Bool {
        let normalized = dependencies.normalizedLookupText(token)
        guard !normalized.isEmpty else { return false }
        guard !germanPlaceholderTokens.contains(normalized) else { return false }
        guard !looksLikePlaceholderOCRVariant(normalized, candidates: germanPlaceholderTokens) else { return false }
        guard !germanPlaceholderStopWords.contains(normalized) else { return false }
        guard !isLikelyMarkerNoise(normalized) else { return false }
        guard !isLikelyOCRCorruptedWordToken(normalized) else { return false }
        guard normalized.count >= 3 else { return false }
        return normalized.range(of: #"[a-zäöüß]"#, options: .regularExpression) != nil
    }

    func containsGermanPlaceholderTemplate(_ text: String) -> Bool {
        let tokens = normalizedLookupWords(text)
        guard let last = tokens.last else { return false }
        guard germanPlaceholderTokens.contains(last) else { return false }

        return tokens.contains(where: {
            $0.hasPrefix("heiss") || $0.hasPrefix("heis") || $0.hasPrefix("heiß")
        })
    }

    func hasPlaceholderLikeToken(in text: String, candidates: Set<String>) -> Bool {
        let tokens = normalizedLookupWords(text)
        guard !tokens.isEmpty else { return false }

        return tokens.contains { token in
            candidates.contains(token) || looksLikePlaceholderOCRVariant(token, candidates: candidates)
        }
    }

    func looksLikePlaceholderOCRVariant(_ token: String, candidates: Set<String>) -> Bool {
        let normalizedToken = dependencies.normalizedLookupText(token)
        guard !normalizedToken.isEmpty else { return false }

        return candidates.contains { candidate in
            let normalizedCandidate = dependencies.normalizedLookupText(candidate)
            guard !normalizedCandidate.isEmpty else { return false }
            guard abs(normalizedToken.count - normalizedCandidate.count) <= 1 else { return false }

            let distance = scanLevenshtein(normalizedToken, normalizedCandidate)
            return distance <= 1
        }
    }
}
