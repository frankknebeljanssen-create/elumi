import Foundation
import NaturalLanguage

extension ScanPreviewBuilder {
    func allowsShortSingleWordLexiconMatch(
        _ source: String,
        in originalText: String,
        sourceLanguage: StudyLanguage
    ) -> Bool {
        guard dependencies.normalizedLookupText(source).count <= 2 else { return false }
        guard originalText.contains("?") || originalText.contains("!") else { return false }

        switch sourceLanguage {
        case .french, .english:
            return true
        }
    }

    func sourceTokens(from text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var tokens: [String] = []

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let token = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if token.range(of: #"\p{L}"#, options: .regularExpression) != nil {
                tokens.append(token)
            }
            return true
        }

        return tokens
    }

    func normalizedSourceTermForScanExtraction(
        _ text: String,
        sourceLanguage: StudyLanguage
    ) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let normalizedSource: String
        if sourceLanguage == .english || dependencies.looksLikeEnglishInfinitiveMarker(trimmed) {
            normalizedSource = dependencies.normalizedEnglishVerbMarker(trimmed)
        } else {
            normalizedSource = trimmed
        }

        return dependencies.canonicalizedSourceTermIfNeeded(normalizedSource, sourceLanguage)
    }
}
