import Foundation

extension ScanOCRNoiseFilter {
    func isLikelyHeadingOrMetaLine(_ text: String) -> Bool {
        let normalized = text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: #"[^a-z0-9 ]+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return true }

        let words = dependencies.normalizedWords(normalized)
        let sourceCoverage = dependencies.sourceLexiconCoverageScore(text)
        let hasSentencePunctuation =
            text.contains("?") ||
            text.contains("!") ||
            text.contains(".")

        if sourceCoverage >= 0.96 {
            if words.count == 1 && normalized.count <= 8 {
                return false
            }

            if words.count <= 4 && hasSentencePunctuation {
                return false
            }
        }

        let headingPatterns = [
            #"^(part|unit|lesson|chapter|exercise|section|topic)\s+[a-z0-9]+$"#,
            #"^(part|unit|lesson|chapter|exercise|section|topic)\s+[a-z0-9]+\s+[a-z0-9]+$"#,
            #"^(vocabulary|vocabulaire|wortschatz|franzosisch|englisch|deutsch|title|heading)$"#
        ]

        if headingPatterns.contains(where: { normalized.range(of: $0, options: .regularExpression) != nil }) {
            return true
        }

        let textbookHeadingPatterns = [
            #"^c est parti\s+tu tappelles comment$"#,
            #"^c est parti\s+ca va$"#,
            #"^c est parti\s+tu tappelles comment\s+ca va$"#,
            #"^c est parti\s+ca va\s+tu tappelles comment$"#
        ]

        if textbookHeadingPatterns.contains(where: { normalized.range(of: $0, options: .regularExpression) != nil }) {
            return true
        }

        if words.count <= 3 {
            let headingWords: Set<String> = [
                "part", "unit", "lesson", "chapter", "exercise", "section", "topic",
                "vocabulary", "vocabulaire", "wortschatz", "title", "heading"
            ]
            if words.contains(where: { headingWords.contains($0) }) {
                return true
            }
        }

        if normalized.hasPrefix("c est parti") && words.count >= 5 {
            return true
        }

        return false
    }
}
