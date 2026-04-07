import Foundation
import SQLite3

private let variantSeparator = "\u{1F}"
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private enum CardType: String {
    case words
    case phrases
}

private struct LexiconRecord {
    let sourceTerm: String
    let targetTerm: String
    let cardType: CardType
    let sourceLookupKey: String
    let sourceCompactKey: String
    let sourceLookupVariants: [String]
    let sourceCompactVariants: [String]
    let targetLookupKey: String
    let targetCompactKey: String
    let isGermanNoun: Bool
    let isFrenchQuestion: Bool
    let sourceGender: String?
    let targetGender: String?
    let sourceArticle: String?
    let targetLeadingArticle: String?
}

private let scriptDirectoryURL = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
private let defaultInputURL = scriptDirectoryURL
    .deletingLastPathComponent()
    .appendingPathComponent("FRDEVocabMVP/FRDEKnowledgePool.tsv")
private let defaultOutputURL = scriptDirectoryURL
    .deletingLastPathComponent()
    .appendingPathComponent("FRDEVocabMVP/FRDEKnowledgePool.sqlite")
private let defaultSchemaURL = scriptDirectoryURL.appendingPathComponent("FRDEKnowledgePoolSchema.sql")

let arguments = CommandLine.arguments
let inputURL = arguments.count > 1 ? URL(fileURLWithPath: arguments[1]) : defaultInputURL
let outputURL = arguments.count > 2 ? URL(fileURLWithPath: arguments[2]) : defaultOutputURL
let schemaURL = arguments.count > 3 ? URL(fileURLWithPath: arguments[3]) : defaultSchemaURL

private let records = try loadRecords(from: inputURL)
try writeDatabase(records: records, to: outputURL, schemaURL: schemaURL)
print("Built \(records.count) lexicon rows at \(outputURL.path)")

private func loadRecords(from tsvURL: URL) throws -> [LexiconRecord] {
    let raw = try String(contentsOf: tsvURL, encoding: .utf8)
    var loadedRecords: [LexiconRecord] = []
    var seen = Set<String>()

    for line in raw.components(separatedBy: .newlines) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

        let parts = trimmed.components(separatedBy: "\t")
        guard parts.count >= 3 else { continue }

        let usesExpandedSchema = parts.count >= 5
        let sourceDisplayRaw = parts[0]
        let sourceLookupRaw = usesExpandedSchema ? parts[1] : ""
        let targetDisplayRaw = usesExpandedSchema ? parts[2] : parts[1]
        let targetLookupRaw = usesExpandedSchema ? parts[3] : ""
        let cardTypeRaw = usesExpandedSchema ? parts[4] : parts[2]
        let explicitGermanNoun = usesExpandedSchema ? boolFlag(from: parts[safe: 5]) : nil
        let explicitFrenchQuestion = usesExpandedSchema ? boolFlag(from: parts[safe: 6]) : nil
        let explicitTargetArticle = usesExpandedSchema ? optionalTrimmed(parts[safe: 7]) : nil

        let cardType: CardType = cardTypeRaw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "phrases" ? .phrases : .words
        let source = sourceDisplayText(sourceDisplayRaw)
        let target = cleanedQuizDisplayText(targetDisplayRaw)
        guard !source.isEmpty else { continue }

        let sourceLookupVariants = deduplicatedLookupVariants(
            [sourceLookupRaw, source]
            + frenchLookupCandidates(for: source)
        )
        let sourceCompactVariants = deduplicatedCompactLookupVariants(sourceLookupVariants)
        let targetLookupVariants = deduplicatedLookupVariants(
            [targetLookupRaw, target]
            + germanLookupCandidates(for: target)
        )

        let sourceLookupKey = sourceLookupVariants.first ?? normalizedLookupText(source)
        let targetLookupKey = targetLookupVariants.first ?? normalizedLookupText(target)
        let sourceCompactKey = sourceCompactVariants.first ?? compactLookupKey(sourceLookupKey)
        let targetCompactKey = compactLookupKey(targetLookupKey)
        let isGermanNoun = explicitGermanNoun ?? inferredGermanNounFlag(source: source, target: target, cardType: cardType)
        let isFrenchQuestion = explicitFrenchQuestion ?? shouldDisplayFrenchQuestionMark(original: sourceDisplayRaw, cleaned: source)
        let targetLeadingArticle = explicitTargetArticle ?? leadingGermanArticle(in: target)

        let uniqueKey = [sourceLookupKey, targetLookupKey, cardType.rawValue].joined(separator: "|")
        guard seen.insert(uniqueKey).inserted else { continue }

        loadedRecords.append(
            LexiconRecord(
                sourceTerm: source,
                targetTerm: target,
                cardType: cardType,
                sourceLookupKey: sourceLookupKey,
                sourceCompactKey: sourceCompactKey,
                sourceLookupVariants: sourceLookupVariants,
                sourceCompactVariants: sourceCompactVariants,
                targetLookupKey: targetLookupKey,
                targetCompactKey: targetCompactKey,
                isGermanNoun: isGermanNoun,
                isFrenchQuestion: isFrenchQuestion,
                sourceGender: nil,
                targetGender: nil,
                sourceArticle: nil,
                targetLeadingArticle: targetLeadingArticle
            )
        )
    }

    return loadedRecords
}

