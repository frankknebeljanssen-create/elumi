import SwiftUI

extension TrainingView {
    func dismissToHome() {
        resetTrainingSession()
        goHome()
    }

    func returnToTrainingSetup() {
        resetTrainingSession()
        session.returnToSetup()
    }

    func applyLaunchContextIfNeeded() {
        session.applyLaunchContextIfNeeded(
            launchContext,
            listStore: listStore,
            updateAppDirectionRaw: { selectedAppDirectionRaw = $0 }
        )
    }

    func ensureTrainingSelectionValidity() {
        session.ensureTrainingSelectionValidity(
            listStore: listStore,
            launchContext: launchContext,
            selectedAppDirection: selectedAppDirection
        )
    }

    func ensureDirectionValidity() {
        session.ensureDirectionValidity(
            listStore: listStore,
            launchContext: launchContext,
            selectedAppDirection: selectedAppDirection,
            updateAppDirectionRaw: { selectedAppDirectionRaw = $0 }
        )
    }

    func refreshDictionaryTrainingListIfNeeded() {
        session.refreshDictionaryTrainingListIfNeeded(
            launchContext: launchContext,
            listStore: listStore,
            selectedAppDirection: selectedAppDirection,
            updateAppDirectionRaw: { selectedAppDirectionRaw = $0 }
        )
    }

    func resetTrainingSession() {
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        session.resetTrainingSessionState()
        lastResult = nil
        speaker?.stop()
        speechController?.stopRecording()
        speechController?.transcript = ""
        speechController?.recordError = nil
        typedAnswer = ""
        showingTypedAnswerInput = !isAudioModeEnabled
        typedAnswerFieldFocused = false
        isMicPulseVisible = false
    }

    func startTraining() {
        ensureTrainingSelectionValidity()
        guard session.startTraining(
            listStore: listStore,
            launchContext: launchContext,
            selectedAppDirection: selectedAppDirection
        ) else {
            resetTrainingSession()
            return
        }
        showingTypedAnswerInput = false
        typedAnswerFieldFocused = false
        speakCurrentPromptAfterScreenUpdate(initialDelay: 0.12)
    }

    func loadNextTrainingCard() {
        speechController?.transcript = ""
        speechController?.recordError = nil
        lastResult = nil
        typedAnswer = ""
        showingTypedAnswerInput = false
        typedAnswerFieldFocused = false
        session.loadNextTrainingCard()
    }

    func revealSolution() {
        guard let currentCard, canRevealSolution else { return }
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        speechController?.stopRecording()
        speechController?.transcript = ""
        speechController?.recordError = nil
        typedAnswerFieldFocused = false
        lastResult = ScoreResult(label: "Lösung", detail: currentCard.answer)
    }

    func repeatCurrentPrompt() {
        guard let currentCard else { return }
        scheduleFeedbackTask(after: 0.35) {
            guard isShowing(currentCard) else { return }
            speakCurrentPromptAfterScreenUpdate(initialDelay: 0.02)
        }
    }

    func scheduleNextCard() {
        guard let currentCard else { return }
        scheduleFeedbackTask(after: 0.55) {
            guard isShowing(currentCard) else { return }
            loadNextTrainingCard()
            if session.hasStartedTraining {
                speakCurrentPromptAfterScreenUpdate(initialDelay: 0.06)
            }
        }
    }

    func scheduleFeedbackTask(after delay: TimeInterval, action: @escaping () -> Void) {
        cancelPendingFeedback()
        let workItem = DispatchWorkItem(block: action)
        pendingFeedbackTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelPendingFeedback() {
        pendingFeedbackTask?.cancel()
        pendingFeedbackTask = nil
    }

    func isShowing(_ card: FlashCard) -> Bool {
        guard let currentCard else { return false }
        return isSameTrainingCard(currentCard, card)
    }

    func isSameTrainingCard(_ lhs: FlashCard, _ rhs: FlashCard) -> Bool {
        lhs.prompt == rhs.prompt
            && lhs.answer == rhs.answer
            && lhs.category == rhs.category
    }
}
