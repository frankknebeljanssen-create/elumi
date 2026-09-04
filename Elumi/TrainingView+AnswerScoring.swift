import SwiftUI

extension TrainingView {
    func submitTypedAnswer() {
        guard session.hasStartedTraining, currentCard != nil else { return }
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        stopListeningForTyping()
        typedAnswerFieldFocused = false
        speechController?.transcript = typedAnswer
        // Getippte Antwort ist eindeutig — evtl. noch stehende
        // Sprach-Alternativen dürfen hier nicht mitgewertet werden.
        speechController?.alternativeTranscripts = []
        evaluateResponse(typedAnswer)
    }

    /// **2026-06-09** — Alle zu prüfenden Eingabe-Varianten: die
    /// Haupteingabe plus die Alternativ-Transkriptionen der
    /// Spracherkennung. Eine Antwort gilt als richtig, wenn IRGENDEINE
    /// davon passt.
    ///
    /// Grund (User-Bugreport): „mai" wurde als „my" transkribiert und
    /// dadurch als falsch gewertet, obwohl die korrekte Variante in
    /// `result.transcriptions` vorlag — bisher wurde nur die
    /// Best-Transkription geprüft.
    private func answerCandidates(for rawInput: String) -> [String] {
        var candidates = [normalized(rawInput)]
        for alternative in speechController?.alternativeTranscripts ?? [] {
            let normalizedAlternative = normalized(alternative)
            if !normalizedAlternative.isEmpty, !candidates.contains(normalizedAlternative) {
                candidates.append(normalizedAlternative)
            }
        }
        return candidates
    }

    private func matchesExpected(rawInput: String, expected: String, card: FlashCard) -> Bool {
        answerCandidates(for: rawInput).contains {
            isCorrect(got: $0, expected: expected, for: card)
        }
    }

    func evaluateResponse(_ rawInput: String) {
        guard session.hasStartedTraining, let currentCard else { return }

        let expected = normalized(currentCard.answer)
        let got = normalized(rawInput)

        // **Daily Drop Modul 2.12 (2026-05-23)** — Count-Modus: EIN Versuch,
        // kein Retry, keine Sofort-Wertung. Der Check setzt nur Feedback +
        // Weiter-Wartezustand; gewertet + advanced wird erst im „Weiter"-Tap
        // (`advanceVokabelCountMode`), konsistent zum Quiz. Leere Tipp-
        // Eingabe = falsch (Soft-Lock-Auflösung). Leere Sprach-Erkennung
        // bleibt „Nicht erkannt" + Mikro-Auto-Resume (Mikro-Anker, Modul 5 /
        // Block 3.7.2) — der User kann erneut sprechen oder per „Weiter"
        // überspringen (= falsch). Normales Training: unverändert darunter.
        if isCountChainStep {
            if got.isEmpty {
                // Leere Eingabe wertet NICHT — „Weiter" bleibt gedimmt, bis
                // tatsächlich etwas eingegeben/gewählt und geprüft wurde
                // (User-Spec 2.12). Sprach-Modus: „Nicht erkannt" + Mikro-
                // Auto-Resume (Mikro-Anker, Modul 5 / Block 3.7.2). Tipp-
                // Modus: „Prüfen" ist bei leerem Feld ohnehin deaktiviert.
                if !isVokabelnTapMode {
                    lastResult = ScoreResult(
                        label: "Nicht erkannt",
                        detail: "Nochmal versuchen!"
                    )
                    scheduleFeedbackTask(after: 0.4) {
                        beginAutomaticListeningIfNeeded()
                    }
                }
                return
            }
            let correct = matchesExpected(rawInput: rawInput, expected: expected, card: currentCard)
            registerCountAnswer(correct: correct, answerShown: rawInput)
            return
        }

        guard !got.isEmpty else {
            lastResult = ScoreResult(
                label: "Nicht erkannt",
                detail: "Nochmal versuchen!"
            )
            // **Block 3.7.2 (2026-05-03)** — User-Spec: nach „Nicht
            // erkannt" muss der User das Mikro nicht manuell wieder
            // antippen, sondern Recording startet automatisch erneut.
            // Pattern-Mirror zum Mikro-Auto-Resume nach
            // „Lösung anzeigen" (Commit `b313559`): kurzer Delay
            // (0.4 s) gibt der gestoppten Audio-Session Zeit, sauber
            // abzubauen, bevor `beginAutomaticListeningIfNeeded()`
            // einen neuen Recording-Start triggert. Self-gated über
            // die Mode-Guards in `beginAutomaticListeningIfNeeded`
            // (No-Op in Article/Verb/Noun-Choice).
            scheduleFeedbackTask(after: 0.4) {
                beginAutomaticListeningIfNeeded()
            }
            return
        }

        if matchesExpected(rawInput: rawInput, expected: expected, card: currentCard) {
            typedAnswer = ""
            showingTypedAnswerInput = false
            handleCorrectAnswer()
        } else {
            feedbackPlayer.playStudyError()
            session.incrementFailedAttempts()
            session.recordAnswer(correct: false)
            lastResult = ScoreResult(
                label: "Falsch 😕",
                detail: "Nochmal versuchen!"
            )
            typedAnswer = ""
            showingTypedAnswerInput = false
            repeatCurrentPrompt()
        }
    }

