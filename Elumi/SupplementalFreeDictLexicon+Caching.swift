import Foundation

extension SupplementalFreeDictLexicon {
    static func exactGenderPair(sourceTerm: String, targetTerm: String) -> ExactGenderPair? {
        let sourceKey = normalizedLookupText(sourceTerm)
        let targetKey = normalizedLookupText(targetTerm)
        guard !sourceKey.isEmpty, !targetKey.isEmpty else { return nil }

        let cacheKey = "\(sourceKey)|\(targetKey)"

        translationCacheLock.lock()
        if let cached = exactGenderPairCache[cacheKey] {
            translationCacheLock.unlock()
            return cached
        }
        translationCacheLock.unlock()

        let resolved = withReadOnlyDatabase { database in
            queryExactGenderPair(
                in: database,
                sourceLookupKey: sourceKey,
                targetLookupKey: targetKey
            )
        }

        translationCacheLock.lock()
        if let resolved {
            exactGenderPairCache[cacheKey] = resolved
        }
        translationCacheLock.unlock()

        return resolved
    }
}
