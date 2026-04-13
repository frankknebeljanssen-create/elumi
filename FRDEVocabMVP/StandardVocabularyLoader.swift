import Foundation
import SQLite3

/// Loads all vocabulary from FRDEMasterLexicon.sqlite (unified source).
/// Single source of truth for all vocabulary in the app.
enum StandardVocabularyLoader {
    struct Entry {
        let sourceDisplay: String
        let target: String
        let cardType: CardType
        let level: String          // A1, A2, B1, B2, C1, C2
        let wordClass: String      // noun, verb, adjective, adverb, etc.
        let gender: String         // m, f, or empty
        let topic: String          // Essen & Trinken, Familie & Freunde, etc.
        let frequency: Double
    }

    static let allEntries: [Entry] = loadEntries()

    static let vocabularyItems: [VocabularyItem] = {
        var seen = Set<String>()
        return allEntries.compactMap { entry -> VocabularyItem? in
            // Use cardType from DB (is_phrase), not word-count heuristic
            let cardType = entry.cardType
            let key = [
                entry.sourceDisplay.lowercased()
                    .folding(options: .diacriticInsensitive, locale: .current),
                entry.target.lowercased()
                    .folding(options: .diacriticInsensitive, locale: .current),
                cardType.rawValue
            ].joined(separator: "|")
            guard seen.insert(key).inserted else { return nil }

            return VocabularyItem(
                rawFrench: entry.sourceDisplay,
                rawGerman: entry.target,
                cardType: cardType,
                level: vocabularyLevel(for: entry.level),
                sourceLanguage: .french,
                wordClass: entry.wordClass.isEmpty ? nil : entry.wordClass
            )
        }
    }()

    static func items(for level: String) -> [VocabularyItem] {
        vocabularyItems.enumerated().compactMap { index, item in
            allEntries[index].level == level ? item : nil
        }
    }

    static func items(forLevels levels: Set<String>) -> [VocabularyItem] {
        vocabularyItems.enumerated().compactMap { index, item in
            levels.contains(allEntries[index].level) ? item : nil
        }
    }

    static func items(forWordClass wordClass: String) -> [VocabularyItem] {
        vocabularyItems.enumerated().compactMap { index, item in
            allEntries[index].wordClass == wordClass ? item : nil
        }
    }

    static func items(forTopic topic: String) -> [VocabularyItem] {
        vocabularyItems.enumerated().compactMap { index, item in
            allEntries[index].topic == topic ? item : nil
        }
    }

    static var allTopics: [String] {
        let topics = Set(allEntries.map(\.topic))
        return topics.sorted().filter { $0 != "Allgemein" } + ["Allgemein"]
    }

    static var allLevels: [String] {
        ["A1", "A2", "B1", "B2", "C1", "C2"]
    }

    /// Fast lookup set of French verb forms (lowercase)
    static let verbSet: Set<String> = {
        Set(allEntries.filter { $0.wordClass == "verb" }.map { $0.sourceDisplay.lowercased() })
    }()

    /// Fast lookup: is this French word a verb? (includes conjugated forms)
    static func isVerb(_ frenchText: String) -> Bool {
        let key = frenchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if verbSet.contains(key) { return true }
        return inflectionWordClassMap[key] == "verb"
    }

    /// Fast lookup set of French nouns (lowercase)
    static let nounSet: Set<String> = {
        Set(allEntries.filter { $0.wordClass == "noun" }.map { $0.sourceDisplay.lowercased() })
    }()

    /// Fast lookup: is this French word a noun? (includes plural forms)
    static func isNoun(_ frenchText: String) -> Bool {
        let key = frenchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if nounSet.contains(key) { return true }
        return inflectionWordClassMap[key] == "noun"
    }

    /// Fast lookup: word class for a French term (lowercase key → word class)
    static let wordClassMap: [String: String] = {
        var map: [String: String] = [:]
        for entry in allEntries where !entry.wordClass.isEmpty {
            map[entry.sourceDisplay.lowercased()] = entry.wordClass
        }
        return map
    }()

