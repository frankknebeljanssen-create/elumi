import Foundation

enum DataStoreLexiconSupport {
    static let internalLexiconEntries: [LexiconEntry] = makeInternalLexiconEntries()

    static func prewarmCuratedLexiconEntries() {
        _ = curatedInternalLexiconEntries.count
    }

    static func mergedLexiconEntries(with customItems: [VocabularyItem]) -> [LexiconEntry] {
        mergeLexiconEntries(
            curatedLexiconEntries(with: customItems)
            + SupplementalFreeDictLexicon.lexiconEntries()
        ).sorted {
            let lhs = $0.sourceTerm.folding(options: String.CompareOptions.diacriticInsensitive, locale: Locale.current).lowercased()
            let rhs = $1.sourceTerm.folding(options: String.CompareOptions.diacriticInsensitive, locale: Locale.current).lowercased()
            if lhs == rhs {
                return $0.targetTerm.lowercased() < $1.targetTerm.lowercased()
            }
            return lhs < rhs
        }
    }

    static func previewLexiconEntries(with customItems: [VocabularyItem], supplementLimit: Int = 2400) -> [LexiconEntry] {
        mergeLexiconEntries(
            curatedLexiconEntries(with: customItems)
            + SupplementalFreeDictLexicon.previewLexiconEntries(limit: supplementLimit)
        ).sorted {
            let lhs = $0.sourceTerm.folding(options: String.CompareOptions.diacriticInsensitive, locale: Locale.current).lowercased()
            let rhs = $1.sourceTerm.folding(options: String.CompareOptions.diacriticInsensitive, locale: Locale.current).lowercased()
            if lhs == rhs {
                return $0.targetTerm.lowercased() < $1.targetTerm.lowercased()
            }
            return lhs < rhs
        }
    }

    static func searchLexiconEntries(
        query: String,
        curatedEntries: [LexiconEntry],
        supplementLimit: Int = 80
    ) -> [LexiconEntry] {
        let normalizedQuery = normalizedLookupText(query)
        let compactQuery = compactLookupKey(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let curatedMatches = curatedEntries.filter { entry in
            let sourceLookupKey = normalizedLookupText(entry.sourceTerm)
            let sourceCompactKey = compactLookupKey(entry.sourceTerm)
            let targetLookupKey = normalizedLookupText(entry.targetTerm)
            let targetCompactKey = compactLookupKey(entry.targetTerm)

            return sourceLookupKey.hasPrefix(normalizedQuery) ||
                targetLookupKey.hasPrefix(normalizedQuery) ||
                (!compactQuery.isEmpty && (
                    sourceCompactKey.hasPrefix(compactQuery) ||
                    targetCompactKey.hasPrefix(compactQuery)
                ))
        }

        return SupplementalFreeDictLexicon.enrichMissingGenderInfo(in: mergeLexiconEntries(
            curatedMatches + SupplementalFreeDictLexicon.searchLexiconEntries(matching: normalizedQuery, limit: supplementLimit)
        )).sorted {
            let lhs = $0.sourceTerm.folding(options: String.CompareOptions.diacriticInsensitive, locale: Locale.current).lowercased()
            let rhs = $1.sourceTerm.folding(options: String.CompareOptions.diacriticInsensitive, locale: Locale.current).lowercased()
            if lhs == rhs {
                return $0.targetTerm.lowercased() < $1.targetTerm.lowercased()
            }
            return lhs < rhs
        }
    }

}
