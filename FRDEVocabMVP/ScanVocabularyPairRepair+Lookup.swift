import Foundation

extension ScanVocabularyPairRepair {
    func bestLocalTranslationMatch(
        for source: String,
        sourceLanguage: StudyLanguage
    ) -> (sourceTerm: String, suggestions: [String], matchDistance: Double)? {
        let lookupKey = dependencies.normalizedLookupText(source)
        guard !lookupKey.isEmpty else { return nil }

        if let direct = DataStore.localTranslationLookup[sourceLanguage]?[lookupKey], !direct.isEmpty {
            return (
                canonicalSourceTerm(for: lookupKey, sourceLanguage: sourceLanguage) ?? source,
                direct,
                0
            )
        }

        guard let approximate = approximateTranslationSuggestions(for: lookupKey, sourceLanguage: sourceLanguage) else {
            return nil
        }

        return (
            canonicalSourceTerm(for: approximate.lookupKey, sourceLanguage: sourceLanguage) ?? source,
            approximate.suggestions,
            approximate.distance
        )
    }

    func normalizedSourceTermForCorrection(
        _ source: String,
        sourceLanguage: StudyLanguage
    ) -> String {
        guard sourceLanguage == .english else { return source }
        return dependencies.normalizedEnglishVerbMarker(source)
    }

    func canonicalizedSourceTermIfNeeded(
        _ source: String,
        sourceLanguage: StudyLanguage
    ) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        if let directMatch = bestLocalTranslationMatch(for: trimmed, sourceLanguage: sourceLanguage),
           directMatch.matchDistance <= 0.18 {
            if shouldPreserveScannedSourceText(
                trimmed,
                insteadOf: directMatch.sourceTerm,
                sourceLanguage: sourceLanguage
            ) {
                return trimmed
            }
            return directMatch.sourceTerm
        }

        let tokens = dependencies.normalizedWords(trimmed)
        guard tokens.count >= 2 else { return trimmed }

        for prefixLength in stride(from: tokens.count - 1, through: 1, by: -1) {
            let candidate = tokens.prefix(prefixLength).joined(separator: " ")
            let trailing = tokens.dropFirst(prefixLength).joined(separator: " ")
            guard !candidate.isEmpty, !trailing.isEmpty else { continue }
            guard let suggestions = DataStore.localTranslationLookup[sourceLanguage]?[candidate], !suggestions.isEmpty else {
                continue
            }

            let trailingGermanCoverage = dependencies.germanDictionaryCoverageScore(trailing)
            let trailingSourceCoverage = dependencies.sourceLexiconCoverageScore(trailing, sourceLanguage)
            let trailingTokens = dependencies.normalizedWords(trailing)
            let trailingLooksSuspicious =
                trailingGermanCoverage > trailingSourceCoverage + 0.12 ||
                isLikelyMarkerNoise(trailing) ||
                looksLikeLowQualitySourceTail(trailing) ||
                (!trailingTokens.isEmpty && trailingTokens.allSatisfy {
                    isLikelyMarkerNoise($0) || $0.count <= 2
                })

            if trailingLooksSuspicious {
                let canonicalCandidate = canonicalSourceTerm(for: candidate, sourceLanguage: sourceLanguage) ?? trimmed
                if shouldPreserveScannedSourceText(
                    trimmed,
                    insteadOf: canonicalCandidate,
                    sourceLanguage: sourceLanguage
                ) {
                    return trimmed
                }
                return canonicalCandidate
            }
        }

        return trimmed
    }

    func localTranslationAgreementScore(
        source: String,
        target: String,
        sourceLanguage: StudyLanguage
    ) -> Double {
        guard let localMatch = bestLocalTranslationMatch(for: source, sourceLanguage: sourceLanguage) else {
            return 0
        }

        let normalizedTarget = dependencies.normalizedLookupText(target)
        guard !normalizedTarget.isEmpty else { return 0 }

        let suggestions = localMatch.suggestions.map(dependencies.normalizedLookupText)
        if suggestions.contains(normalizedTarget) {
            return 1.45
        }

        if suggestions.contains(where: { normalizedTarget.contains($0) || $0.contains(normalizedTarget) }) {
            return 0.78
        }

        return 0
    }

    private func approximateTranslationSuggestions(
        for lookupKey: String,
        sourceLanguage: StudyLanguage
    ) -> (lookupKey: String, suggestions: [String], distance: Double)? {
        DataStore.cachedApproximateTranslationSuggestions(
            for: lookupKey,
            sourceLanguage: sourceLanguage
        )
    }

    private func canonicalSourceTerm(
        for lookupKey: String,
        sourceLanguage: StudyLanguage
    ) -> String? {
        DataStore.cachedCanonicalSourceTerm(
            for: lookupKey,
            sourceLanguage: sourceLanguage
        )
    }
}
