import Foundation
import SwiftUI

extension FlashcardsSessionController {
    func toggleRecording(
        sessionStore: FlashcardSessionStore,
        speechController: SpeechController,
        speaker: Speaker,
        dismissTypedAnswerFocus: () -> Void
    ) {
        guard sessionStore.hasActiveSession, currentFlashCard != nil else { return }
        cancelPendingFeedback()

        if speechController.isRecording {
            shouldEvaluateAfterStop = false
            speechController.stopRecording()
            return
        }

        stopListeningForTyping(speechController: speechController, speaker: speaker)
        hideTypedAnswerField()
        lastResult = nil
        showingSolution = false
        isFlashcardFlipped = false
        typedAnswer = ""
        shouldEvaluateAfterStop = true
        dismissTypedAnswerFocus()
        speechController.startRecording(localeIdentifier: sessionStore.selectedDirection.recognitionLocaleIdentifier)
    }

    func handleRecordingStateChange(
        wasRecording: Bool,
        isRecording: Bool,
        sessionStore: FlashcardSessionStore,
        speechController: SpeechController,
        speaker: Speaker,
        feedbackPlayer: FeedbackPlayer,
        dismissTypedAnswerFocus: () -> Void
    ) {
        if wasRecording, !isRecording, shouldEvaluateAfterStop {
            shouldEvaluateAfterStop = false
            evaluateResponse(
                speechController.transcript,
                sessionStore: sessionStore,
                speechController: speechController,
                speaker: speaker,
                feedbackPlayer: feedbackPlayer,
                dismissTypedAnswerFocus: dismissTypedAnswerFocus
            )
        }

        isMicPulseVisible = isRecording
    }

    func speakCurrentPrompt(
        speechController: SpeechController,
        speaker: Speaker,
        areSoundsEnabled: Bool
    ) {
        guard let currentFlashCard else { return }
        stopListeningForTyping(speechController: speechController, speaker: speaker)
        hideTypedAnswerField()
        guard areSoundsEnabled else { return }
        speaker.speak(text: currentFlashCard.prompt, languageCode: currentFlashCard.promptLanguageCode)
    }
}
