import Foundation

// Delegates to LexiconTextUtility (single source of truth)
extension ScanReviewMapper {
    static func mapperNormalizedLookupText(_ text: String) -> String {
        LexiconTextUtility.normalizedLookupText(text)
    }

    static func mapperCompactLookupKey(_ text: String) -> String {
        LexiconTextUtility.compactLookupKey(text)
    }

    static func mapperNormalizedWords(_ text: String) -> [String] {
        LexiconTextUtility.normalizedWords(text)
    }

    static func mapperLevenshtein(_ lhs: String, _ rhs: String) -> Int {
        LexiconTextUtility.levenshtein(lhs, rhs)
    }
}
