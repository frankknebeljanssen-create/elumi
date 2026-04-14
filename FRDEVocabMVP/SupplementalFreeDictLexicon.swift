import Foundation
import SQLite3

enum SupplementalFreeDictLexicon {
    typealias ExactGenderPair = (french: LexiconGenderInfo?, german: LexiconGenderInfo?)
    static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    static let translationCacheLock = NSLock()
    static var exactTranslationCache: [String: [String]] = [:]
    static var canonicalSourceCache: [String: String?] = [:]
    static var lexiconEntryCache: [LexiconEntry]?
    static var previewLexiconEntryCaches: [Int: [LexiconEntry]] = [:]
    static var exactGenderPairCache: [String: ExactGenderPair] = [:]

    static func exactTranslations(for lookupKey: String) -> [String] {
        let normalizedKey = normalizedLookupText(lookupKey)
        guard !normalizedKey.isEmpty else { return [] }

        translationCacheLock.lock()
        if let cached = exactTranslationCache[normalizedKey] {
            translationCacheLock.unlock()
            return cached
        }
        translationCacheLock.unlock()

        let compactKey = compactLookupKey(normalizedKey)
        // Search via forms index → senses translations
        let results = withReadOnlyDatabase { database in
            queryDistinctStrings(
                in: database,
                sql: """
                SELECT DISTINCT s.translation_de
                FROM forms f
                JOIN senses s ON s.entry_id = f.entry_id
                WHERE f.form = ? AND s.translation_de != ''
                ORDER BY s.translation_de ASC LIMIT 8;
                """,
                parameter: normalizedKey
            )
        } ?? []

        let compactResults: [String]
        if results.isEmpty, !compactKey.isEmpty {
            compactResults = withReadOnlyDatabase { database in
                queryDistinctStrings(
                    in: database,
                    sql: """
                    SELECT DISTINCT s.translation_de
                    FROM entries e
                    JOIN senses s ON s.entry_id = e.entry_id
                    WHERE LOWER(e.lemma_fr) = ? AND s.translation_de != ''
                    ORDER BY s.translation_de ASC LIMIT 8;
                    """,
                    parameter: normalizedKey
                )
            } ?? []
        } else {
            compactResults = []
        }

        let merged = Array(Set(results + compactResults)).sorted()

        translationCacheLock.lock()
        exactTranslationCache[normalizedKey] = merged
        translationCacheLock.unlock()

        return merged
    }

    static func canonicalSourceTerm(for lookupKey: String) -> String? {
        let normalizedKey = normalizedLookupText(lookupKey)
        guard !normalizedKey.isEmpty else { return nil }

        translationCacheLock.lock()
        if let cached = canonicalSourceCache[normalizedKey] {
            translationCacheLock.unlock()
            return cached
        }
        translationCacheLock.unlock()

        let compactKey = compactLookupKey(normalizedKey)
        // Search via forms index → canonical lemma
        let direct = withReadOnlyDatabase { database in
            queryFirstString(
                in: database,
                sql: """
                SELECT e.lemma_fr
                FROM forms f
                JOIN entries e ON e.entry_id = f.entry_id
                WHERE f.form = ?
                LIMIT 1;
                """,
                parameter: normalizedKey
            )
        }

        let resolved = direct ?? {
            guard !compactKey.isEmpty else { return nil }
            return withReadOnlyDatabase { database in
                queryFirstString(
                    in: database,
                    sql: "SELECT lemma_fr FROM entries WHERE LOWER(lemma_fr) = ? LIMIT 1;",
                    parameter: normalizedKey
                )
            }
        }()

        let canonicalSource = resolved.map {
            sourceDisplayText($0, sourceLanguage: .french)
        }

        translationCacheLock.lock()
        canonicalSourceCache[normalizedKey] = canonicalSource
        translationCacheLock.unlock()

        return canonicalSource
    }

    static func lexiconEntries() -> [LexiconEntry] {
        translationCacheLock.lock()
        if let cached = lexiconEntryCache {
            translationCacheLock.unlock()
            return cached
        }
        translationCacheLock.unlock()

        let loadedEntries = withReadOnlyDatabase { database in
            queryLexiconEntries(in: database)
        } ?? []

        translationCacheLock.lock()
        lexiconEntryCache = loadedEntries
        translationCacheLock.unlock()

        return loadedEntries
    }

    static func previewLexiconEntries(limit: Int) -> [LexiconEntry] {
        guard limit > 0 else { return [] }

        translationCacheLock.lock()
        if let cached = previewLexiconEntryCaches[limit] {
            translationCacheLock.unlock()
            return cached
        }
        translationCacheLock.unlock()

        let loadedEntries = withReadOnlyDatabase { database in
            queryLexiconEntries(in: database, limit: limit)
        } ?? []

        translationCacheLock.lock()
        previewLexiconEntryCaches[limit] = loadedEntries
        translationCacheLock.unlock()

        return loadedEntries
    }

    static func searchLexiconEntries(matching query: String, limit: Int = 250) -> [LexiconEntry] {
        let normalizedQuery = normalizedLookupText(query)
        let compactQuery = compactLookupKey(query)
        guard !normalizedQuery.isEmpty else { return [] }

        return withReadOnlyDatabase { database in
            querySearchLexiconEntries(
                in: database,
                lookupQuery: normalizedQuery,
                compactQuery: compactQuery,
                limit: limit
            )
        } ?? []
    }

    static func enrichMissingGenderInfo(in entries: [LexiconEntry]) -> [LexiconEntry] {
        entries.map { entry in
            guard entry.cardType == .words,
                  entry.frenchGender == nil || entry.germanGender == nil else {
                return entry
            }

            guard let exactPair = exactGenderPair(
                sourceTerm: entry.sourceTerm,
                targetTerm: entry.targetTerm
            ) else {
                return entry
            }

            return LexiconEntry(
                id: entry.id,
                sourceTerm: entry.sourceTerm,
                targetTerm: entry.targetTerm,
                sourceLanguage: entry.sourceLanguage,
                cardType: entry.cardType,
                frenchGender: preferredLexiconGenderInfo(entry.frenchGender, exactPair.french),
                germanGender: preferredLexiconGenderInfo(entry.germanGender, exactPair.german),
                isGermanNoun: entry.isGermanNoun
            )
        }
    }

    static func exactGenderInfo(sourceTerm: String, targetTerm: String) -> (french: LexiconGenderInfo?, german: LexiconGenderInfo?)? {
        exactGenderPair(sourceTerm: sourceTerm, targetTerm: targetTerm)
    }
}
