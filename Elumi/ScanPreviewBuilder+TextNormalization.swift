import Foundation
import NaturalLanguage

extension ScanPreviewBuilder {
    func normalizedFreeText(from lines: [String]) -> String {
        var chunks: [String] = []

        for line in lines {
            let cleaned = dependencies.extractedDisplayTerm(line)
            guard !cleaned.isEmpty else { continue }

            if let last = chunks.last,
               !last.hasSuffix("."),
               !last.hasSuffix("!"),
               !last.hasSuffix("?") {
                chunks[chunks.count - 1] = last + " " + cleaned
            } else {
                chunks.append(cleaned)
            }
        }

        return chunks.joined(separator: " ")
    }

    func sentenceUnits(from text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []

        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty {
                sentences.append(sentence)
            }
            return true
        }

        if sentences.isEmpty {
            return [text]
        }

        return sentences
    }
}
