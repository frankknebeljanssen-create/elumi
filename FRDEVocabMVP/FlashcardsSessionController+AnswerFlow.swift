import Foundation
import SwiftUI

extension FlashcardsSessionController {
    func submitTypedAnswer(
        sessionStore: FlashcardSessionStore,
        speechController: SpeechController,
        speaker: Speaker,
        feedbackPlayer: FeedbackPlayer,
        dismissTypedAnswerFocus: () -> Void
    ) {
        guard sessionStore.hasActiveSession, currentFlashCard != nil else { return }
        dismissTypedAnswerFocus()
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        stopListeningForTyping(speechController: speechController, speaker: speaker)
        speechController.transcript = typedAnswer
        evaluateResponse(
            typedAnswer,
            sessionStore: sessionStore,
            speechController: speechController,
            speaker: speaker,
            feedbackPlayer: feedbackPlayer,
            dismissTypedAnswerFocus: dismissTypedAnswerFocus
        )
    }

    func evaluateResponse(
        _ rawInput: String,
        sessionStore: FlashcardSessionStore,
        speechController: SpeechController,
        speaker: Speaker,
        feedbackPlayer: FeedbackPlayer,
        dismissTypedAnswerFocus: () -> Void
    ) {
        guard let currentFlashCard else { return }
        dismissTypedAnswerFocus()

        let expected = normalized(currentFlashCard.answer)
        let got = normalized(rawInput)

        guard !got.isEmpty else {
            lastResult = ScoreResult(label: "Nicht erkannt", detail: "Bitte nochmal versuchen.")
            showingSolution = false
            isFlashcardFlipped = false
            return
        }

        typedAnswer = ""
        hideTypedAnswerField()

        if isCorrect(got: got, expected: expected, card: currentFlashCard) {
            // **Peek-Protection (User-Revision 2026-04-22)**: Wurde die
            // Karte vorher manuell geflippt (gepeekt), zählt die
            // korrekte Antwort NICHT als gemeistert. Stattdessen wird
            // die Karte ans Ende des aktuellen Stapels geschoben und
            // kommt später nochmal dran — diesmal ohne Spicken.
            if let cardID = sessionStore.session?.currentCardID,
               peekedCurrentCardID == cardID {
                lastResult = ScoreResult(label: "Nochmal — diesmal ohne peek", detail: "")
                showingSolution = false
                isFlashcardFlipped = false
                peekedCurrentCardID = nil
                sessionStore.moveCurrentCardToEndAndAdvance()
                syncDisplayedCard(with: sessionStore)
                scheduleNextPrompt(
                    after: 0.3,
                    sessionStore: sessionStore,
                    speechController: speechController,
                    speaker: speaker,
                    areSoundsEnabled: true
                )
                return
            }

            if sessionStore.remainingCount > 1 {
                feedbackPlayer.playFlashcardSuccess()
            }
            lastResult = ScoreResult(label: "Korrekt! 🙂", detail: "")
            showingSolution = false
            isFlashcardFlipped = false
            animateCorrectCardRemoval(
                sessionStore: sessionStore,
                speechController: speechController,
                speaker: speaker,
                feedbackPlayer: feedbackPlayer
            )
            return
        }

        feedbackPlayer.playFlashcardError()
        lastResult = ScoreResult(label: "Falsch 😕", detail: "")

        // **User-Revision 2026-04-22**: bei falscher Antwort NICHT mehr
        // automatisch die nächste Karte aufdecken. Stattdessen:
        //   • Karte bleibt auf der Rückseite (Lösung sichtbar)
        //   • `isAwaitingContinueAfterWrong` gesetzt → Antwort-Card
        //     zeigt einen „Weiter"-Button
        //   • `markWrong()` + Karten-Advance erst, wenn der User den
        //     Button drückt (`continueAfterWrongAnswer(...)`).
        showingSolution = true
        isFlashcardFlipped = true
        isAwaitingContinueAfterWrong = true
        pushCurrentFlashcardToHistory(revealingSolution: true, sessionStore: sessionStore)
        // Keine Auto-Advance-Task mehr — der User steuert den Wechsel.
        cancelPendingFeedback()
    }

    /// Triggered durch den „Weiter"-Button in der Antwort-Card nach einer
    /// falschen Antwort. Führt die bisher im 1,5-s-Auto-Advance
    /// eingebettete Mutation aus: `markWrong()` zählt die Karte zurück,
    /// Karte wird zurückgeklappt, nächste Karte vorbereitet.
    func continueAfterWrongAnswer(
        sessionStore: FlashcardSessionStore,
        speechController: SpeechController,
        speaker: Speaker,
        feedbackPlayer: FeedbackPlayer
    ) {
        guard isAwaitingContinueAfterWrong else { return }
        isAwaitingContinueAfterWrong = false
        sessionStore.markWrong()
        isFlashcardFlipped = false
        showingSolution = false
        syncDisplayedCard(with: sessionStore)
        scheduleNextPrompt(
            after: 0.3,
            sessionStore: sessionStore,
            speechController: speechController,
            speaker: speaker,
            areSoundsEnabled: true
        )
    }

    func animateCorrectCardRemoval(
        sessionStore: FlashcardSessionStore,
        speechController: SpeechController,
        speaker: Speaker,
        feedbackPlayer: FeedbackPlayer
    ) {
        cancelPendingFeedback()
        resetCardFlyOut()
        let shouldPlayAchievement = sessionStore.remainingCount == 1
        pushCurrentFlashcardToHistory(revealingSolution: false, sessionStore: sessionStore)

        // Gelöste Karte fliegt nach LINKS raus — konsistent mit der
        // Swipe-Logik: links wischen = „weiter / gelöst", rechts wischen
        // = „zurück". Negative Werte = links.
        withAnimation(.easeIn(duration: 0.22)) {
            cardFlyOutOffset = -340
            cardFlyOutRotation = -12
            cardFlyOutOpacity = 0.15
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            sessionStore.markCorrect()
            self.syncDisplayedCard(with: sessionStore)
            if shouldPlayAchievement, sessionStore.session?.isCompleted == true {
                feedbackPlayer.playFlashcardAchievement()
            }
            self.resetCardFlyOut()
            self.scheduleNextPrompt(after: 0.32, sessionStore: sessionStore, speechController: speechController, speaker: speaker, areSoundsEnabled: true)
        }
        pendingFeedbackTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: workItem)
    }
}
