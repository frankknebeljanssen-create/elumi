import SwiftUI

extension TrainingView {
    func submitTypedAnswer() {
        guard session.hasStartedTraining, currentCard != nil else { return }
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        stopListeningForTyping()
        typedAnswerFieldFocused = false
        speechController?.transcript = typedAnswer
        evaluateResponse(typedAnswer)
    }

    func evaluateResponse(_ rawInput: String) {
        guard session.hasStartedTraining, let currentCard else { return }

        let expected = normalized(currentCard.answer)
        let got = normalized(rawInput)

        guard !got.isEmpty else {
            lastResult = ScoreResult(
                label: "Nicht erkannt",
                detail: "Bitte nochmal versuchen."
            )
            return
        }

        if isCorrect(got: got, expected: expected, for: currentCard) {
            typedAnswer = ""
            showingTypedAnswerInput = false
            handleCorrectAnswer()
        } else {
            feedbackPlayer.playStudyError()
            session.incrementFailedAttempts()
            lastResult = ScoreResult(
                label: "Falsch",
                detail: "Bitte nochmal."
            )
            typedAnswer = ""
            showingTypedAnswerInput = false
            repeatCurrentPrompt()
        }
    }

    func handleCorrectAnswer() {
        feedbackPlayer.playStudySuccess()
        lastResult = ScoreResult(label: "Richtig 🙂", detail: "")
        scheduleNextCard()
    }

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

    func isCorrect(got: String, expected: String, for card: FlashCard) -> Bool {
        if requiresFrenchArticle(for: card),
           hasFrenchArticleMismatch(got: got, expected: expected) {
            return false
        }

        let expectedVariants = answerVariants(for: expected, answerLanguageCode: card.answerLanguageCode)
        let gotVariants = answerVariants(for: got, answerLanguageCode: card.answerLanguageCode)

        for gotVariant in gotVariants {
            if expectedVariants.contains(where: { isApproximateMatch(got: gotVariant, expected: $0) }) {
                return true
            }
        }

        return false
    }

    func isApproximateMatch(got: String, expected: String) -> Bool {
        if got == expected {
            return true
        }

        let distance = levenshtein(got, expected)
        let maxLength = max(got.count, expected.count)
        let ratio = maxLength == 0 ? 0 : Double(distance) / Double(maxLength)
        return ratio <= 0.25 || got.contains(expected) || expected.contains(got)
    }

    func requiresFrenchArticle(for card: FlashCard) -> Bool {
        card.answerLanguageCode == "fr-FR" && card.category == CardType.words.categoryName
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
