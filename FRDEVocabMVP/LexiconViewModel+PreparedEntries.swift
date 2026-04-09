import Foundation

extension LexiconViewModel {
    func rebuildPreparedEntries(
        from entries: [LexiconEntry],
        query: String,
        selectedDirection: Direction
    ) async {
        let normalizedQuery = normalizedLookupText(query)
        let compactQuery = compactLookupKey(query)

        preparedEntries = await Task.detached(priority: .userInitiated) {
            guard !normalizedQuery.isEmpty else { return [] }

            struct AggregationCandidate {
                let entry: LexiconEntry
                let displayCardType: CardType
                let displayCountryCode: String
                let sourceText: String
                let targetText: String
                let sourceSearchKey: String
                let targetSearchKey: String
                let matchRank: Int
            }

            let candidates: [AggregationCandidate] = entries.flatMap { entry in
                let displayCardType = resolvedLexiconCardType(for: entry)
                let frenchText = sourceDisplayText(entry.sourceTerm, sourceLanguage: .french)
                // targetTerm is already correctly cased based on isGermanNoun
                let germanText = entry.targetTerm
                let frenchLookupKey = normalizedLookupText(frenchText)
                let germanLookupKey = normalizedLookupText(germanText)
                let frenchCompactKey = compactLookupKey(frenchText)
                let germanCompactKey = compactLookupKey(germanText)
                var result: [AggregationCandidate] = []

                if Self.isSearchMatch(
                    lookupKey: frenchLookupKey,
                    compactKey: frenchCompactKey,
                    query: normalizedQuery,
                    compactQuery: compactQuery
                ) {
                    result.append(
                        AggregationCandidate(
                            entry: entry,
                            displayCardType: displayCardType,
                            displayCountryCode: "FR",
                            sourceText: selectedDirection == .germanToFrench && !entry.targetTerm.isEmpty
                                ? entry.targetTerm
                                : frenchText,
                            targetText: selectedDirection == .germanToFrench
                                ? frenchText
                                : (germanText.isEmpty ? "Im internen Wörterbuch gespeichert" : germanText),
                            sourceSearchKey: selectedDirection == .germanToFrench ? germanLookupKey : frenchLookupKey,
                            targetSearchKey: selectedDirection == .germanToFrench ? frenchLookupKey : germanLookupKey,
                            matchRank: Self.searchMatchRank(
                                lookupKey: frenchLookupKey,
                                compactKey: frenchCompactKey,
                                query: normalizedQuery,
                                compactQuery: compactQuery
                            )
                        )
                    )
                }

                if !germanText.isEmpty,
                   Self.isSearchMatch(
                    lookupKey: germanLookupKey,
                    compactKey: germanCompactKey,
                    query: normalizedQuery,
                    compactQuery: compactQuery
                   ) {
                    result.append(
                        AggregationCandidate(
                            entry: entry,
                            displayCardType: displayCardType,
                            displayCountryCode: "DE",
                            sourceText: germanText,
                            targetText: frenchText,
                            sourceSearchKey: germanLookupKey,
                            targetSearchKey: frenchLookupKey,
                            matchRank: Self.searchMatchRank(
                                lookupKey: germanLookupKey,
                                compactKey: germanCompactKey,
                                query: normalizedQuery,
                                compactQuery: compactQuery
                            )
                        )
                    )
                }

                return result.filter {
                    selectedDirection == .germanToFrench ? $0.displayCountryCode == "DE" : true
                }
            }

            let grouped = Dictionary(grouping: candidates) { candidate in
                // Group by source + country + word class to separate noun/adjective entries
                let nounSuffix = candidate.entry.isGermanNoun ? "|n" : "|a"
                return "\(candidate.displayCountryCode)|\(candidate.sourceSearchKey)\(nounSuffix)"
            }

            return grouped.values.compactMap { group in
                let sortedGroup = group.sorted {
                    if $0.matchRank == $1.matchRank {
                        if $0.sourceText.count == $1.sourceText.count {
                            if $0.targetSearchKey == $1.targetSearchKey {
                                return $0.targetText < $1.targetText
                            }
                            return $0.targetSearchKey < $1.targetSearchKey
                        }
                        return $0.sourceText.count < $1.sourceText.count
                    }
                    return $0.matchRank < $1.matchRank
                }
                guard let first = sortedGroup.first else { return nil }

                var targetVariants: [String] = []
                var seenTargetKeys = Set<String>()

                for candidate in sortedGroup {
                    guard seenTargetKeys.insert(candidate.targetSearchKey).inserted else { continue }
                    targetVariants.append(candidate.targetText)
                }

                if targetVariants.count > 1 {
                    targetVariants.removeAll { $0 == "Im internen Wörterbuch gespeichert" }
                }

                guard !targetVariants.isEmpty else { return nil }

                let groupDisplayCardType: CardType = sortedGroup.contains(where: { $0.displayCardType == .phrases }) ? .phrases : .words
                let frenchGender = sortedGroup
                    .compactMap(\.entry.frenchGender)
                    .reduce(nil, preferredLexiconGenderInfo)

                let germanGender = sortedGroup
                    .compactMap(\.entry.germanGender)
                    .reduce(nil, preferredLexiconGenderInfo)

                let targetSummary = targetVariants.joined(separator: " / ")
                let targetSearchKey = targetVariants
                    .map(normalizedLookupText(_:))
                    .joined(separator: " ")

                return PreparedLexiconEntry(
                    id: "\(first.displayCountryCode)|\(groupDisplayCardType.rawValue)|\(first.sourceSearchKey)",
                    entries: sortedGroup.map(\.entry),
                    displayCardType: groupDisplayCardType,
                    displayCountryCode: first.displayCountryCode,
                    frenchGender: frenchGender,
                    germanGender: germanGender,
                    sourceText: first.sourceText,
                    targetText: targetSummary,
                    targetVariants: targetVariants,
                    sourceSearchKey: first.sourceSearchKey,
                    targetSearchKey: targetSearchKey
                )
            }
            .sorted {
                if $0.sourceSearchKey == $1.sourceSearchKey {
                    if $0.displayCountryCode == $1.displayCountryCode {
                        if $0.targetSearchKey == $1.targetSearchKey {
                            return $0.sourceText < $1.sourceText
                        }
                        return $0.targetSearchKey < $1.targetSearchKey
                    }
                    return $0.displayCountryCode < $1.displayCountryCode
                }
                return $0.sourceSearchKey < $1.sourceSearchKey
            }
        }.value
    }

    nonisolated static func isSearchMatch(
        lookupKey: String,
        compactKey: String,
        query: String,
        compactQuery: String
    ) -> Bool {
        guard !query.isEmpty else { return false }
        return lookupKey.hasPrefix(query) || (!compactQuery.isEmpty && compactKey.hasPrefix(compactQuery))
    }

    nonisolated static func searchMatchRank(
        lookupKey: String,
        compactKey: String,
        query: String,
        compactQuery: String
    ) -> Int {
        if lookupKey == query || (!compactQuery.isEmpty && compactKey == compactQuery) {
            return 0
        }
        if lookupKey.hasPrefix(query) {
            return 1
        }
        if !compactQuery.isEmpty && compactKey.hasPrefix(compactQuery) {
            return 2
        }
        return 3
    }
}
