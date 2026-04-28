import Foundation
import SwiftUI

extension FlashcardsSessionController {
    /// **Peek-aware revealSolution** (User-Revision 2026-04-22):
    /// Manuelles Umdrehen der Karte (Peek) wird als „nicht gekonnt"
    /// gewertet. Solange `peekedCurrentCardID` diese CardID markiert,
    /// kann die Karte in diesem Durchgang **nicht** mehr als
    /// gemeistert zählen — selbst wenn sie danach korrekt
    /// beantwortet wird. Die korrekte Antwort schiebt sie ans Ende
    /// des Stapels (nochmal drankommen).
    func revealSolution(
        sessionStore: FlashcardSessionStore? = nil,
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

        // **Peek-Protection**: Flag setzen + Mastery zurück auf 0.
        // Nur beim ERSTEN Flip dieser Karte — wiederholtes
        // Zurück-und-wieder-Aufdecken zählt als ein Peek.
        if let sessionStore,
           let currentCardID = sessionStore.session?.currentCardID,
           peekedCurrentCardID != currentCardID {
            peekedCurrentCardID = currentCardID
            sessionStore.resetMasteryDueToPeek(cardID: currentCardID)
            triggerPeekToast()
        }
    }

    /// Kurzer User-Feedback-Toast unter der Karte. 0,3 s Fade-in,
    /// 1,5 s sichtbar, 0,3 s Fade-out.
    private func triggerPeekToast() {
        withAnimation(.easeIn(duration: 0.3)) {
            peekToastVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                self.peekToastVisible = false
            }
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