private func writeDatabase(records: [LexiconRecord], to outputURL: URL, schemaURL: URL) throws {
    try? FileManager.default.removeItem(at: outputURL)

    var database: OpaquePointer?
    guard sqlite3_open(outputURL.path, &database) == SQLITE_OK, let database else {
        throw databaseError(from: database, fallback: "Could not open SQLite database.")
    }

    defer { sqlite3_close(database) }

    let schema = try String(contentsOf: schemaURL, encoding: .utf8)
    guard sqlite3_exec(database, schema, nil, nil, nil) == SQLITE_OK else {
        throw databaseError(from: database, fallback: "Could not apply schema.")
    }

    let insertSQL = """
    INSERT INTO lexicon_entries (
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
        source_gender,
        target_gender,
        source_article,
        target_leading_article
    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
    """

    var insertStatement: OpaquePointer?
    guard sqlite3_prepare_v2(database, insertSQL, -1, &insertStatement, nil) == SQLITE_OK, let insertStatement else {
        throw databaseError(from: database, fallback: "Could not prepare insert statement.")
    }

    defer { sqlite3_finalize(insertStatement) }

    guard sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
        throw databaseError(from: database, fallback: "Could not start transaction.")
    }

    do {
        for record in records {
            sqlite3_reset(insertStatement)
            sqlite3_clear_bindings(insertStatement)

            bind(record.sourceTerm, to: insertStatement, index: 1)
            bind(record.targetTerm, to: insertStatement, index: 2)
            bind(record.cardType.rawValue, to: insertStatement, index: 3)
            bind(record.sourceLookupKey, to: insertStatement, index: 4)
            bind(record.sourceCompactKey, to: insertStatement, index: 5)
            bind(record.sourceLookupVariants.joined(separator: variantSeparator), to: insertStatement, index: 6)
            bind(record.sourceCompactVariants.joined(separator: variantSeparator), to: insertStatement, index: 7)
            bind(record.targetLookupKey, to: insertStatement, index: 8)
            bind(record.targetCompactKey, to: insertStatement, index: 9)
            sqlite3_bind_int(insertStatement, 10, record.isGermanNoun ? 1 : 0)
            sqlite3_bind_int(insertStatement, 11, record.isFrenchQuestion ? 1 : 0)
            if let sourceGender = record.sourceGender {
                bind(sourceGender, to: insertStatement, index: 12)
            } else {
                sqlite3_bind_null(insertStatement, 12)
            }
            if let targetGender = record.targetGender {
                bind(targetGender, to: insertStatement, index: 13)
            } else {
                sqlite3_bind_null(insertStatement, 13)
            }
            if let sourceArticle = record.sourceArticle {
                bind(sourceArticle, to: insertStatement, index: 14)
            } else {
                sqlite3_bind_null(insertStatement, 14)
            }
            if let targetLeadingArticle = record.targetLeadingArticle {
                bind(targetLeadingArticle, to: insertStatement, index: 15)
            } else {
                sqlite3_bind_null(insertStatement, 15)
            }

            guard sqlite3_step(insertStatement) == SQLITE_DONE else {
                throw databaseError(from: database, fallback: "Could not insert lexicon row.")
            }
        }

        try upsertMetadata(key: "schema_version", value: "2", in: database)
        try upsertMetadata(key: "record_count", value: String(records.count), in: database)
        try upsertMetadata(key: "generated_at", value: ISO8601DateFormatter().string(from: Date()), in: database)

        guard sqlite3_exec(database, "COMMIT TRANSACTION;", nil, nil, nil) == SQLITE_OK else {
            throw databaseError(from: database, fallback: "Could not commit transaction.")
        }
    } catch {
        sqlite3_exec(database, "ROLLBACK TRANSACTION;", nil, nil, nil)
        throw error
    }
}