    /// Inflection form → word class map (lazy loaded from SQLite forms table)
    static let inflectionWordClassMap: [String: String] = {
        var map: [String: String] = [:]
        _ = SupplementalFreeDictLexicon.withReadOnlyDatabase { database -> Bool in
            let sql = """
                SELECT DISTINCT f.form, e.word_class
                FROM forms f
                JOIN entries e ON f.entry_id = e.entry_id
                WHERE f.form_type = 'inflection' AND e.word_class != ''
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let stmt = statement else { return false }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let form = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let wc = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                guard !form.isEmpty, !wc.isEmpty else { continue }
                // Store individual words from the form (e.g. "je suis" → "suis")
                let words = form.lowercased().split(separator: " ")
                if let lastWord = words.last, words.count <= 2 {
                    map[String(lastWord)] = wc
                }
            }
            return true
        }
        return map
    }()

    /// Lookup word class for a French term — returns "noun", "verb", etc. or nil
    static func wordClass(for frenchText: String) -> String? {
        let key = frenchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let wc = wordClassMap[key] { return wc }
        let stripped = strippedArticle(key)
        if stripped != key, let wc = wordClassMap[stripped] { return wc }
        // Check inflection forms (conjugated verbs, plural nouns, etc.)
        if let wc = inflectionWordClassMap[key] { return wc }
        if stripped != key, let wc = inflectionWordClassMap[stripped] { return wc }
        return nil
    }

    /// Fast lookup set of non-noun French words (verbs, adjectives, adverbs, etc.)
    static let nonNounSet: Set<String> = {
        Set(allEntries.filter { $0.wordClass != "noun" && !$0.wordClass.isEmpty }.map { $0.sourceDisplay.lowercased() })
    }()

    /// Fast lookup: is this French word explicitly NOT a noun (verb, adjective, adverb, etc.)?
    static func isNonNoun(_ frenchText: String) -> Bool {
        let lower = frenchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if nonNounSet.contains(lower) { return true }
        // Also check without article (in case "le super" was passed)
        let stripped = strippedArticle(lower)
        return stripped != lower && nonNounSet.contains(stripped)
    }

    private static func strippedArticle(_ text: String) -> String {
        for art in ["le ", "la ", "l'", "l\u{2019}", "les ", "un ", "une ", "des ", "du "] {
            if text.hasPrefix(art) { return String(text.dropFirst(art.count)).trimmingCharacters(in: .whitespaces) }
        }
        return text
    }

    // MARK: - Pre-built VocabularyLists for the list picker

    private static let levelNames: [String: String] = [
        "A1": "A1 Grundwortschatz",
        "A2": "A2 Aufbauwortschatz",
        "B1": "B1 Mittelstufe",
        "B2": "B2 Oberstufe",
        "C1": "C1 Fortgeschritten",
        "C2": "C2 Experte"
    ]

    static let allInOneList: VocabularyList = VocabularyList(
        id: UUID(uuidString: "F1E1EEE1-A000-4000-A000-000000000000")!,
        name: "Komplettes Wörterbuch",
        items: vocabularyItems,
        isBuiltIn: true,
        collectionPreset: .standardLevel,
        isAggregateVocabulary: true
    )

    static let levelLists: [VocabularyList] = {
        var lists: [VocabularyList] = []
        let levelUUIDs: [String: UUID] = [
            "A1": UUID(uuidString: "F1E1EEE1-A100-4000-A000-000000000001")!,
            "A2": UUID(uuidString: "F1E1EEE1-A200-4000-A000-000000000002")!,
            "B1": UUID(uuidString: "F1E1EEE1-B100-4000-A000-000000000003")!,
            "B2": UUID(uuidString: "F1E1EEE1-B200-4000-A000-000000000004")!,
            "C1": UUID(uuidString: "F1E1EEE1-C100-4000-A000-000000000005")!,
            "C2": UUID(uuidString: "F1E1EEE1-C200-4000-A000-000000000006")!,
        ]
        for level in ["A1", "A2", "B1", "B2", "C1", "C2"] {
            let levelItems = items(for: level)
            guard !levelItems.isEmpty else { continue }
            lists.append(VocabularyList(
                id: levelUUIDs[level]!,
                name: levelNames[level] ?? level,
                items: levelItems,
                isBuiltIn: true,
                collectionPreset: .standardLevel
            ))
        }
        return lists
    }()

    static let topicLists: [VocabularyList] = {
        let minItems = 20
        var lists: [VocabularyList] = []
        let sortedTopics = allTopics.filter { $0 != "Allgemein" }
        for (index, topic) in sortedTopics.enumerated() {
            let topicItems = items(forTopic: topic)
            guard topicItems.count >= minItems else { continue }
            let idString = String(format: "AAAA0000-0000-4000-A000-%012d", index + 1)
            lists.append(VocabularyList(
                id: UUID(uuidString: idString) ?? UUID(),
                name: topic,
                items: topicItems,
                isBuiltIn: true,
                collectionPreset: .standardTopic
            ))
        }
        return lists.sorted { $0.items.count > $1.items.count }
    }()

    // MARK: - Private

    private static func loadEntries() -> [Entry] {
        guard let result = SupplementalFreeDictLexicon.withReadOnlyDatabase({ database -> [Entry] in
            let sql = """
                SELECT lemma_fr, lemma_de, word_class, gender_fr, level, is_phrase, frequency_rank, topic
                FROM entries
                ORDER BY frequency_rank ASC
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let stmt = statement else {
                return []
            }
            defer { sqlite3_finalize(stmt) }

            var entries: [Entry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let lemmaFr = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let lemmaDe = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                guard !lemmaFr.isEmpty, !lemmaDe.isEmpty else { continue }

                let wordClass = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let genderFr = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
                let level = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
                let isPhrase = sqlite3_column_int(stmt, 5)
                let freqRank = sqlite3_column_int(stmt, 6)
                let topic = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? "Allgemein"

                entries.append(Entry(
                    sourceDisplay: lemmaFr,
                    target: lemmaDe,
                    cardType: isPhrase == 1 ? .phrases : .words,
                    level: level,
                    wordClass: wordClass,
                    gender: genderFr,
                    topic: topic,
                    frequency: Double(freqRank)
                ))
            }
            return entries
        }) else {
            print("⚠️ FRDEMasterLexicon.sqlite not found or failed to open")
            return []
        }

        print("📚 StandardVocabulary loaded from SQLite: \(result.count) entries")
        return result
    }

    private static func vocabularyLevel(for level: String) -> VocabularyLevel? {
        switch level {
        case "A1", "A2": return .beginner
        case "B1": return .intermediate
        case "B2", "C1", "C2": return .advanced
        default: return nil
        }
    }
}
