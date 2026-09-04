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

        // **Codeaudit 2026-09-03, Stufe 2** — auch `nil` ablegen. Vorher
        // wurde nur ein Treffer gecacht; jeder Fehlschlag öffnete die
        // 26-MB-SQLite bei jedem weiteren Zugriff neu.
        translationCacheLock.lock()
        exactGenderPairCache[cacheKey] = resolved
        translationCacheLock.unlock()

        return resolved
    }
}
