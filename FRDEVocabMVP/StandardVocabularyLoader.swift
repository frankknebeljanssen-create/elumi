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

    static let vocabularyItems: [VocabularyItem] = allEntries.map { entry in
        let cardType: CardType = entry.sourceDisplay.split(separator: " ").count >= 3 ? .phrases : .words
        return VocabularyItem(
            french: entry.sourceDisplay,
            german: entry.target,
            cardType: cardType,
            level: vocabularyLevel(for: entry.level),
            sourceLanguage: .french
        )
    }

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