private func upsertMetadata(key: String, value: String, in database: OpaquePointer?) throws {
    let sql = """
    INSERT INTO metadata (key, value)
    VALUES (?, ?)
    ON CONFLICT(key) DO UPDATE SET value = excluded.value;
    """

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
        throw databaseError(from: database, fallback: "Could not prepare metadata statement.")
    }

    defer { sqlite3_finalize(statement) }

    bind(key, to: statement, index: 1)
    bind(value, to: statement, index: 2)

    guard sqlite3_step(statement) == SQLITE_DONE else {
        throw databaseError(from: database, fallback: "Could not write metadata.")
    }
}

private func bind(_ value: String, to statement: OpaquePointer?, index: Int32) {
    sqlite3_bind_text(statement, index, value, -1, sqliteTransient)
}

private func databaseError(from database: OpaquePointer?, fallback: String) -> NSError {
    let message = database.flatMap { sqlite3_errmsg($0) }.map { String(cString: $0) } ?? fallback
    return NSError(domain: "FRDEKnowledgePoolBuilder", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
}

private func shouldDisplayFrenchQuestionMark(original: String, cleaned: String) -> Bool {
    let words = normalizedLookupText(cleaned).split(separator: " ").map(String.init)
    guard !words.isEmpty else { return original.contains("?") }

    let firstWord = words[0]
    let firstTwoWords = words.prefix(2).joined(separator: " ")
    let firstThreeWords = words.prefix(3).joined(separator: " ")
    let singleWordQuestionStarts: Set<String> = [
        "comment", "ou", "où", "pourquoi", "quand", "combien",
        "quel", "quelle", "quels", "quelles", "qui", "que"
    ]
    let multiWordQuestionStarts: Set<String> = [
        "puis je", "pouvez vous", "est ce", "est ce que", "est ce qu",
        "ou est", "où est", "ou sont", "où sont",
        "ou habites", "où habites", "ou puis", "où puis",
        "combien de temps", "quelle heure"
    ]

    if singleWordQuestionStarts.contains(firstWord) ||
        multiWordQuestionStarts.contains(firstTwoWords) ||
        multiWordQuestionStarts.contains(firstThreeWords) {
        return true
    }

    let inversionPattern = #"(?iu)\b(?:est|faut|peut|doit|va|vient|habites|avez|pouvez|souhaitez)\s+(?:t\s+)?(?:il|elle|on|tu|vous|nous|je)\b"#
    if cleaned.range(of: inversionPattern, options: .regularExpression) != nil {
        return true
    }

    if original.contains("?") {
        return words.count > 1
    }

    return false
}

private func sourceDisplayText(_ text: String) -> String {
    let restored = restoringFrenchElisions(text)
    guard !restored.isEmpty else { return restored }
    if shouldDisplayFrenchQuestionMark(original: text, cleaned: restored) {
        let base = restored
            .replacingOccurrences(of: #"\s*\?$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return base + " ?"
    }
    return restored
        .replacingOccurrences(of: #"\s*\?$"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func cleanedQuizDisplayText(_ text: String) -> String {
    text
        .replacingOccurrences(of: #"\[[^\[\]]+\]"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"\/[^\/]+\/"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"(?iu)^\s*\[[^\]]*$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?iu)(^|\s)\[[A-Za-zˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ'’\-\.\,]+\b"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"(?iu)^\s*\[[A-Za-zˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ\s'’\-\.\,]+\s+"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?iu)\s+\[[A-Za-zˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ\s'’\-\.\,]+$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?iu)^\s*\[[A-Za-zˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ\s'’\-\.\,]+$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?iu)^\s*[\[/][^\s]+\s+"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?iu)^\s*[^\s]*[ˈˌːəæœøɥʁʀŋʃʒɲθðɑɔɛɪʊʌ][^\s]*\s+"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)^\s*[\[\]/]+|[\[\]/]+\s*$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)[*†‡•●▪◦※§]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)(^|\s)[~^_#]+(?=\s|$)"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)(^|\s)['’`]+(?=\p{L})"#, with: "$1", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)^['’`]+"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)['’`]+$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)(^|\s)[^\p{L}\p{M}\p{N}'’\-]+(?=\s|$)"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #"(?u)^[^\p{L}\p{M}\p{N}]+|[^\p{L}\p{M}\p{N}]+$"#, with: "", options: .regularExpression)
        .replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func restoringFrenchElisions(_ text: String) -> String {
    let cleaned = cleanedQuizDisplayText(text)
    guard !cleaned.isEmpty else { return cleaned }

    let apostropheVowels = "aeiouyhàâäæéèêëîïôöœùûü"
    let singleLetterPattern = "(?iu)\\b([cdjlmnst])\\s+(?=[\(apostropheVowels)])"
    let quPattern = "(?iu)\\b(qu|jusqu|lorsqu|puisqu)\\s+(?=[\(apostropheVowels)])"

    return cleaned
        .replacingOccurrences(of: singleLetterPattern, with: "$1’", options: .regularExpression)
        .replacingOccurrences(of: quPattern, with: "$1’", options: .regularExpression)
}

private func normalizedLookupText(_ text: String) -> String {
    cleanedQuizDisplayText(text)
        .folding(options: .diacriticInsensitive, locale: .current)
        .lowercased()
        .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: " ", options: .regularExpression)
        .replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func compactLookupKey(_ text: String) -> String {
    normalizedLookupText(text).replacingOccurrences(of: " ", with: "")
}

private func deduplicatedLookupVariants(_ candidates: [String]) -> [String] {
    var seen = Set<String>()
    return candidates
        .map(normalizedLookupText(_:))
        .filter { !$0.isEmpty }
        .filter { seen.insert($0).inserted }
}

private func deduplicatedCompactLookupVariants(_ candidates: [String]) -> [String] {
    var seen = Set<String>()
    return candidates
        .map(compactLookupKey(_:))
        .filter { !$0.isEmpty }
        .filter { seen.insert($0).inserted }
}

private func frenchLookupCandidates(for text: String) -> [String] {
    let canonical = sourceDisplayText(text)
    let apostropheSpaces = canonical
        .replacingOccurrences(of: "’", with: " ")
        .replacingOccurrences(of: "'", with: " ")
    let apostropheRemoved = canonical
        .replacingOccurrences(of: "’", with: "")
        .replacingOccurrences(of: "'", with: "")

    return [
        text,
        cleanedQuizDisplayText(text),
        restoringFrenchElisions(text),
        canonical,
        apostropheSpaces,
        apostropheRemoved
    ]
}

private func germanLookupCandidates(for text: String) -> [String] {
    [
        text,
        cleanedQuizDisplayText(text)
    ]
}

private func inferredGermanNounFlag(source: String, target: String, cardType: CardType) -> Bool {
    guard cardType == .words else { return false }

    if leadingGermanArticle(in: target) != nil || looksLikeFrenchNounSource(source) {
        return true
    }

    let targetWords = normalizedLookupText(target).split(separator: " ").map(String.init)
    return targetWords.count == 1 && target.count >= 3
}

private func looksLikeFrenchNounSource(_ text: String) -> Bool {
    let normalized = normalizedLookupText(text)
    guard !normalized.isEmpty else { return false }

    let frenchArticleHints: Set<String> = [
        "le", "la", "les", "un", "une", "des", "du", "de la", "de l", "au", "aux", "l"
    ]

    let words = normalized.split(separator: " ").map(String.init)
    guard let first = words.first else { return false }

    if frenchArticleHints.contains(first) {
        return true
    }

    if words.count >= 2 {
        let firstTwo = "\(words[0]) \(words[1])"
        return frenchArticleHints.contains(firstTwo)
    }

    return false
}

private func leadingGermanArticle(in text: String) -> String? {
    let germanArticleHints: Set<String> = [
        "der", "die", "das", "ein", "eine", "einer", "einem", "einen", "den", "dem", "des", "kein", "keine"
    ]

    let normalized = normalizedLookupText(text)
    let words = normalized.split(separator: " ").map(String.init)
    guard let first = words.first, germanArticleHints.contains(first) else { return nil }
    return first
}

private func boolFlag(from rawValue: String?) -> Bool? {
    guard let rawValue else { return nil }
    let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return nil }

    switch normalized {
    case "1", "true", "yes", "y", "oui", "ja":
        return true
    case "0", "false", "no", "n", "non", "nein":
        return false
    default:
        return nil
    }
}

private func optionalTrimmed(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
