import SwiftUI
import AVFoundation

extension TrainingView {
    func dismissToHome() {
        resetTrainingSession()
        goHome()
    }

    func returnToTrainingSetup() {
        // Award XP for training session (2 XP per correct answer, not speed round)
        if !session.isSpeedRound, trainingCorrectCount > 0 {
            let earnedXP = trainingCorrectCount * 2
            let previousXP = UserDefaults.standard.integer(forKey: appElumiXPKey)
            let newXP = previousXP + earnedXP
            UserDefaults.standard.set(newXP, forKey: appElumiXPKey)
            let xpBonusCredits = ArcadeCreditSystem.bonusCreditsFromXP(previousXP: previousXP, newXP: newXP)
            if xpBonusCredits > 0 {
                arcadeCredits += xpBonusCredits
            }
        }
        trainingCorrectCount = 0
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
        let trace = Thread.callStackSymbols.prefix(8).joined(separator: "\n")
        print("🏋️ [Training] ⚠️ resetTrainingSession called from:\n\(trace)")
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
        articleAnswer = nil
        articleLocked = false
        showingArticleTranslation = false
        verbMCOptions = []
        verbMCSelected = nil
        verbMCLocked = false
        speedCountdown = nil
        stopSpeedRoundTimer()
    }

    func startSpeedRoundTimer() {
        session.speedRoundScore = 0
        session.speedRoundTimeRemaining = 45
        session.speedRoundTimer?.invalidate()
        session.speedRoundTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak session] _ in
            Task { @MainActor in
                guard let session else { return }
                session.speedRoundTimeRemaining -= 1
                if session.speedRoundTimeRemaining <= 5, session.speedRoundTimeRemaining > 0 {
                    self.feedbackPlayer.playToggle()
                }
                if session.speedRoundTimeRemaining <= 0 {
                    self.feedbackPlayer.playRoundClear()
                    session.speedRoundTimer?.invalidate()
                    session.speedRoundTimer = nil
                }
            }
        }
    }

    func stopSpeedRoundTimer() {
        session.speedRoundTimer?.invalidate()
        session.speedRoundTimer = nil
    }

    func startTraining() {
        print("🏋️ [Training] startTraining mode=\(session.trainingMode) activeItems=\(activeItems.count) selectedIDs=\(session.selectedTrainingListIDs.count) verbSetSize=\(StandardVocabularyLoader.verbSet.count)")
        ensureTrainingSelectionValidity()
        guard session.startTraining(
            listStore: listStore,
            launchContext: launchContext,
            selectedAppDirection: selectedAppDirection
        ) else {
            print("🏋️ [Training] ❌ startTraining failed")
            resetTrainingSession()
            return
        }
        showingTypedAnswerInput = false
        typedAnswerFieldFocused = false
        if session.isSpeedRound {
            // 3-2-1 countdown before starting
            speedCountdown = 3
            feedbackPlayer.playToggle()
            scheduleFeedbackTask(after: 1.0) {
                speedCountdown = 2
                feedbackPlayer.playToggle()
                scheduleFeedbackTask(after: 1.0) {
                    speedCountdown = 1
                    feedbackPlayer.playToggle()
                    scheduleFeedbackTask(after: 1.0) {
                        speedCountdown = nil
                        feedbackPlayer.playLaunch()
                        startSpeedRoundTimer()
                        if isVerbMode { prepareVerbMCOptions() }
                    }
                }
            }
            return
        }
        if isArticleMode {
            return
        }
        if isVerbMode {
            prepareVerbMCOptions()
            return
        }
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
