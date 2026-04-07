import Foundation
import SwiftUI

extension FlashcardsSessionController {
    func syncDisplayedCard(with sessionStore: FlashcardSessionStore) {
        displayedFlashCard = sessionStore.currentCard?.card(for: sessionStore.selectedDirection)
    }

    func resetTransientState(
        speechController: SpeechController,
        speaker: Speaker,
        dismissTypedAnswerFocus: () -> Void,
        clearDisplayedCard: Bool = false
    ) {
        dismissTypedAnswerFocus()
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        flashcardHistory = []
        lastResult = nil
        showingSolution = false
        isFlashcardFlipped = false
        resetCardFlyOut()
        speaker.stop()
        speechController.stopRecording()
        speechController.transcript = ""
        speechController.recordError = nil
        typedAnswer = ""
        hideTypedAnswerField()
        isMicPulseVisible = false
        if clearDisplayedCard {
            displayedFlashCard = nil
        }
    }

    func handleDisappear(
        speechController: SpeechController,
        speaker: Speaker,
        dismissTypedAnswerFocus: () -> Void
    ) {
        resetTransientState(
            speechController: speechController,
            speaker: speaker,
            dismissTypedAnswerFocus: dismissTypedAnswerFocus,
            clearDisplayedCard: true
        )
        speechController.deactivateAudioSession()
    }

    func handleAudioModeChange(
        isEnabled: Bool,
        speechController: SpeechController,
        speaker: Speaker
    ) {
        if !isEnabled {
            stopListeningForTyping(speechController: speechController, speaker: speaker)
        }
    }

    func scheduleNextPrompt(
        after delay: TimeInterval,
        sessionStore: FlashcardSessionStore,
        speechController: SpeechController
    ) {
        cancelPendingFeedback()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastResult = nil
            self.showingSolution = false
            self.isFlashcardFlipped = false
            speechController.transcript = ""
            self.typedAnswer = ""
            self.hideTypedAnswerField()

            if sessionStore.session?.isCompleted == true {
                return
            }
        }
        pendingFeedbackTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelPendingFeedback() {
        pendingFeedbackTask?.cancel()
        pendingFeedbackTask = nil
    }

    func resetCardFlyOut() {
        cardFlyOutOffset = 0
        cardFlyOutRotation = 0
        cardFlyOutOpacity = 1
    }

    func hideTypedAnswerField() {
        showingTypedAnswerInput = false
    }

    func stopListeningForTyping(
        speechController: SpeechController,
        speaker: Speaker
    ) {
        shouldEvaluateAfterStop = false
        if speechController.isRecording {
            speechController.stopRecording()
        }
        if speaker.isSpeaking {
            speaker.stop()
        }
        isMicPulseVisible = false
    }

    func pushCurrentFlashcardToHistory(
        revealingSolution: Bool,
        sessionStore: FlashcardSessionStore
    ) {
        guard let sessionSnapshot = sessionStore.session,
              let currentFlashCard else { return }

        let historyResult: ScoreResult?
        if revealingSolution {
            historyResult = ScoreResult(label: "Lösung", detail: currentFlashCard.answer)
        } else {
            historyResult = nil
        }

        flashcardHistory.append(
            HistoryEntry(
                sessionState: sessionSnapshot,
                lastResult: historyResult,
                showingSolution: revealingSolution,
                isFlashcardFlipped: revealingSolution
            )
        )
    }

    func restorePreviousFlashcard(
        sessionStore: FlashcardSessionStore,
        speechController: SpeechController,
        speaker: Speaker,
        dismissTypedAnswerFocus: () -> Void
    ) {
        guard let historyEntry = flashcardHistory.popLast() else { return }

        dismissTypedAnswerFocus()
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        speaker.stop()
        speechController.stopRecording()
        speechController.transcript = ""
        speechController.recordError = nil
        typedAnswer = ""
        hideTypedAnswerField()

        sessionStore.restoreSession(historyEntry.sessionState)
        syncDisplayedCard(with: sessionStore)
        lastResult = historyEntry.lastResult
        showingSolution = historyEntry.showingSolution
        resetCardFlyOut()

        if historyEntry.isFlashcardFlipped {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                isFlashcardFlipped = true
            }
        } else {
            isFlashcardFlipped = false
        }
    }
}

struct HistoryEntry {
    let sessionState: FlashcardSessionState
    let lastResult: ScoreResult?
    let showingSolution: Bool
    let isFlashcardFlipped: Bool
}
