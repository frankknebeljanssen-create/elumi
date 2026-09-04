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

                // Französisch display-ready: bei Einzelwort-Nomen Artikel hinzufügen,
                // wenn nicht schon vorhanden (l'auto, la voiture, le chien).
                let frenchGenderHint: String? = {
                    switch entry.frenchGender?.gender {
                    case .masculine: return "m"
                    case .feminine: return "f"
                    case .plural: return "pl"
                    default: return nil
                    }
                }()
                let frenchRawDisplay = sourceDisplayText(entry.sourceTerm, sourceLanguage: .french)
                let frenchIsNoun = entry.isGermanNoun || (entry.frenchGender != nil)
                // Nur bei Nomen-Einzelwort Artikel ergänzen, sonst restoreFrenchElisions etc.
                let frenchText: String
                if frenchIsNoun, displayCardType == .words {
                    frenchText = FrenchLemmaFormatter.displayFrenchRaw(
                        frenchRawDisplay,
                        isNoun: true,
                        gender: frenchGenderHint
                    )
                } else {
                    frenchText = frenchRawDisplay
                }

                // Deutsch display-ready: bei Nomen Großschreibung sicherstellen, Artikel ergänzen
                let germanRaw: String = {
                    if entry.isGermanNoun, !startsWithGermanArticle(entry.targetTerm),
                       let article = entry.germanGender?.article, !article.isEmpty {
                        return "\(article) \(entry.targetTerm)"
                    }
                    return entry.targetTerm
                }()
                let germanText = FrenchLemmaFormatter.displayGermanRaw(
                    germanRaw,
                    isNoun: entry.isGermanNoun
                )
                let frenchLookupKey = normalizedLookupText(frenchText)
                // Use raw targetTerm for lookup (without added article prefix)
                let germanLookupKey = normalizedLookupText(entry.targetTerm)
                let frenchCompactKey = compactLookupKey(frenchText)
                let germanCompactKey = compactLookupKey(germanText)
                var result: [AggregationCandidate] = []

                // Always display the matched side as source — regardless of global direction.
                // The UI filter (lexiconFilterMode) handles direction-based filtering.
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
                            sourceText: frenchText,
                            targetText: germanText.isEmpty ? "Im internen Wörterbuch gespeichert" : germanText,
                            sourceSearchKey: frenchLookupKey,
                            targetSearchKey: germanLookupKey,
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

                return result
            }

            let grouped = Dictionary(grouping: candidates) { candidate in
                let nounSuffix = candidate.entry.isGermanNoun ? "|n" : "|a"
                // DE-Kandidaten: alle Senses desselben DB-Eintrags zusammenfassen
                // (sonst entstehen Duplikate wie „Straße" + „Straße; Öffentlichkeit; …"
                // als separate Einträge, obwohl es dieselbe entry_id ist).
                if candidate.displayCountryCode == "DE", let id = candidate.entry.entryID {
                    return "DE|entryID:\(id)\(nounSuffix)"
                }
                return "\(candidate.displayCountryCode)|\(candidate.sourceSearchKey)\(nounSuffix)"
            }

            let sortedResults: [PreparedLexiconEntry] = grouped.values.compactMap { group in
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

                let isNounGroup = sortedGroup.first?.entry.isGermanNoun ?? false
                let wordClassSuffix = isNounGroup ? "|n" : "|a"
                let bestMatchRank = sortedGroup.map(\.matchRank).min() ?? 3
                return PreparedLexiconEntry(
                    id: "\(first.displayCountryCode)|\(groupDisplayCardType.rawValue)|\(first.sourceSearchKey)\(wordClassSuffix)",
                    entries: sortedGroup.map(\.entry),
                    displayCardType: groupDisplayCardType,
                    displayCountryCode: first.displayCountryCode,
                    frenchGender: isNounGroup ? frenchGender : nil,
                    germanGender: isNounGroup ? germanGender : nil,
                    sourceText: first.sourceText,
                    targetText: targetSummary,
                    targetVariants: targetVariants,
                    sourceSearchKey: first.sourceSearchKey,
                    targetSearchKey: targetSearchKey,
                    matchRank: bestMatchRank
                )
            }
            .sorted {
                // 1. Primär: Match-Rang (0 = exakter Treffer kommt zuerst).
                //    Damit steht „Straße → la rue" bei Suche „strasse" oben,
                //    NICHT die Compound-Wörter wie „Straßenbahn".
                if $0.matchRank != $1.matchRank {
                    return $0.matchRank < $1.matchRank
                }
                // 2. Innerhalb gleichen Rangs: kürzerer sourceText zuerst
                //    (Primärwort vor Komposita vor Phrasen).
                if $0.sourceText.count != $1.sourceText.count {
                    return $0.sourceText.count < $1.sourceText.count
                }
                // 3. Alphabetische Tiebreaker
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
            // Final-Dedup: pro DB-entry_id wird nur EIN PreparedLexiconEntry behalten.
            // Verhindert Duplikate, wenn ein Eintrag sowohl auf der FR- als auch
            // der DE-Seite die Query trifft („l'automne" + „der Herbst").
            // Behält den besseren Match-Rang (der wegen vorheriger Sortierung zuerst kommt).
            return Self.dedupePreparedByEntryID(sortedResults)
        }.value
    }

    /// Pro entry_id wird der PreparedLexiconEntry mit dem besseren matchRank behalten.
    /// Bei Gleichstand bleibt der erste in der Reihenfolge.
    nonisolated static func dedupePreparedByEntryID(
        _ entries: [PreparedLexiconEntry]
    ) -> [PreparedLexiconEntry] {
        var seenEntryIDs: Set<Int> = []
        var output: [PreparedLexiconEntry] = []
        for prep in entries {
            // Wenn keiner der enthaltenen LexiconEntries eine entryID hat → durchlassen
            let ids = prep.entries.compactMap(\.entryID)
            guard let primaryID = ids.first else {
                output.append(prep)
                continue
            }
            if seenEntryIDs.insert(primaryID).inserted {
                output.append(prep)
            }
        }
        return output
    }

    nonisolated static func isSearchMatch(
        lookupKey: String,
        compactKey: String,
        query: String,
        compactQuery: String
    ) -> Bool {
        guard !query.isEmpty else { return false }
        if lookupKey.hasPrefix(query) { return true }
        if !compactQuery.isEmpty && compactKey.hasPrefix(compactQuery) { return true }
        // Match after article: "der hase" contains " hase"
        if lookupKey.contains(" \(query)") { return true }
        // Match article-stripped
        let stripped = strippingLeadingGermanArticle(from: strippingLeadingFrenchArticle(from: lookupKey))
        if stripped != lookupKey && stripped.hasPrefix(query) { return true }
        return false
    }

    /// Zentrale Ranking-Funktion für Wörterbuch-Suchergebnisse.
    /// Niedrigere Zahl = relevanter (steht oben in der Liste).
    ///
    /// Stufen:
    ///   0  → Exakter Treffer auf Haupteintrag (Strasse == strasse)
    ///   10 → Exakter Treffer nach Artikel-Strip („die Strasse" → „strasse")
    ///   20 → Mehrwortig, beginnt mit Query als eigenständigem Wort
    ///        („die Strasse überqueren", „Auto fahren") — Query bleibt erkennbar
    ///   30 → Einzelwort-Compound mit Query als Präfix („Strassenbahn", „Autobahn")
    ///   40 → Mehrwortig, Query als Präfix mitten im Wort
    ///   50 → Query als ganzes Wort innerhalb der Phrase („an der Strasse wohnen")
    ///   60 → Compact-Match (Leerzeichen-frei, Fallback)
    ///   90 → Sonst (sehr unscharf)
    ///
    /// Damit erscheint bei Suche „Strasse" die Reihenfolge:
    ///   Strasse → die Strasse → die Strasse überqueren → Strassenbahn → an der Strasse wohnen
    nonisolated static func searchMatchRank(
        lookupKey: String,
        compactKey: String,
        query: String,
        compactQuery: String
    ) -> Int {
        guard !query.isEmpty else { return 999 }

        // Artikel-Strip einmalig (FR + DE)
        let stripped = strippingLeadingGermanArticle(from: strippingLeadingFrenchArticle(from: lookupKey))

        // 0: Exakt-Treffer auf den ganzen Eintrag
        if lookupKey == query { return 0 }
        if !compactQuery.isEmpty && compactKey == compactQuery { return 0 }

        // 10: Exakt nach Artikel-Strip („die Strasse" mit Query „strasse")
        if stripped != lookupKey && stripped == query { return 10 }

        // 20: Mehrwortig, das ERSTE Wort (nach Artikel-Strip oder direkt) ist die Query.
        //     Query bleibt als eigenes Wort sichtbar — viel näher am Haupteintrag als
        //     ein verschmolzenes Compound-Wort.
        let lookupTokens = lookupKey.split(separator: " ").map(String.init)
        let strippedTokens = stripped.split(separator: " ").map(String.init)
        if let first = strippedTokens.first, first == query, strippedTokens.count > 1 {
            return 20
        }
        if let first = lookupTokens.first, first == query, lookupTokens.count > 1 {
            return 20
        }

        // 25: Plural-/Flexions-Form derselben Grundform — „Strassen" für Query „Strasse",
        //     „les amis" für Query „ami", „Hasen" für Query „Hase".
        //     Rangiert klar VOR fremden Wörtern, die zufällig denselben Präfix haben
        //     (z.B. „amiable" bei Suche „ami").
        if strippedTokens.count == 1, let single = strippedTokens.first {
            // Häufige Plural- und Flexions-Endungen FR + DE
            let endings = ["s", "x", "es", "en", "n", "er", "e"]
            for ending in endings {
                if single.count > query.count + ending.count - 1,
                   single.hasSuffix(ending),
                   String(single.dropLast(ending.count)) == query {
                    return 25
                }
            }
        }

        // 30: Einzelwort-Compound, beginnt mit Query („Strassenbahn", „Autobahn")
        if lookupTokens.count == 1, lookupKey.hasPrefix(query) { return 30 }
        if strippedTokens.count == 1, stripped.hasPrefix(query) { return 30 }

        // 40: Mehrwortig, Eintrag startet mit Query (aber nicht als sauberes Wort)
        if lookupKey.hasPrefix(query) || stripped.hasPrefix(query) { return 40 }

        // 50: Query als ganzes Wort irgendwo in der Phrase
        if lookupKey.contains(" \(query) ") { return 50 }
        if lookupKey.contains(" \(query)") { return 50 }   // am Ende der Phrase

        // 60: Compact-Match (Leerzeichen ignoriert, schwächer)
        if !compactQuery.isEmpty, compactKey.hasPrefix(compactQuery) { return 60 }

        return 90
    }
}
