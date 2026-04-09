import Foundation

extension DataStoreLexiconSupport {
    static func curatedLexiconEntries(with customItems: [VocabularyItem]) -> [LexiconEntry] {
        guard !customItems.isEmpty else {
            return curatedInternalLexiconEntries
        }

        let cacheKey = curatedLexiconEntriesCacheKey(for: customItems)
        curatedLexiconEntriesCacheLock.lock()
        if let cached = curatedLexiconEntriesCache[cacheKey] {
            curatedLexiconEntriesCacheLock.unlock()
            return cached
        }
        curatedLexiconEntriesCacheLock.unlock()

        let curatedEntries = SupplementalFreeDictLexicon.enrichMissingGenderInfo(in: mergeLexiconEntries(
            internalLexiconEntries + customLexiconEntries(from: customItems)
        )).sorted {
            if $0.sourceSortKey == $1.sourceSortKey {
                return $0.targetSortKey < $1.targetSortKey
            }
            return $0.sourceSortKey < $1.sourceSortKey
        }

        curatedLexiconEntriesCacheLock.lock()
        if curatedLexiconEntriesCache.count > 5 {
            curatedLexiconEntriesCache.removeAll(keepingCapacity: true)
        }
        curatedLexiconEntriesCache[cacheKey] = curatedEntries
        curatedLexiconEntriesCacheLock.unlock()

        return curatedEntries
    }

    static let curatedInternalLexiconEntries: [LexiconEntry] = {
        let totalStart = CFAbsoluteTimeGetCurrent()
        var start = CFAbsoluteTimeGetCurrent()
        let internal_ = internalLexiconEntries
        print("⏱ [CuratedLexicon] internalLexiconEntries: \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms (\(internal_.count) entries)")

        start = CFAbsoluteTimeGetCurrent()
        let merged = mergeLexiconEntries(internal_)
        print("⏱ [CuratedLexicon] mergeLexiconEntries: \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms (\(merged.count) entries)")

        start = CFAbsoluteTimeGetCurrent()
        let enriched = SupplementalFreeDictLexicon.enrichMissingGenderInfo(in: merged)
        print("⏱ [CuratedLexicon] enrichMissingGenderInfo: \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms")

        start = CFAbsoluteTimeGetCurrent()
        let sorted = enriched.sorted {
            if $0.sourceSortKey == $1.sourceSortKey {
                return $0.targetSortKey < $1.targetSortKey
            }
            return $0.sourceSortKey < $1.sourceSortKey
        }
        print("⏱ [CuratedLexicon] sort: \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms")
        print("⏱ [CuratedLexicon] TOTAL: \(Int(((CFAbsoluteTimeGetCurrent() - totalStart) * 1000).rounded()))ms")
        return sorted
    }()

    static func makeInternalLexiconEntries() -> [LexiconEntry] {
        var entries: [LexiconEntry] = []
        var seen: Set<String> = []

        func appendEntry(
            sourceTerm: String,
            targetTerm: String,
            sourceLanguage: StudyLanguage,
            cardType: CardType,
            explicitFrenchGender: LexiconNounGender? = nil,
            explicitGermanGender: LexiconNounGender? = nil,
            explicitFrenchArticle: String? = nil,
            explicitGermanArticle: String? = nil,
            isGermanNoun: Bool? = nil
        ) {
            let cleanedSource = sourceDisplayText(sourceTerm, sourceLanguage: sourceLanguage)
            let nounFlag = isGermanNoun ?? (explicitGermanGender != nil || explicitGermanArticle != nil || startsWithGermanArticle(targetTerm))
            let cleanedTarget: String
            if nounFlag {
                cleanedTarget = germanDisplayText(targetTerm, cardType: cardType, sourceHint: nil)
            } else {
                cleanedTarget = targetTerm.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard !cleanedSource.isEmpty else { return }

            let key = [
                sourceLanguage.rawValue,
                cardType.rawValue,
                normalizedLookupText(cleanedSource),
                normalizedLookupText(cleanedTarget)
            ].joined(separator: "|")

            guard seen.insert(key).inserted else { return }
            entries.append(
                LexiconEntry(
                    id: key,
                    sourceTerm: cleanedSource,
                    targetTerm: cleanedTarget,
                    sourceLanguage: sourceLanguage,
                    cardType: cardType,
                    frenchGender: sourceLanguage == .french
                        ? preferredLexiconGenderInfo(
                            exactFrenchGenderInfo(
                                gender: explicitFrenchGender,
                                article: explicitFrenchArticle
                            ),
                            frenchGenderInfo(for: cleanedSource, cardType: cardType)
                        )
                        : nil,
                    germanGender: preferredLexiconGenderInfo(
                        exactGermanGenderInfo(
                            gender: explicitGermanGender,
                            article: explicitGermanArticle
                        ),
                        germanGenderInfo(for: cleanedTarget, cardType: cardType)
                    ),
                    isGermanNoun: nounFlag
                )
            )
        }

        for item in OfflineFrenchGermanKnowledgePool.translatedRecords {
            appendEntry(
                sourceTerm: item.sourceTerm,
                targetTerm: item.targetTerm,
                sourceLanguage: .french,
                cardType: item.cardType,
                explicitFrenchGender: item.sourceGender,
                explicitGermanGender: item.targetGender,
                explicitFrenchArticle: item.sourceArticle,
                explicitGermanArticle: item.targetLeadingArticle,
                isGermanNoun: item.isGermanNoun
            )
        }

        return entries.sorted {
            if $0.sourceSortKey == $1.sourceSortKey {
                return $0.targetSortKey < $1.targetSortKey
            }
            return $0.sourceSortKey < $1.sourceSortKey
        }
    }

    static func customLexiconEntries(from customItems: [VocabularyItem]) -> [LexiconEntry] {
        var customEntries: [LexiconEntry] = []
        var seen = Set<String>()

        for item in customItems {
            let sourceTerm = cleanedQuizDisplayText(item.french)
            let targetTerm = germanDisplayText(item.german, cardType: item.cardType, sourceHint: item.french)
            guard !sourceTerm.isEmpty, !targetTerm.isEmpty else { continue }

            let key = [
                item.sourceLanguage.rawValue,
                item.cardType.rawValue,
                normalizedLookupText(sourceTerm),
                normalizedLookupText(targetTerm)
            ].joined(separator: "|")

            guard seen.insert(key).inserted else { continue }

            customEntries.append(
                LexiconEntry(
                    id: key,
                    sourceTerm: sourceTerm,
                    targetTerm: targetTerm,
                    sourceLanguage: item.sourceLanguage,
                    cardType: item.cardType,
                    frenchGender: item.sourceLanguage == .french ? frenchGenderInfo(for: sourceTerm, cardType: item.cardType) : nil,
                    germanGender: germanGenderInfo(for: targetTerm, cardType: item.cardType),
                    isGermanNoun: startsWithGermanArticle(targetTerm) || germanGenderInfo(for: targetTerm, cardType: item.cardType) != nil
                )
            )
        }

        return customEntries
    }
}
