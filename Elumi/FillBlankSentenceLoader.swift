import Foundation

/// Loads fill-in-the-blank sentences from FillBlankSentences.tsv
enum FillBlankSentenceLoader {
    struct Sentence: Hashable {
        let sentenceFr: String
        let sentenceDe: String
        let blankWord: String
        let distractors: [String]
        let verbFr: String
        let nounFr: String
    }

    static let allSentences: [Sentence] = loadSentences()

    /// Find sentences where the verb OR noun exists in the user's vocabulary
    static func matchingSentences(for items: [VocabularyItem]) -> [Sentence] {
        let itemKeys = Set(items.map {
            $0.french.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        })
        let strippedKeys = Set(items.map { item -> String in
            let lower = item.french.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            for art in ["le ", "la ", "l'", "l'", "les ", "un ", "une "] {
                if lower.hasPrefix(art) { return String(lower.dropFirst(art.count)).trimmingCharacters(in: .whitespaces) }
            }
            return lower
        })
        let allKeys = itemKeys.union(strippedKeys)

        return allSentences.filter { sentence in
            allKeys.contains(sentence.verbFr.lowercased()) ||
            allKeys.contains(sentence.nounFr.lowercased()) ||
            allKeys.contains(strippedNoun(sentence.nounFr))
        }
    }

    private static func strippedNoun(_ text: String) -> String {
        let lower = text.lowercased()
        for art in ["le ", "la ", "l'", "l'", "les ", "un ", "une "] {
            if lower.hasPrefix(art) { return String(lower.dropFirst(art.count)).trimmingCharacters(in: .whitespaces) }
        }
        return lower
    }

    private static func loadSentences() -> [Sentence] {
        guard let url = Bundle.main.url(forResource: "FillBlankSentences", withExtension: "tsv") else {
            appDebugLog("⚠️ FillBlankSentences.tsv not found in bundle")
            return []
        }
        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = data.components(separatedBy: .newlines)
        var sentences: [Sentence] = []
        sentences.reserveCapacity(lines.count)

        for line in lines.dropFirst() {
            let cols = line.split(separator: "\t", maxSplits: 5).map(String.init)
            guard cols.count >= 6 else { continue }
            let distractors = cols[3].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            guard !distractors.isEmpty else { continue }
            sentences.append(Sentence(
                sentenceFr: cols[0],
                sentenceDe: cols[1],
                blankWord: cols[2],
                distractors: distractors,
                verbFr: cols[4],
                nounFr: cols[5]
            ))
        }
        appDebugLog("📚 FillBlankSentences loaded: \(sentences.count) sentences")
        return sentences
    }
}
