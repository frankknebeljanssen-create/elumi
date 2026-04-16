import SwiftUI
import AVFoundation

extension TrainingView {
    func dismissToHome() {
        resetTrainingSession()
        goHome()
    }

    /// TopBar-/Session-Back-Verhalten: Im aktiven Abfragemodus (nach „Los geht's")
    /// führt der Back-Button eine Ebene zurück zur Setup-/Listenauswahl-Card,
    /// NICHT komplett nach Home. Bei Verbformen wird weiterhin dismissed — dort
    /// gibt es eigene Reset/Setup-Flows und der User hat explizit gesagt, dass
    /// das aktuelle Verhalten passt.
    ///
    /// XP/Credits werden gleich wie bei `dismissTraining()` vergeben, damit der
    /// User nicht bestraft wird, wenn er zurück zum Setup springt statt zu Home.
    func handleTopBarBack() {
        let isInTrainingSession = !isVerbformsMode
            && (session.hasStartedTraining || !session.isShowingSetup)
        if isInTrainingSession {
            awardTrainingXPIfNeeded()
            resetTrainingSession()
        } else {
            // Auch im Verbformen-Flow: erst Reward (falls Fortschritt
            // vorhanden), dann dismiss. `awardVerbformsXPIfNeeded` ist idempotent.
            if isVerbformsMode {
                awardVerbformsXPIfNeeded()
            }
            dismiss()
        }
    }

    func dismissTraining() {
        awardTrainingXPIfNeeded()
        resetTrainingSession()
        dismiss()
    }

    /// Vergibt XP/Credits/Streak für die aktuelle Verbformen-Session über den
    /// zentralen `ProgressService`. Schutz via `sessionRewardConsumed` verhindert
    /// Mehrfach-Vergabe, wenn der Hook aus mehreren Back-Pfaden aufgerufen wird
    /// (Result-Screen, TopBar-Back). Speed-Round läuft als eigene Origin.
    ///
    /// Das berechnete `SessionRewardOutcome` wird in `verbformsSessionOutcome`
    /// abgelegt und ersetzt den bisherigen Zahlen-Result-Screen durch die
    /// einheitliche `SessionSummaryView`.
    func awardVerbformsXPIfNeeded() {
        guard !verbformsSession.sessionRewardConsumed else { return }
        let origin: LearningSession.Origin = verbformsSession.isSpeedRound ? .speedRound : .verbforms
        let learningSession = LearningSession(
            origin: origin,
            correctCount: verbformsSession.sessionCorrectCount,
            wrongCount: verbformsSession.sessionWrongCount,
            longestCombo: verbformsSession.sessionLongestCombo
        )
        guard learningSession.correctCount > 0 || learningSession.wrongCount > 0 else { return }
        verbformsSession.sessionRewardConsumed = true
        let outcome = ProgressService.shared.record(session: learningSession)
        verbformsSessionOutcome = outcome
        arcadeCredits = ProgressStore.shared.progress.arcadeCredits
    }

    /// XP, Credits und Streak werden über den zentralen `ProgressService`
    /// vergeben. Single Source of Truth, konsistent mit Karteikarten und Quiz.
    /// Schutz via `sessionRewardConsumed` gegen Mehrfach-Vergabe bei
    /// wiederholtem Aufruf aus verschiedenen Back-Pfaden.
    ///
    /// Das berechnete `SessionRewardOutcome` wird in `trainingSessionOutcome`
    /// abgelegt und triggert die einheitliche `SessionSummaryView`. Diese zeigt
    /// dem Nutzer XP-Aufschlüsselung, Credits, Level-Progress — analog zu den
    /// Karteikarten.
    func awardTrainingXPIfNeeded() {
        guard !session.sessionRewardConsumed else { return }
        // Speed Rounds fließen als eigene Origin; normales Training als
        // `.training`. Das Session-Minimum unterscheidet sich (siehe
        // `GamificationConfig.SessionMinimum`).
        let origin: LearningSession.Origin = session.isSpeedRound ? .speedRound : .training
        let learningSession = LearningSession(
            origin: origin,
            correctCount: session.sessionCorrectCount,
            wrongCount: session.sessionWrongCount,
            longestCombo: session.sessionLongestCombo
        )
        guard learningSession.correctCount > 0 || learningSession.wrongCount > 0 else { return }
        session.sessionRewardConsumed = true
        let outcome = ProgressService.shared.record(session: learningSession)
        trainingSessionOutcome = outcome
        arcadeCredits = ProgressStore.shared.progress.arcadeCredits
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
        showingVerbTranslation = false
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
