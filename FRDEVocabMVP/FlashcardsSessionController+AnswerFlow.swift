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
        showingSolution = false
        isFlashcardFlipped = false
        pushCurrentFlashcardToHistory(revealingSolution: true, sessionStore: sessionStore)
        sessionStore.markWrong()
        syncDisplayedCard(with: sessionStore)
        scheduleNextPrompt(after: 0.55, sessionStore: sessionStore, speechController: speechController, speaker: speaker, areSoundsEnabled: true)
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

        withAnimation(.easeIn(duration: 0.22)) {
            cardFlyOutOffset = 340
            cardFlyOutRotation = 12
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
