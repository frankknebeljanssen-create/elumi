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

    func beginAutomaticListeningIfNeeded(
        sessionStore: FlashcardSessionStore,
        speechController: SpeechController,
        speaker: Speaker,
        areSoundsEnabled: Bool,
        dismissTypedAnswerFocus: () -> Void
    ) {
        guard sessionStore.hasActiveSession, currentFlashCard != nil else { return }
        guard areSoundsEnabled else { return }
        guard speechController.authorizationStatus != .denied,
              speechController.authorizationStatus != .restricted else { return }
        guard !showingTypedAnswerInput, !isFlashcardFlipped else { return }
        guard !speechController.isRecording else { return }

        shouldEvaluateAfterStop = true
        dismissTypedAnswerFocus()
        speechController.startRecording(localeIdentifier: sessionStore.selectedDirection.recognitionLocaleIdentifier)
    }

    func speakCurrentPrompt(
        speechController: SpeechController,
        speaker: Speaker,
        areSoundsEnabled: Bool
    ) {
        guard let currentFlashCard else {
            print("🔊 [FC-Speak] ❌ no currentFlashCard")
            return
        }
        stopListeningForTyping(speechController: speechController, speaker: speaker)
        hideTypedAnswerField()
        guard areSoundsEnabled else {
            print("🔊 [FC-Speak] ❌ sounds disabled")
            return
        }
        print("🔊 [FC-Speak] ✅ speaking: \(currentFlashCard.prompt)")
        speaker.speak(text: currentFlashCard.prompt, languageCode: currentFlashCard.promptLanguageCode)
    }
}
