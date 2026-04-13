import Foundation
import SQLite3

extension SupplementalFreeDictLexicon {

    // MARK: - Gender Lookup

    static func queryExactGenderPair(
        in database: OpaquePointer,
        sourceLookupKey: String,
        targetLookupKey: String
    ) -> ExactGenderPair? {
        let sql = """
        SELECT
            COALESCE(e.gender_fr, ''),
            COALESCE(e.gender_de, '')
        FROM entries e
        JOIN senses s ON s.entry_id = e.entry_id
        WHERE LOWER(e.lemma_fr) = ? AND LOWER(s.translation_de) = ?
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

        let frGenderRaw = sqliteTextColumn(statement, index: 0)
        let deGenderRaw = sqliteTextColumn(statement, index: 1)

        let frenchInfo = masterGenderInfo(raw: frGenderRaw, language: .french)
        let germanInfo = masterGenderInfo(raw: deGenderRaw, language: .german)

        guard frenchInfo != nil || germanInfo != nil else { return nil }
        return (french: frenchInfo, german: germanInfo)
    }

    /// Convert master DB gender string (m/f/n/empty) to LexiconGenderInfo
    private static func masterGenderInfo(raw: String, language: MasterGenderLanguage) -> LexiconGenderInfo? {
        switch raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "m":
            return LexiconGenderInfo(
                gender: .masculine,
                article: language == .french ? "le" : "der",
                isHeuristic: false
            )
        case "f":
            return LexiconGenderInfo(
                gender: .feminine,
                article: language == .french ? "la" : "die",
                isHeuristic: false
            )
        case "n":
            return LexiconGenderInfo(
                gender: .neuter,
                article: language == .french ? nil : "das",
                isHeuristic: false
            )
        default:
            return nil
        }
    }

    private enum MasterGenderLanguage { case french, german }

    // MARK: - Build LexiconEntry from new schema

    /// Builds a LexiconEntry from a query result row.
    /// Expected columns: 0=lemma_fr, 1=translation_de, 2=word_class, 3=gender_fr, 4=gender_de, 5=is_phrase, 6=entry_id
    static func makeLexiconEntryFromMaster(from statement: OpaquePointer?) -> LexiconEntry? {
        let lemmaFr = sqliteTextColumn(statement, index: 0)
        let translationDe = sqliteTextColumn(statement, index: 1)
        let wordClass = sqliteTextColumn(statement, index: 2)
        let genderFr = sqliteTextColumn(statement, index: 3)
        let genderDe = sqliteTextColumn(statement, index: 4)
        let isPhrase = sqlite3_column_int(statement, 5) != 0
        let entryId = sqlite3_column_int(statement, 6)

        let cardType: CardType = isPhrase ? .phrases : .words
        let isNoun = wordClass.lowercased() == "noun"

        let sourceTerm = sourceDisplayText(lemmaFr, sourceLanguage: .french)
        // Use translation directly from DB — no article manipulation
        // The new master DB already has correct article handling
        let targetTerm = translationDe

        guard !sourceTerm.isEmpty, !targetTerm.isEmpty else { return nil }

        let sourceLookupKey = normalizedLookupText(sourceTerm)
        let targetLookupKey = normalizedLookupText(targetTerm)

        let id = [
            StudyLanguage.french.rawValue,
            cardType.rawValue,
            sourceLookupKey,
            targetLookupKey,
            String(entryId)
        ].joined(separator: "|")

        let frenchGender = masterGenderInfo(raw: genderFr, language: .french)
            ?? frenchGenderInfo(for: sourceTerm, cardType: cardType)
        let germanGender = masterGenderInfo(raw: genderDe, language: .german)
            ?? germanGenderInfo(for: targetTerm, cardType: cardType)

        return LexiconEntry(
            id: id,
            sourceTerm: sourceTerm,
            targetTerm: targetTerm,
            sourceLanguage: .french,
            cardType: cardType,
            frenchGender: isNoun ? frenchGender : nil,
            germanGender: isNoun ? germanGender : nil,
            isGermanNoun: isNoun
        )
    }

    // MARK: - Query All Entries

    static func queryLexiconEntries(in database: OpaquePointer, limit: Int? = nil) -> [LexiconEntry] {
        let limitClause = limit.map { " LIMIT \($0)" } ?? ""
        let sql = """
        SELECT
            e.lemma_fr,
            s.translation_de,
            e.word_class,
            COALESCE(e.gender_fr, ''),
            COALESCE(e.gender_de, ''),
            e.is_phrase,
            e.entry_id
        FROM entries e
        JOIN senses s ON s.entry_id = e.entry_id
        WHERE s.translation_de != ''
        ORDER BY LOWER(e.lemma_fr) ASC, LOWER(s.translation_de) ASC\(limitClause);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }

