import Foundation
import SQLite3

enum OfflineFrenchGermanKnowledgePool {
    static let records: [OfflineFrenchGermanLexiconRecord] = loadRecords()
    static let translatedRecords: [OfflineFrenchGermanLexiconRecord] = records.filter { !$0.targetTerm.isEmpty }
    static let frenchSourceTerms: [String] = records.map(\.sourceTerm)
    static let germanTargetTerms: [String] = translatedRecords.map(\.targetTerm)
    static let exactTranslationLookup: [String: [String]] = makeExactTranslationLookup()
    static let canonicalSourceLookup: [String: String] = makeCanonicalSourceLookup()
    static let translationLookupEntries: [TranslationLookupEntry] = makeTranslationLookupEntries()
    private static let variantSeparator = "\u{1F}"

    private static func loadRecords() -> [OfflineFrenchGermanLexiconRecord] {
        let tsvRecords = loadRecordsFromTSV()

        if let bundledSQLiteURL = Bundle.main.url(forResource: "ElumiKnowledgePool", withExtension: "sqlite"),
           let sqliteRecords = loadRecordsFromSQLite(at: bundledSQLiteURL),
           !sqliteRecords.isEmpty {
            return mergedRecords(base: sqliteRecords, overlay: tsvRecords)
        }

        return tsvRecords
    }

    private static func mergedRecords(
        base: [OfflineFrenchGermanLexiconRecord],
        overlay: [OfflineFrenchGermanLexiconRecord]
    ) -> [OfflineFrenchGermanLexiconRecord] {
        guard !overlay.isEmpty else { return base }

        func recordKey(_ record: OfflineFrenchGermanLexiconRecord) -> String {
            [
                record.sourceLookupKey,
                record.targetLookupKey,
                record.cardType.rawValue
            ].joined(separator: "|")
        }

        var merged = base
        var indexByKey: [String: Int] = [:]

        for (index, record) in merged.enumerated() {
            indexByKey[recordKey(record)] = index
        }

        for record in overlay {
            let key = recordKey(record)
            if let existingIndex = indexByKey[key] {
                merged[existingIndex] = record
            } else {
                indexByKey[key] = merged.count
                merged.append(record)
            }
        }

        return merged
    }

