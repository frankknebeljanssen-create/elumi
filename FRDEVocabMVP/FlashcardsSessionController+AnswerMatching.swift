import Foundation

extension FlashcardsSessionController {
    func normalized(_ text: String) -> String {
        text
            .lowercased()
            .replacingOccurrences(of: "ß", with: "ss")
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: "'", with: " ")
            .replacingOccurrences(of: "’", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func isCorrect(got: String, expected: String, card: FlashCard) -> Bool {
        if requiresFrenchArticle(for: card),
           hasFrenchArticleMismatch(got: got, expected: expected) {
            return false
        }

        var expectedVariants = answerVariants(for: expected, answerLanguageCode: card.answerLanguageCode)

        // Add synonym translations from supplemental lexicon
        if card.promptLanguageCode == "fr-FR" {
            let translations = SupplementalFreeDictLexicon.exactTranslations(for: card.prompt)
            for translation in translations {
                expectedVariants.formUnion(answerVariants(for: normalized(translation), answerLanguageCode: card.answerLanguageCode))
            }
        }

        let gotVariants = answerVariants(for: got, answerLanguageCode: card.answerLanguageCode)

        for gotVariant in gotVariants {
            if expectedVariants.contains(where: { isApproximateMatch(got: gotVariant, expected: $0) }) {
                return true
            }
        }

        return false
    }

    /// **Bug #4 Fix (2026-05-23)** — delegiert an den geteilten
    /// `approximateAnswerMatch` (längen-geschützter Substring statt nacktem
    /// `contains`). Bleibt als Wrapper, weil `isCorrect` +
    /// `hasFrenchArticleMismatch` ihn aufrufen.
    func isApproximateMatch(got: String, expected: String) -> Bool {
        approximateAnswerMatch(got: got, expected: expected)
    }

    func requiresFrenchArticle(for card: FlashCard) -> Bool {
        card.answerLanguageCode == "fr-FR" && card.category == "Karteikarte"
    }

    func hasFrenchArticleMismatch(got: String, expected: String) -> Bool {
        let expectedStem = droppingFrenchLeadingArticle(from: expected)
        guard expectedStem != expected else { return false }

        let gotStem = droppingFrenchLeadingArticle(from: got)
        let gotHasArticle = gotStem != got
        let expectedArticle = leadingFrenchArticle(in: expected)
        let gotArticle = leadingFrenchArticle(in: got)
        let stemsMatch = isApproximateMatch(got: gotStem, expected: expectedStem)

        guard stemsMatch else { return false }
        return !gotHasArticle || gotArticle != expectedArticle
    }

    func droppingFrenchLeadingArticle(from text: String) -> String {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return text }

        if words.count >= 2 {
            let firstTwo = "\(words[0]) \(words[1])"
            if frenchTwoWordArticles.contains(firstTwo) {
                return words.dropFirst(2).joined(separator: " ")
            }
        }

        if frenchSingleWordArticles.contains(words[0]) {
            return words.dropFirst().joined(separator: " ")
        }

        return text
    }

    func leadingFrenchArticle(in text: String) -> String? {
        let words = text.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return nil }

        if words.count >= 2 {
            let firstTwo = "\(words[0]) \(words[1])"
            if frenchTwoWordArticles.contains(firstTwo) {
                return firstTwo
            }
        }

        if frenchSingleWordArticles.contains(words[0]) {
            return words[0]
        }

        return nil
    }

    var frenchSingleWordArticles: Set<String> {
        ["l", "la", "le", "les", "un", "une", "des", "du", "au", "aux"]
    }

    var frenchTwoWordArticles: Set<String> {
        ["de la", "de l", "de les", "a la", "a l"]
    }

    func levenshtein(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        var dist = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)

        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }

        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    dist[i][j] = dist[i - 1][j - 1]
                } else {
                    dist[i][j] = min(
                        dist[i - 1][j] + 1,
                        dist[i][j - 1] + 1,
                        dist[i - 1][j - 1] + 1
                    )
                }
            }
        }

        return dist[a.count][b.count]
    }
}
