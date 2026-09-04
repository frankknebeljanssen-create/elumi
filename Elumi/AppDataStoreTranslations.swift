import Foundation

enum DataStoreTranslationSupport {
    static let localTranslationLookup: [StudyLanguage: [String: [String]]] = makeLocalTranslationLookup()

    private static let canonicalSourceLookup: [StudyLanguage: [String: String]] = makeCanonicalSourceLookup()
    private static let translationLookupEntries: [StudyLanguage: [TranslationLookupEntry]] = makeTranslationLookupEntries()
    private static let translationLookupCacheLock = NSLock()
    private static var approximateTranslationCache: [StudyLanguage: [String: (lookupKey: String, suggestions: [String], distance: Double)?]] = [.french: [:], .english: [:]]

    static func cachedCanonicalSourceTerm(for lookupKey: String, sourceLanguage: StudyLanguage) -> String? {
        if let canonical = canonicalSourceLookup[sourceLanguage]?[lookupKey] {
            return canonical
        }

        switch sourceLanguage {
        case .french:
            return SupplementalFreeDictLexicon.canonicalSourceTerm(for: lookupKey)
        case .english:
            return nil
        }
    }

    static func bestLexiconTranslation(for sourceTerm: String, sourceLanguage: StudyLanguage) -> String? {
        let lookupKey = normalizedLookupText(cleanedQuizDisplayText(sourceTerm))
        guard !lookupKey.isEmpty else { return nil }

        if let direct = localTranslationLookup[sourceLanguage]?[lookupKey]?.first, !direct.isEmpty {
            return direct
        }

        if sourceLanguage == .french,
           let supplemental = SupplementalFreeDictLexicon.exactTranslations(for: lookupKey).first,
           !supplemental.isEmpty {
            return supplemental
        }

        if let approximate = cachedApproximateTranslationSuggestions(for: lookupKey, sourceLanguage: sourceLanguage),
           let suggestion = approximate.suggestions.first,
           !suggestion.isEmpty {
            return suggestion
        }

        return nil
    }

    static func cachedApproximateTranslationSuggestions(
        for lookupKey: String,
        sourceLanguage: StudyLanguage
    ) -> (lookupKey: String, suggestions: [String], distance: Double)? {
        translationLookupCacheLock.lock()
        if let cached = approximateTranslationCache[sourceLanguage]?[lookupKey] {
            translationLookupCacheLock.unlock()
            return cached
        }
        translationLookupCacheLock.unlock()

        guard let entries = translationLookupEntries[sourceLanguage], !entries.isEmpty else {
            translationLookupCacheLock.lock()
            approximateTranslationCache[sourceLanguage, default: [:]][lookupKey] = nil
            translationLookupCacheLock.unlock()
            return nil
        }

        let lookupLength = lookupKey.count
        let lookupPrefix = String(lookupKey.prefix(2))
        let lookupFirst = lookupKey.first
        let lookupCompact = compactLookupKey(lookupKey)
        let lookupCompactPrefix = String(lookupCompact.prefix(3))
        let lookupCompactLength = lookupCompact.count

        let candidates = entries.compactMap { entry -> (String, [String], Double)? in
            guard
                abs(entry.length - lookupLength) <= 4 ||
                abs(entry.compactLength - lookupCompactLength) <= 3
            else {
                return nil
            }

            let matchesPrimaryPrefix =
                entry.firstCharacter == lookupFirst ||
                entry.key.hasPrefix(lookupPrefix) ||
                lookupKey.hasPrefix(String(entry.key.prefix(2)))
            let matchesCompactPrefix =
                !lookupCompactPrefix.isEmpty && (
                    entry.compactKey.hasPrefix(lookupCompactPrefix) ||
                    lookupCompact.hasPrefix(String(entry.compactKey.prefix(3)))
                )
            let sharesPrefix = matchesPrimaryPrefix || matchesCompactPrefix

            guard sharesPrefix else { return nil }

            let distance = dataStoreLevenshtein(lookupKey, entry.key)
            let compactDistance = dataStoreLevenshtein(lookupCompact, entry.compactKey)
            let maxLength = max(lookupLength, entry.length)
            let maxCompactLength = max(lookupCompactLength, entry.compactLength)
            guard maxLength > 0, maxCompactLength > 0 else { return nil }

            let ratio = Double(distance) / Double(maxLength)
            let compactRatio = Double(compactDistance) / Double(maxCompactLength)
            let effectiveRatio = min(ratio, compactRatio * 0.92)
            let sameStart = lookupFirst == entry.firstCharacter
            let closeEnough =
                effectiveRatio <= 0.18 ||
                compactRatio <= 0.14 ||
                (sameStart && min(distance, compactDistance) <= 1) ||
                (abs(lookupLength - entry.length) <= 1 && distance <= 1) ||
                (abs(lookupCompactLength - entry.compactLength) <= 1 && compactDistance <= 1)

            guard closeEnough else { return nil }
            return (entry.key, entry.suggestions, effectiveRatio)
        }
        .sorted {
            if $0.2 == $1.2 {
                return $0.0.count < $1.0.count
            }
            return $0.2 < $1.2
        }

        let best = candidates.first

        translationLookupCacheLock.lock()
        approximateTranslationCache[sourceLanguage, default: [:]][lookupKey] = best
        translationLookupCacheLock.unlock()

        return best
    }

    private static func makeLocalTranslationLookup() -> [StudyLanguage: [String: [String]]] {
        [
            .french: OfflineFrenchGermanKnowledgePool.exactTranslationLookup,
            .english: [:]
        ]
    }

    private static func makeCanonicalSourceLookup() -> [StudyLanguage: [String: String]] {
        [
            .french: OfflineFrenchGermanKnowledgePool.canonicalSourceLookup,
            .english: [:]
        ]
    }

    private static func makeTranslationLookupEntries() -> [StudyLanguage: [TranslationLookupEntry]] {
        [
            .french: OfflineFrenchGermanKnowledgePool.translationLookupEntries,
            .english: [TranslationLookupEntry]()
        ]
    }

    private static func dataStoreLevenshtein(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        var dist = Array(repeating: Array(repeating: 0, count: right.count + 1), count: left.count + 1)

        for i in 0...left.count { dist[i][0] = i }
        for j in 0...right.count { dist[0][j] = j }

        guard !left.isEmpty, !right.isEmpty else {
            return max(left.count, right.count)
        }

        for i in 1...left.count {
            for j in 1...right.count {
                if left[i - 1] == right[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = min(
                        dist[i - 1][j] + 1,
                        dist[i][j - 1] + 1,
                        dist[i - 1][j - 1] + 1
                    )
                }
            }
        }

        return dist[left.count][right.count]
    }
}