    private static func loadRecordsFromSQLite(at url: URL) -> [OfflineFrenchGermanLexiconRecord]? {
        var database: OpaquePointer?
        let openResult = sqlite3_open_v2(url.path, &database, SQLITE_OPEN_READONLY, nil)
        guard openResult == SQLITE_OK, let database else {
            if let database {
                sqlite3_close(database)
            }
            return nil
        }

        defer { sqlite3_close(database) }

        let sql = """
        SELECT
            source_term,
            target_term,
            card_type,
            source_lookup_key,
            source_compact_key,
            source_lookup_variants,
            source_compact_variants,
            target_lookup_key,
            target_compact_key,
            is_german_noun,
            is_french_question,
            COALESCE(source_gender, ''),
            COALESCE(target_gender, ''),
            COALESCE(source_article, ''),
            COALESCE(target_leading_article, '')
        FROM lexicon_entries
        ORDER BY id ASC;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            if let statement {
                sqlite3_finalize(statement)
            }
            return nil
        }

        defer { sqlite3_finalize(statement) }

        var loadedRecords: [OfflineFrenchGermanLexiconRecord] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            let cardTypeRaw = sqliteTextColumn(statement, index: 2)
            let cardType: CardType = cardTypeRaw == CardType.phrases.rawValue ? .phrases : .words
            let sourceTerm = sourceDisplayText(
                sqliteTextColumn(statement, index: 0),
                sourceLanguage: .french
            )
            let sourceLookupVariants = splitStoredVariants(sqliteTextColumn(statement, index: 5))
            let sourceCompactVariants = splitStoredVariants(sqliteTextColumn(statement, index: 6))
            let sourceGender = lexiconGender(from: sqliteTextColumn(statement, index: 11))
            let targetGender = lexiconGender(from: sqliteTextColumn(statement, index: 12))
            let sourceArticle = optionalTrimmed(sqliteTextColumn(statement, index: 13))
            let targetArticle = optionalTrimmed(sqliteTextColumn(statement, index: 14))
            let targetTerm = bootstrappedGermanText(
                sqliteTextColumn(statement, index: 1),
                cardType: cardType,
                sourceHint: sourceTerm
            )

            loadedRecords.append(
                OfflineFrenchGermanLexiconRecord(
                    sourceTerm: sourceTerm,
                    targetTerm: targetTerm,
                    cardType: cardType,
                    sourceLookupKey: sqliteTextColumn(statement, index: 3),
                    sourceCompactKey: sqliteTextColumn(statement, index: 4),
                    sourceLookupVariants: sourceLookupVariants,
                    sourceCompactVariants: sourceCompactVariants,
                    targetLookupKey: sqliteTextColumn(statement, index: 7),
                    targetCompactKey: sqliteTextColumn(statement, index: 8),
                    isGermanNoun: sqlite3_column_int(statement, 9) != 0,
                    isFrenchQuestion: sqlite3_column_int(statement, 10) != 0,
                    sourceGender: sourceGender,
                    targetGender: targetGender,
                    sourceArticle: sourceArticle,
                    targetLeadingArticle: targetArticle
                )
            )
        }

        return loadedRecords
    }

    private static func sqliteTextColumn(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let rawText = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: rawText)
    }

    private static func splitStoredVariants(_ rawValue: String) -> [String] {
        rawValue
            .split(separator: Character(variantSeparator), omittingEmptySubsequences: true)
            .map(String.init)
    }

    private static func loadRecordsFromTSV() -> [OfflineFrenchGermanLexiconRecord] {
        guard let url = Bundle.main.url(forResource: "ElumiKnowledgePool", withExtension: "tsv"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }

        var loadedRecords: [OfflineFrenchGermanLexiconRecord] = []
        var seen = Set<String>()

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.components(separatedBy: "\t")
            guard parts.count >= 3 else { continue }

            let usesExpandedSchema = parts.count >= 5
            let sourceDisplayRaw = usesExpandedSchema ? parts[0] : parts[0]
            let sourceLookupRaw = usesExpandedSchema ? parts[1] : ""
            let targetDisplayRaw = usesExpandedSchema ? parts[2] : parts[1]
            let targetLookupRaw = usesExpandedSchema ? parts[3] : ""
            let cardTypeRaw = usesExpandedSchema ? parts[4] : parts[2]
            let explicitGermanNoun = usesExpandedSchema ? boolFlag(from: parts[safe: 5]) : nil
            let explicitFrenchQuestion = usesExpandedSchema ? boolFlag(from: parts[safe: 6]) : nil
            let explicitTargetArticle = usesExpandedSchema ? optionalTrimmed(parts[safe: 7]) : nil

            let cardType: CardType = cardTypeRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "phrases" ? .phrases : .words
            let source = sourceDisplayText(sourceDisplayRaw, sourceLanguage: .french)
            let target = bootstrappedGermanText(targetDisplayRaw, cardType: cardType, sourceHint: source)
            guard !source.isEmpty else { continue }

            let sourceLookupVariants = deduplicatedLookupVariants(
                [sourceLookupRaw, source]
                + frenchLookupCandidates(for: source)
            )
            let sourceCompactVariants = deduplicatedCompactLookupVariants(sourceLookupVariants)
            let targetLookupVariants = deduplicatedLookupVariants(
                [targetLookupRaw, target]
                + germanLookupCandidates(for: target, cardType: cardType, sourceHint: source)
            )
            let targetLookupKey = targetLookupVariants.first ?? normalizedLookupText(target)
            let sourceLookupKey = sourceLookupVariants.first ?? normalizedLookupText(source)
            let targetLeadingArticle = explicitTargetArticle ?? leadingGermanArticle(in: target)
            let isGermanNoun = explicitGermanNoun ?? inferredGermanNounFlag(
                source: source,
                target: target,
                cardType: cardType
            )
            let isFrenchQuestion = explicitFrenchQuestion ?? shouldDisplayFrenchQuestionMark(
                original: sourceDisplayRaw,
                cleaned: source
            )

            let key = [
                sourceLookupKey,
                targetLookupKey,
                cardType.rawValue
            ].joined(separator: "|")

            guard seen.insert(key).inserted else { continue }

            loadedRecords.append(
                OfflineFrenchGermanLexiconRecord(
                    sourceTerm: source,
                    targetTerm: target,
                    cardType: cardType,
                    sourceLookupKey: sourceLookupKey,
                    sourceCompactKey: sourceCompactVariants.first ?? compactLookupKey(sourceLookupKey),
                    sourceLookupVariants: sourceLookupVariants,
                    sourceCompactVariants: sourceCompactVariants,
                    targetLookupKey: targetLookupKey,
                    targetCompactKey: compactLookupKey(targetLookupKey),
                    isGermanNoun: isGermanNoun,
                    isFrenchQuestion: isFrenchQuestion,
                    sourceGender: nil,
                    targetGender: nil,
                    sourceArticle: leadingFrenchArticle(in: source),
                    targetLeadingArticle: targetLeadingArticle
                )
            )
        }

        return loadedRecords
    }

    private static func makeExactTranslationLookup() -> [String: [String]] {
        var lookup: [String: Set<String>] = [:]

        for record in translatedRecords {
            guard !record.targetTerm.isEmpty else { continue }
            for key in record.sourceLookupVariants {
                lookup[key, default: []].insert(record.targetTerm)
            }
        }

        return Dictionary(uniqueKeysWithValues: lookup.map { key, values in
            (key, values.sorted())
        })
    }

    private static func makeCanonicalSourceLookup() -> [String: String] {
        var lookup: [String: String] = [:]

        for record in records {
            for key in record.sourceLookupVariants {
                if lookup[key] == nil || !record.targetTerm.isEmpty {
                    lookup[key] = record.sourceTerm
                }
            }
        }

        return lookup
    }

    private static func makeTranslationLookupEntries() -> [TranslationLookupEntry] {
        exactTranslationLookup.map { key, suggestions in
            TranslationLookupEntry(
                key: key,
                compactKey: compactLookupKey(key),
                suggestions: suggestions,
                length: key.count,
                compactLength: compactLookupKey(key).count,
                firstCharacter: key.first
            )
        }
    }
}
