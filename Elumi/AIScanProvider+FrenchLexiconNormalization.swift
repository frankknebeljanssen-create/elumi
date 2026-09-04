import Foundation

// Delegates to LexiconTextUtility (single source of truth)
extension AIScanProvider {
    func aiNormalizedLookupText(_ text: String) -> String {
        LexiconTextUtility.normalizedLookupText(text)
    }

    func aiCompactLookupKey(_ text: String) -> String {
        LexiconTextUtility.compactLookupKey(text)
    }

    func aiNormalizedWords(_ text: String) -> [String] {
        LexiconTextUtility.normalizedWords(text)
    }

    func aiLevenshtein(_ lhs: String, _ rhs: String) -> Int {
        LexiconTextUtility.levenshtein(lhs, rhs)
    }
}
