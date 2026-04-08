import SwiftUI

extension TrainingView {
    func speakCurrentPrompt() {
        guard let currentCard else {
            print("🔊 [Speak] ❌ no currentCard")
            return
        }
        stopListeningForTyping()
        guard isAudioModeEnabled else {
            print("🔊 [Speak] ❌ audioMode disabled (sounds=\(feedbackPlayer.areSoundsEnabled))")
            showingTypedAnswerInput = true
            return
        }
        guard let speaker else {
            print("🔊 [Speak] ❌ no speaker (runtimeSpeaker=\(runtimeSpeaker != nil))")
            showingTypedAnswerInput = true
            return
        }
        print("🔊 [Speak] ✅ speaking: \(currentCard.prompt)")
        lastResult = nil
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
        let started = session.hasStartedTraining
        let hasCard = currentCard != nil
        let audioOn = isAudioModeEnabled
        let speechOK = canUseSpeechRecognition
        let typing = showingTypedAnswerInput
        let focused = typedAnswerFieldFocused
        let hasController = speechController != nil
        let recording = speechController?.isRecording == true
        let authStatus = speechController?.authorizationStatus.rawValue ?? -1

        print("🎤 [AutoListen] started=\(started) card=\(hasCard) audio=\(audioOn) speechPerm=\(speechOK)(auth=\(authStatus)) typing=\(typing) focused=\(focused) controller=\(hasController) recording=\(recording)")

        guard started, hasCard else { return }
        guard audioOn, speechOK else {
            print("🎤 [AutoListen] ❌ blocked: audioMode=\(audioOn) speechPerm=\(speechOK)")
            return
        }
        guard !typing, !focused else {
            print("🎤 [AutoListen] ❌ blocked: typing=\(typing) focused=\(focused)")
            return
        }
        guard let speechController else {
            print("🎤 [AutoListen] ❌ no speechController, preparing...")
            Task {
                await prepareTrainingAudioDependenciesIfNeeded()
            }
            return
        }
        guard !recording else { return }
        print("🎤 [AutoListen] ✅ STARTING recording")
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
