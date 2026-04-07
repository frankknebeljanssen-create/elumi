import Foundation
import SwiftUI

extension FlashcardsSessionController {
    func revealSolution(
        speechController: SpeechController,
        dismissTypedAnswerFocus: () -> Void
    ) {
        guard let currentFlashCard else { return }
        dismissTypedAnswerFocus()
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        speechController.stopRecording()
        speechController.transcript = ""
        typedAnswer = ""
        hideTypedAnswerField()
        lastResult = ScoreResult(label: "Lösung", detail: currentFlashCard.answer)
        showingSolution = true
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            isFlashcardFlipped = true
        }
    }

    func flipBackToFront(dismissTypedAnswerFocus: () -> Void) {
        dismissTypedAnswerFocus()
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            isFlashcardFlipped = false
        }
        showingSolution = false
        lastResult = nil
    }

    func skipCard(
        sessionStore: FlashcardSessionStore,
        speechController: SpeechController,
        speaker: Speaker,
        areSoundsEnabled: Bool,
        dismissTypedAnswerFocus: () -> Void
    ) {
        guard sessionStore.hasActiveSession, currentFlashCard != nil else { return }
        dismissTypedAnswerFocus()
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        speechController.stopRecording()
        speechController.transcript = ""
        typedAnswer = ""
        hideTypedAnswerField()
        lastResult = nil
        showingSolution = false
        isFlashcardFlipped = false
        pushCurrentFlashcardToHistory(revealingSolution: true, sessionStore: sessionStore)
        sessionStore.markWrong()
        syncDisplayedCard(with: sessionStore)
        speakCurrentPrompt(
            speechController: speechController,
            speaker: speaker,
            areSoundsEnabled: areSoundsEnabled
        )
    }

    @discardableResult
    func showTypedAnswerField(isSessionReady: Bool) -> Bool {
        guard isSessionReady else { return false }
        showingTypedAnswerInput = true
        showingSolution = false
        isFlashcardFlipped = false
        return true
    }
}
