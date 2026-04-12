import SwiftUI

extension TrainingView {
    func handleTrainingAppear() {
        triggerTrainingAudioPreparationIfNeeded()
        applyLaunchContextIfNeeded()
        if session.selectedTrainingListIDs.isEmpty {
            session.restoreSelectedListIDs()
        }
        refreshDictionaryTrainingListIfNeeded()
        ensureTrainingSelectionValidity()
        ensureDirectionValidity()
        // Only reset if not currently in a training session
        if !session.hasStartedTraining {
            resetTrainingSession()
        }
    }

    func handleTrainingDirectionChange() {
        // Only reset if still in setup (not during active training)
        if session.isShowingSetup {
            resetTrainingSession()
        }
    }

    func handleTrainingCardTypeChange() {
        guard session.isShowingSetup else { return }
        resetTrainingSession()
    }

    func handleTrainingListChange() {
        guard session.isShowingSetup else { return }
        refreshDictionaryTrainingListIfNeeded()
        ensureDirectionValidity()
        resetTrainingSession()
    }

    func handleDictionaryLearningLevelChange() {
        guard session.isShowingSetup else { return }
        refreshDictionaryTrainingListIfNeeded()
        ensureTrainingSelectionValidity()
        ensureDirectionValidity()
        resetTrainingSession()
    }

    func handleTrainingAppDirectionChange() {
        guard session.isShowingSetup else { return }
        refreshDictionaryTrainingListIfNeeded()
        ensureDirectionValidity()
        resetTrainingSession()
    }

    func handleTrainingCustomListsChange() {
        guard session.isShowingSetup else { return }
        ensureTrainingSelectionValidity()
        ensureDirectionValidity()
        resetTrainingSession()
    }

    func handleTrainingListPickerChange() {
        refreshDictionaryTrainingListIfNeeded()
    }

    func handleTrainingRecordingTransition(from wasRecording: Bool, to isRecording: Bool) {
        guard wasRecording, !isRecording, shouldEvaluateAfterStop else { return }
        shouldEvaluateAfterStop = false
        evaluateTranscript()
    }

    func handleTrainingRecordingPulseChange(_ isRecording: Bool) {
        isMicPulseVisible = isRecording
    }

    func handleTrainingSpeakerTransition(from wasSpeaking: Bool, to isSpeaking: Bool) {
        print("🔊 [SpeakerTransition] \(wasSpeaking) → \(isSpeaking)")
        guard wasSpeaking, !isSpeaking else { return }
        print("🔊 [SpeakerTransition] speaker finished → calling beginAutomaticListeningIfNeeded")
        beginAutomaticListeningIfNeeded()
    }

    func handleTypedAnswerFocusChange(_ isFocused: Bool) {
        if isFocused {
            stopListeningForTyping()
        }
    }

    func handleTrainingDisappear() {
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        speechController?.stopRecording()
        speechController?.deactivateAudioSession()
    }

    func triggerTrainingAudioPreparationIfNeeded() {
        guard !hasTriggeredAudioPreparation else { return }
        hasTriggeredAudioPreparation = true
        Task {
            await prepareTrainingAudioDependenciesIfNeeded()
        }
    }

    func prepareTrainingAudioDependenciesIfNeeded() async {
        guard speechController == nil || speaker == nil else { return }
        guard !isPreparingAudioDependencies else { return }
        isPreparingAudioDependencies = true
        await ensureAudioDependenciesReady()
        isPreparingAudioDependencies = false
    }
}