        defer { sqlite3_finalize(statement) }

        var entries: [LexiconEntry] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let entry = makeLexiconEntryFromMaster(from: statement) else { continue }
            entries.append(entry)
        }

        return entries
    }

    // MARK: - Search via forms index

    static func querySearchLexiconEntries(
        in database: OpaquePointer,
        lookupQuery: String,
        compactQuery: String,
        limit: Int
    ) -> [LexiconEntry] {
        // Two-phase search: forms index (FR) + direct lemma/translation match (DE)
        let sql = """
        SELECT DISTINCT
            e.lemma_fr,
            s.translation_de,
            e.word_class,
            COALESCE(e.gender_fr, ''),
            COALESCE(e.gender_de, ''),
            e.is_phrase,
            e.entry_id
        FROM entries e
        JOIN senses s ON s.entry_id = e.entry_id
        WHERE s.translation_de != ''
          AND (
            e.entry_id IN (SELECT entry_id FROM forms WHERE form LIKE ? || '%')
            OR LOWER(e.lemma_fr) LIKE ? || '%'
            OR LOWER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(e.lemma_fr,'è','e'),'é','e'),'ê','e'),'ë','e'),'à','a'),'ô','o')) LIKE ? || '%'
            OR LOWER(e.lemma_de) LIKE ? || '%'
            OR LOWER(s.translation_de) LIKE ? || '%'
            OR LOWER(s.translation_de) LIKE '% ' || ? || '%'
          )
        ORDER BY
            CASE
                WHEN LOWER(e.lemma_fr) = ? OR LOWER(s.translation_de) = ? THEN 0
                WHEN LOWER(e.lemma_fr) LIKE ? || '%' OR LOWER(s.translation_de) LIKE ? || '%' THEN 1
                WHEN LOWER(s.translation_de) LIKE '% ' || ? || '%' THEN 2
                ELSE 3
            END ASC,
            LENGTH(e.lemma_fr) ASC,
            LOWER(e.lemma_fr) ASC,
            LOWER(s.translation_de) ASC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }

        defer { sqlite3_finalize(statement) }
        // WHERE: forms(1), lemma_fr(2), lemma_fr_stripped(3), lemma_de(4), translation_de prefix(5), translation_de word(6)
        sqlite3_bind_text(statement, 1, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 2, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 3, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 4, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 5, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 6, lookupQuery, -1, sqliteTransient)
        // ORDER BY: exact(7,8), prefix(9,10), word-in(11)
        sqlite3_bind_text(statement, 7, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 8, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 9, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 10, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 11, lookupQuery, -1, sqliteTransient)
        // LIMIT
        sqlite3_bind_int(statement, 12, Int32(max(limit, 1)))

        var entries: [LexiconEntry] = []
        var seen = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let entry = makeLexiconEntryFromMaster(from: statement) else { continue }
            // Dedup by normalized source+target (strips articles)
            let dedupKey = [
                strippingLeadingFrenchArticle(from: entry.sourceSortKey),
                strippingLeadingGermanArticle(from: entry.targetSortKey)
            ].joined(separator: "|")
            guard seen.insert(dedupKey).inserted else { continue }
            entries.append(entry)
        }

        return entries
    }
}