    func handleCorrectAnswer() {
        feedbackPlayer.playStudySuccess()
        // firstAttempt: nur wenn die Karte beim ersten Versuch richtig
        // beantwortet wurde, zählt sie zur laufenden Streak-Serie. Retry-
        // Corrects brechen die Serie genauso ab wie eine falsche Antwort.
        session.recordAnswer(
            correct: true,
            firstAttempt: session.failedAttemptsOnCurrentCard == 0
        )
        lastResult = ScoreResult(label: "Richtig 🙂", detail: "")
        scheduleNextCard()
    }

    /// **Daily Drop Modul 2.12 (2026-05-23)** — Count-Modus-Check (Vokabel):
    /// spielt den Antwort-Sound, setzt das Visual-Feedback (Ergebnis +
    /// korrekte Lösung in `lastResult`/`countModeVokabelFeedback`) und den
    /// Weiter-Wartezustand. Wertet bewusst NICHT (kein `recordAnswer`) —
    /// Segment/Combo-Toast/Cap feuern erst im Weiter-Tap
    /// (`advanceVokabelCountMode`), exakt wie beim Quiz. `typedAnswer`
    /// bleibt stehen, damit das Tipp-Feld grün/rot eingefärbt werden kann.
    func registerCountAnswer(correct: Bool, answerShown: String) {
        if correct {
            feedbackPlayer.playStudySuccess()
        } else {
            feedbackPlayer.playStudyError()
        }
        vokabelPendingCorrect = correct
        vokabelCheckedAnswer = answerShown.trimmingCharacters(in: .whitespacesAndNewlines)
        vokabelAwaitingWeiter = true
        lastResult = ScoreResult(
            label: correct ? "Richtig 🙂" : "Falsch 😕",
            detail: correct ? "" : (currentCard?.answer ?? "")
        )
        typedAnswerFieldFocused = false
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

        var expectedVariants = answerVariants(for: expected, answerLanguageCode: card.answerLanguageCode)

        // **Wertung #3 (2026-05-23)** — Geschwister-Einträge (gleiche Prompt-
        // Seite im aktiven Pool) + deren `answerVariants` + Lexikon-Synonyme
        // als zusätzlich zulässige Antworten. Ersetzt die reine Lexikon-
        // Schleife: jetzt zählen auch mehrere hinterlegte Übersetzungen
        // desselben Prompts (z. B. „un peu" → „ein wenig" UND „ein bisschen").
        expectedVariants.formUnion(acceptedAnswerVariants(
            forPrompt: card.prompt,
            answerLanguageCode: card.answerLanguageCode,
            promptIsFrench: card.promptLanguageCode == "fr-FR",
            pool: session.preparedTrainingItems.map { (french: $0.french, german: $0.german) },
            normalize: normalized
        ))

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

    // **Codeaudit 2026-09-03, Stufe 2** — hier stand eine eigene
    // `levenshtein`-Implementierung ohne einen einzigen Aufrufer.
    // Die tatsächlich genutzten Varianten leben in
    // `LexiconTextUtility.levenshtein` und `answerLevenshtein`.
}
