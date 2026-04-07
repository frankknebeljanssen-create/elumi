import SwiftUI

extension TrainingView {
    func speakCurrentPrompt() {
        guard let currentCard else { return }
        stopListeningForTyping()
        guard isAudioModeEnabled else {
            showingTypedAnswerInput = true
            return
        }
        guard let speaker else {
            showingTypedAnswerInput = true
            return
        }
        speaker.speak(text: currentCard.prompt, languageCode: currentCard.promptLanguageCode)
    }

    func toggleRecording() {
        guard session.hasStartedTraining, currentCard != nil else { return }
        cancelPendingFeedback()
        typedAnswerFieldFocused = false

        guard let speechController else {
            Task {
                await prepareTrainingAudioDependenciesIfNeeded()
            }
            return
        }

        if speechController.isRecording {
            shouldEvaluateAfterStop = false
            speechController.stopRecording()
        } else {
            speaker?.stop()
            lastResult = nil
            typedAnswer = ""
            showingTypedAnswerInput = false
            shouldEvaluateAfterStop = true
            speechController.startRecording(localeIdentifier: localeIdentifierForRecognition)
        }
    }

    func evaluateTranscript() {
        evaluateResponse(speechController?.transcript ?? "")
    }

    func speakCurrentPromptAfterScreenUpdate(initialDelay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            await Task.yield()
            guard session.hasStartedTraining, currentCard != nil else { return }
            await prepareTrainingAudioDependenciesIfNeeded()
            speakCurrentPrompt()
        }
    }

    func beginAutomaticListeningIfNeeded() {
        guard session.hasStartedTraining, currentCard != nil else { return }
        guard isAudioModeEnabled, canUseSpeechRecognition else { return }
        guard !showingTypedAnswerInput, !typedAnswerFieldFocused else { return }
        guard let speechController else {
            Task {
                await prepareTrainingAudioDependenciesIfNeeded()
            }
            return
        }
        guard !speechController.isRecording else { return }
        shouldEvaluateAfterStop = true
        speechController.startRecording(localeIdentifier: localeIdentifierForRecognition)
    }

    func stopListeningForTyping() {
        shouldEvaluateAfterStop = false
        if speechController?.isRecording == true {
            speechController?.stopRecording()
        }
        speaker?.stop()
        isMicPulseVisible = false
    }

    func handleAudioModeChange(isEnabled: Bool) {
        if !isEnabled {
            stopListeningForTyping()
            showingTypedAnswerInput = true
        } else if session.hasStartedTraining, currentCard != nil, !showingTypedAnswerInput {
            speakCurrentPrompt()
        }
    }
}
