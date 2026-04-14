import Foundation
import SQLite3

/// Ein Beispielsatz-Paar aus der `examples`-Tabelle.
/// Mehrere Beispiele pro Eintrag sind möglich (geordnet via `order`).
struct DictionaryExample: Identifiable, Equatable {
    let id: Int           // example_id (stabil in der DB)
    let entryID: Int      // entry_id, Join-Key zu entries/senses
    let order: Int        // 1 = bevorzugtes Hauptbeispiel
    let french: String
    let german: String
    let type: String      // z.B. "simple_sentence"
    let level: String     // z.B. "7"
}

extension SupplementalFreeDictLexicon {

    // MARK: - Quick Lemma Translation Lookup

    /// Deutsche Hauptübersetzung für ein französisches Lemma.
    /// Bevorzugt `entries.lemma_de`; fällt auf erste `senses.translation_de` zurück.
    static func germanTranslation(forFrenchLemma lemma: String, wordClassHint: String? = nil) -> String? {
        let key = lemma.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }
        return withReadOnlyDatabase { database -> String? in
            // 1) direkte entry.lemma_de (bevorzugte Grundform) — ggf. eingegrenzt auf Wortart
            let directSQL: String
            if wordClassHint != nil {
                directSQL = """
                SELECT lemma_de FROM entries
                WHERE LOWER(lemma_fr) = ? AND LOWER(word_class) = ?
                LIMIT 1;
                """
            } else {
                directSQL = """
                SELECT lemma_de FROM entries
                WHERE LOWER(lemma_fr) = ?
                LIMIT 1;
                """
            }
            var statement: OpaquePointer?
            if sqlite3_prepare_v2(database, directSQL, -1, &statement, nil) == SQLITE_OK,
               let stmt = statement {
                sqlite3_bind_text(stmt, 1, key, -1, sqliteTransient)
                if let hint = wordClassHint {
                    sqlite3_bind_text(stmt, 2, hint.lowercased(), -1, sqliteTransient)
                }
                if sqlite3_step(stmt) == SQLITE_ROW {
                    let de = sqliteTextColumn(stmt, index: 0)
                    sqlite3_finalize(stmt)
                    if !de.isEmpty { return de }
                } else {
                    sqlite3_finalize(stmt)
                }
            } else if statement != nil {
                sqlite3_finalize(statement)
            }

            // 2) Fallback: erste translation_de aus senses
            let fallbackSQL = """
            SELECT s.translation_de
            FROM entries e
            JOIN senses s ON s.entry_id = e.entry_id
            WHERE LOWER(e.lemma_fr) = ? AND s.translation_de != ''
            ORDER BY s.sense_id ASC
            LIMIT 1;
            """
            var stmt2: OpaquePointer?
            defer { if stmt2 != nil { sqlite3_finalize(stmt2) } }
            guard sqlite3_prepare_v2(database, fallbackSQL, -1, &stmt2, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_text(stmt2, 1, key, -1, sqliteTransient)
            guard sqlite3_step(stmt2) == SQLITE_ROW else { return nil }
            let de = sqliteTextColumn(stmt2, index: 0)
            return de.isEmpty ? nil : de
        }
    }

    // MARK: - Examples (mehrere pro entry_id, sortiert nach example_order)

    /// Alle Beispielsätze eines Eintrags, sortiert: `example_order` ASC, danach `example_id` ASC.
    /// Leeres Ergebnis wenn keine Beispiele oder Einträge mit leeren FR/DE-Feldern
    /// (werden herausgefiltert).
    static func examples(forEntryID entryID: Int) -> [DictionaryExample] {
        withReadOnlyDatabase { database in
            queryExamples(in: database, entryID: entryID)
        } ?? []
    }

    /// Bevorzugtes Hauptbeispiel (`example_order = 1`), wenn vorhanden.
    /// Fallback: erstes Beispiel überhaupt.
    static func primaryExample(forEntryID entryID: Int) -> DictionaryExample? {
        let list = examples(forEntryID: entryID)
        return list.first(where: { $0.order == 1 }) ?? list.first
    }

    private static func queryExamples(in database: OpaquePointer, entryID: Int) -> [DictionaryExample] {
        let sql = """
        SELECT
            example_id,
            example_order,
            COALESCE(example_fr, ''),
            COALESCE(example_de, ''),
            COALESCE(example_type, ''),
            COALESCE(example_level, '')
        FROM examples
        WHERE entry_id = ?
        ORDER BY
            CASE WHEN example_order > 0 THEN example_order ELSE 999 END ASC,
            example_id ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            return []
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_int(statement, 1, Int32(entryID))

        var results: [DictionaryExample] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let exampleID = Int(sqlite3_column_int(statement, 0))
            let order = Int(sqlite3_column_int(statement, 1))
            let fr = sqliteTextColumn(statement, index: 2)
            let de = sqliteTextColumn(statement, index: 3)
            let type = sqliteTextColumn(statement, index: 4)
            let level = sqliteTextColumn(statement, index: 5)
            guard !fr.isEmpty else { continue }
            results.append(DictionaryExample(
                id: exampleID,
                entryID: entryID,
                order: order,
                french: fr,
                german: de,
                type: type,
                level: level
            ))
        }
        return results
    }

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
            isGermanNoun: isNoun,
            entryID: Int(entryId),
            wordClass: wordClass
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
                -- Forms-Treffer (auch Compound-Wörter wie „autobahn", „strassenbahn") als
                -- gleichwertig zu lemma_fr/translation_de prefix-Treffern behandeln,
                -- damit sie nicht durch das LIMIT abgeschnitten werden.
                WHEN e.entry_id IN (SELECT entry_id FROM forms WHERE LOWER(form) = ?) THEN 0
                WHEN LOWER(e.lemma_fr) LIKE ? || '%' OR LOWER(s.translation_de) LIKE ? || '%' THEN 1
                WHEN e.entry_id IN (SELECT entry_id FROM forms WHERE LOWER(form) LIKE ? || '%') THEN 1
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
        // ORDER BY: exact lemma_fr(7), exact translation_de(8), exact form(9),
        //          prefix lemma_fr(10), prefix translation_de(11), prefix form(12),
        //          word-in translation_de(13)
        sqlite3_bind_text(statement, 7, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 8, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 9, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 10, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 11, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 12, lookupQuery, -1, sqliteTransient)
        sqlite3_bind_text(statement, 13, lookupQuery, -1, sqliteTransient)
        // LIMIT
        sqlite3_bind_int(statement, 14, Int32(max(limit, 1)))

        var entries: [LexiconEntry] = []
        var seen = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let entry = makeLexiconEntryFromMaster(from: statement) else { continue }
            let strippedSource = strippingLeadingFrenchArticle(from: entry.sourceSortKey)
            let strippedTarget = strippingLeadingGermanArticle(from: entry.targetSortKey)
            let sourceKey = strippedSource.isEmpty ? entry.sourceSortKey : strippedSource
            let targetKey = strippedTarget.isEmpty ? entry.targetSortKey : strippedTarget
            let dedupKey = "\(sourceKey)|\(targetKey)"
            guard seen.insert(dedupKey).inserted else { continue }
            entries.append(entry)
        }

        return entries
    }
}
