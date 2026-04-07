import Foundation
import SQLite3

extension SupplementalFreeDictLexicon {
    static func queryExactGenderPair(
        in database: OpaquePointer,
        sourceLookupKey: String,
        targetLookupKey: String
    ) -> ExactGenderPair? {
        let sql = """
        SELECT
            COALESCE(source_gender, ''),
            COALESCE(target_gender, ''),
            COALESCE(source_article, ''),
            COALESCE(target_leading_article, '')
        FROM lexicon_entries
        WHERE source_lookup_key = ? AND target_lookup_key = ?
        LIMIT 1;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return nil
        }

        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, sourceLookupKey, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, targetLookupKey, -1, sqliteTransient)

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        let sourceGender = lexiconGender(from: sqliteTextColumn(statement, index: 0))
        let targetGender = lexiconGender(from: sqliteTextColumn(statement, index: 1))
        let sourceArticle = optionalTrimmed(sqliteTextColumn(statement, index: 2))
        let targetArticle = optionalTrimmed(sqliteTextColumn(statement, index: 3))

        let frenchInfo = exactFrenchGenderInfo(gender: sourceGender, article: sourceArticle)
        let germanInfo = exactGermanGenderInfo(gender: targetGender, article: targetArticle)

        guard frenchInfo != nil || germanInfo != nil else { return nil }
        return (french: frenchInfo, german: germanInfo)
    }

    static func makeLexiconEntry(from statement: OpaquePointer?) -> LexiconEntry? {
        let cardTypeRaw = sqliteTextColumn(statement, index: 2)
        let cardType: CardType = cardTypeRaw == CardType.phrases.rawValue ? .phrases : .words
        let sourceTerm = sourceDisplayText(
            sqliteTextColumn(statement, index: 0),
            sourceLanguage: .french
        )
        let targetTerm = germanDisplayText(
            sqliteTextColumn(statement, index: 1),
            cardType: cardType,
            sourceHint: sourceTerm
        )

        guard !sourceTerm.isEmpty, !targetTerm.isEmpty else { return nil }

        let sourceLookupKey = sqliteTextColumn(statement, index: 3)
        let targetLookupKey = sqliteTextColumn(statement, index: 4)
        let sourceGender = lexiconGender(from: sqliteTextColumn(statement, index: 5))
        let targetGender = lexiconGender(from: sqliteTextColumn(statement, index: 6))
        let sourceArticle = optionalTrimmed(sqliteTextColumn(statement, index: 7))
        let targetArticle = optionalTrimmed(sqliteTextColumn(statement, index: 8))
        let id = [
            StudyLanguage.french.rawValue,
            cardType.rawValue,
            sourceLookupKey.isEmpty ? normalizedLookupText(sourceTerm) : sourceLookupKey,
            targetLookupKey.isEmpty ? normalizedLookupText(targetTerm) : targetLookupKey
        ].joined(separator: "|")

        return LexiconEntry(
            id: id,
            sourceTerm: sourceTerm,
            targetTerm: targetTerm,
            sourceLanguage: .french,
            cardType: cardType,
            frenchGender: preferredLexiconGenderInfo(
                exactFrenchGenderInfo(gender: sourceGender, article: sourceArticle),
                frenchGenderInfo(for: sourceTerm, cardType: cardType)
            ),
            germanGender: preferredLexiconGenderInfo(
                exactGermanGenderInfo(gender: targetGender, article: targetArticle),
                germanGenderInfo(for: targetTerm, cardType: cardType)
            )
        )
    }

    static func queryLexiconEntries(in database: OpaquePointer, limit: Int? = nil) -> [LexiconEntry] {
        let limitClause = limit.map { " LIMIT \($0)" } ?? ""
        let sql = """
        SELECT
            source_term,
            target_term,
            card_type,
            source_lookup_key,
            target_lookup_key,
            COALESCE(source_gender, ''),
            COALESCE(target_gender, ''),
            COALESCE(source_article, ''),
            COALESCE(target_leading_article, '')
        FROM lexicon_entries
        WHERE target_term != ''
        ORDER BY source_lookup_key ASC, target_lookup_key ASC\(limitClause);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }

        defer { sqlite3_finalize(statement) }

        var entries: [LexiconEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let entry = makeLexiconEntry(from: statement) else { continue }
            entries.append(entry)
        }

        return entries
    }

    static func querySearchLexiconEntries(
        in database: OpaquePointer,
        lookupQuery: String,
        compactQuery: String,
        limit: Int
    ) -> [LexiconEntry] {
        let sql = """
        SELECT
            source_term,
            target_term,
            card_type,
            source_lookup_key,
            target_lookup_key,
            COALESCE(source_gender, ''),
            COALESCE(target_gender, ''),
            COALESCE(source_article, ''),
            COALESCE(target_leading_article, '')
        FROM lexicon_entries
        WHERE target_term != ''
          AND (
            source_lookup_key LIKE ? || '%'
            OR target_lookup_key LIKE ? || '%'
            OR source_compact_key LIKE ? || '%'
            OR target_compact_key LIKE ? || '%'
          )
        ORDER BY
            CASE
                WHEN source_lookup_key = ? OR target_lookup_key = ? THEN 0
                WHEN source_lookup_key LIKE ? || '%' OR target_lookup_key LIKE ? || '%' THEN 1
                ELSE 2
            END ASC,
            LENGTH(source_lookup_key) ASC,
            source_lookup_key ASC,
            target_lookup_key ASC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }

        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 3, compactQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 4, compactQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 5, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 6, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 7, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 8, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_int(statement, 9, Int32(max(limit, 1)))

        var entries: [LexiconEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let entry = makeLexiconEntry(from: statement) else { continue }
            entries.append(entry)
        }

        return entries
    }
}
