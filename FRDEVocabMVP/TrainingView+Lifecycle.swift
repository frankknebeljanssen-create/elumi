import SwiftUI

extension TrainingView {
    func handleTrainingAppear() {
        triggerTrainingAudioPreparationIfNeeded()
        applyLaunchContextIfNeeded()
        refreshDictionaryTrainingListIfNeeded()
        ensureTrainingSelectionValidity()
        ensureDirectionValidity()
        resetTrainingSession()
    }

    func handleTrainingDirectionChange() {
        resetTrainingSession()
    }

    func handleTrainingCardTypeChange() {
        resetTrainingSession()
    }

    func handleTrainingListChange() {
        refreshDictionaryTrainingListIfNeeded()
        ensureDirectionValidity()
        resetTrainingSession()
    }

    func handleDictionaryLearningLevelChange() {
        refreshDictionaryTrainingListIfNeeded()
        ensureTrainingSelectionValidity()
        ensureDirectionValidity()
        resetTrainingSession()
    }

    func handleTrainingAppDirectionChange() {
        refreshDictionaryTrainingListIfNeeded()
        ensureDirectionValidity()
        resetTrainingSession()
    }

    func handleTrainingCustomListsChange() {
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
        guard wasSpeaking, !isSpeaking else { return }
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
