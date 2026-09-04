import Foundation

/// Loads verb+noun combination pairs from VerbNounPairs.tsv
/// Used by quiz to generate "Verbinde den Ausdruck" questions
enum VerbNounPairLoader {
    struct VerbNounPair: Hashable {
        let verbFr: String
        let verbDe: String
        let nounFr: String
        let nounDe: String
    }

    /// All loaded pairs
    static let allPairs: [VerbNounPair] = loadPairs()

    /// Lookup: French verb (lowercased) → pairs containing that verb
    static let pairsByVerbFr: [String: [VerbNounPair]] = {
        Dictionary(grouping: allPairs, by: { $0.verbFr.lowercased() })
    }()

    /// Lookup: French noun (lowercased, stripped of article) → pairs containing that noun
    static let pairsByNounFr: [String: [VerbNounPair]] = {
        Dictionary(grouping: allPairs, by: { strippedNoun($0.nounFr) })
    }()

    /// Find pairs where BOTH verb and noun exist in the given vocabulary items
    static func matchingPairs(for items: [VocabularyItem]) -> [VerbNounPair] {
        let itemKeys = Set(items.map { $0.french.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) })
        // Also index stripped versions (without articles)
        let strippedKeys = Set(items.map { strippedNoun($0.french) })
        let allKeys = itemKeys.union(strippedKeys)

        return allPairs.filter { pair in
            let verbKey = pair.verbFr.lowercased()
            let nounKey = strippedNoun(pair.nounFr)
            return allKeys.contains(verbKey) && allKeys.contains(nounKey)
        }
    }

    private static func strippedNoun(_ text: String) -> String {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for article in ["le ", "la ", "l'", "l'", "les ", "un ", "une ", "des ", "du "] {
            if lower.hasPrefix(article) {
                return String(lower.dropFirst(article.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return lower
    }

    private static func loadPairs() -> [VerbNounPair] {
        guard let url = Bundle.main.url(forResource: "VerbNounPairs", withExtension: "tsv") else {
            appDebugLog("⚠️ VerbNounPairs.tsv not found in bundle")
            return []
        }

        guard let data = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let lines = data.components(separatedBy: .newlines)
        var pairs: [VerbNounPair] = []
        pairs.reserveCapacity(lines.count)

        for line in lines.dropFirst() { // Skip header
            let cols = line.split(separator: "\t", maxSplits: 3).map(String.init)
            guard cols.count >= 4 else { continue }
            pairs.append(VerbNounPair(
                verbFr: cols[0],
                verbDe: cols[1],
                nounFr: cols[2],
                nounDe: cols[3]
            ))
        }

        appDebugLog("📚 VerbNounPairs loaded: \(pairs.count) pairs")
        return pairs
    }
}
