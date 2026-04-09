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
            if $0.sourceSortKey == $1.sourceSortKey {
                return $0.targetSortKey < $1.targetSortKey
            }
            return $0.sourceSortKey < $1.sourceSortKey
        }
    }

    static func previewLexiconEntries(with customItems: [VocabularyItem], supplementLimit: Int = 2400) -> [LexiconEntry] {
        mergeLexiconEntries(
            curatedLexiconEntries(with: customItems)
            + SupplementalFreeDictLexicon.previewLexiconEntries(limit: supplementLimit)
        ).sorted {
            if $0.sourceSortKey == $1.sourceSortKey {
                return $0.targetSortKey < $1.targetSortKey
            }
            return $0.sourceSortKey < $1.sourceSortKey
        }
    }

    static func searchLexiconEntries(
        query: String,
        curatedEntries: [LexiconEntry],
        supplementLimit: Int = 80
    ) -> [LexiconEntry] {
        let totalStart = CFAbsoluteTimeGetCurrent()
        let normalizedQuery = normalizedLookupText(query)
        let compactQuery = compactLookupKey(query)
        guard !normalizedQuery.isEmpty else { return [] }

        var start = CFAbsoluteTimeGetCurrent()
        let curatedMatches = curatedEntries.filter { entry in
            if entry.sourceSortKey.hasPrefix(normalizedQuery) || entry.targetSortKey.hasPrefix(normalizedQuery) {
                return true
            }
            if strippingLeadingFrenchArticle(from: entry.sourceSortKey).hasPrefix(normalizedQuery) ||
               strippingLeadingGermanArticle(from: entry.targetSortKey).hasPrefix(normalizedQuery) {
                return true
            }
            if !compactQuery.isEmpty,
               entry.sourceSortKey.replacingOccurrences(of: " ", with: "").hasPrefix(compactQuery) ||
               entry.targetSortKey.replacingOccurrences(of: " ", with: "").hasPrefix(compactQuery) {
                return true
            }
            return false
        }
        print("⏱ [Search] curatedFilter (\(curatedEntries.count)→\(curatedMatches.count)): \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms")

        start = CFAbsoluteTimeGetCurrent()
        let supplementResults = SupplementalFreeDictLexicon.searchLexiconEntries(matching: normalizedQuery, limit: supplementLimit)
        print("⏱ [Search] SQLite supplement (\(supplementResults.count)): \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms")

        start = CFAbsoluteTimeGetCurrent()
        let merged = SupplementalFreeDictLexicon.enrichMissingGenderInfo(in: mergeLexiconEntries(
            curatedMatches + supplementResults
        )).sorted {
            if $0.sourceSortKey == $1.sourceSortKey {
                return $0.targetSortKey < $1.targetSortKey
            }
            return $0.sourceSortKey < $1.sourceSortKey
        }
        print("⏱ [Search] merge+enrich+sort (\(merged.count)): \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms")
        print("⏱ [Search] TOTAL: \(Int(((CFAbsoluteTimeGetCurrent() - totalStart) * 1000).rounded()))ms")

        return merged
    }

}
