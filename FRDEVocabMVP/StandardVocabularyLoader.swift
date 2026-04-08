import Foundation

/// Loads the FLELex-based vocabulary from StandardpaketGPT.tsv
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
            let cardType: CardType = entry.sourceDisplay.split(separator: " ").count >= 3 ? .phrases : .words
            // Deduplicate by normalized key to prevent crashes
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
                sourceLanguage: .french
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

    // MARK: - Pre-built VocabularyLists for the list picker

    private static let levelNames: [String: String] = [
        "A1": "A1 Grundwortschatz",
        "A2": "A2 Aufbauwortschatz",
        "B1": "B1 Mittelstufe",
        "B2": "B2 Oberstufe",
        "C1": "C1 Fortgeschritten",
        "C2": "C2 Experte"
    ]

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
        guard let url = Bundle.main.url(forResource: "StandardpaketGPT", withExtension: "tsv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            print("⚠️ StandardpaketGPT.tsv not found")
            return []
        }

        var entries: [Entry] = []
        let lines = content.components(separatedBy: .newlines)

        for (index, line) in lines.enumerated() {
            guard index > 0, !line.isEmpty else { continue } // Skip header
            let columns = line.components(separatedBy: "\t")
            guard columns.count >= 7 else { continue }

            let sourceDisplay = columns[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let target = columns[1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !sourceDisplay.isEmpty, !target.isEmpty else { continue }

            entries.append(Entry(
                sourceDisplay: sourceDisplay,
                target: target,
                cardType: columns.count > 2 ? (columns[2] == "phrases" ? .phrases : .words) : .words,
                level: columns.count > 3 ? columns[3] : "",
                wordClass: columns.count > 4 ? columns[4] : "",
                gender: columns.count > 5 ? columns[5] : "",
                topic: columns.count > 6 ? columns[6] : "Allgemein",
                frequency: columns.count > 8 ? (Double(columns[8]) ?? 0) : 0
            ))
        }

        print("📚 StandardVocabulary loaded: \(entries.count) entries")
        return entries
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
