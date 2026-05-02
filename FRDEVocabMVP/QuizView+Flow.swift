import SwiftUI

extension QuizView {
    func toggleListSelection(_ id: UUID) {
        if session.selectedListIDs.contains(id) {
            if session.selectedListIDs.count > 1 {
                session.selectedListIDs.remove(id)
            }
        } else {
            session.selectedListIDs.insert(id)
        }
    }

    func startQuiz() {
        print("🧩 [Quiz] startQuiz called, candidates=\(session.cachedCandidates.count), prepared=\(session.preparedQuestions.count)")
        // Launch-Sound beim Session-Start — systemweit identisch zum
        // Speed-Round-Start in Verbformen.
        feedbackPlayer.playLaunch()
        session.syncSelectedLists(availableLists: availableQuizLists)
        session.startQuiz(direction: selectedAppDirection)
        awardedHearts = 0
        awardedWaterfloh = 0
        awardedAlgenkugel = 0
        unlockedRewardLevels = []
        didPersistHearts = false
        quizSessionOutcome = nil
        resetPerQuestionState()
    }

    func submitMultipleChoice(_ option: String, for question: QuizMultipleChoiceQuestion) {
        guard !multipleChoiceLocked else { return }
        multipleChoiceLocked = true
        selectedMultipleChoiceOption = option

        let isCorrect = normalizedLookupText(option) == normalizedLookupText(question.correctAnswer)
        if isCorrect {
            feedbackPlayer.playStudySuccess()
        } else {
            feedbackPlayer.playStudyError()
        }

        scheduleAdvance(after: 0.95) {
            completeCurrentQuestion(correct: isCorrect)
        }
    }

    func submitTyping(for question: QuizTypingQuestion) {
        guard !typingLocked else { return }
        let userInput = typingInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !userInput.isEmpty else { return }
        typingLocked = true
        isTypingFieldFocused = false

        let got = normalizedLookupText(userInput)
        let expected = normalizedLookupText(question.correctAnswer)
        let isCorrect = got == expected
            || levenshteinRatio(got, expected) <= 0.25
            || got.contains(expected)
            || expected.contains(got)

        if isCorrect {
            feedbackPlayer.playStudySuccess()
        } else {
            feedbackPlayer.playStudyError()
            typingShowCorrectAnswer = question.correctAnswer
        }

        scheduleAdvance(after: 1.2) {
            completeCurrentQuestion(correct: isCorrect)
        }
    }

    private func levenshteinRatio(_ lhs: String, _ rhs: String) -> Double {
        let a = Array(lhs), b = Array(rhs)
        guard !a.isEmpty, !b.isEmpty else { return a.isEmpty && b.isEmpty ? 0 : 1 }
        var dist = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { dist[i][0] = i }
        for j in 0...b.count { dist[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                dist[i][j] = a[i-1] == b[j-1]
                    ? dist[i-1][j-1]
                    : min(dist[i-1][j], dist[i][j-1], dist[i-1][j-1]) + 1
            }
        }
        return Double(dist[a.count][b.count]) / Double(max(a.count, b.count))
    }

    func updateHoveredAnswer(for promptID: UUID) {
        selectedPromptID = promptID
        hoveredAnswerID = droppedAnswerID(for: promptID)
    }

    func finishDrag(for promptID: UUID, in question: QuizMatchingQuestion) {
        selectedPromptID = promptID
        selectedAnswerID = droppedAnswerID(for: promptID)
        hoveredAnswerID = selectedAnswerID

        guard selectedAnswerID != nil else {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                dragOffset = .zero
            }
            draggingPromptID = nil
            selectedPromptID = nil
            return
        }

        evaluateMatchingSelection(in: question)
    }

    func droppedAnswerID(for promptID: UUID) -> UUID? {
        guard let promptFrame = promptFrames[promptID] else { return nil }
        let draggedCenter = CGPoint(
            x: promptFrame.midX + dragOffset.width,
            y: promptFrame.midY + dragOffset.height
        )

        return answerFrames.first(where: { candidateID, frame in
            !matchedPairIDs.contains(candidateID) && frame.contains(draggedCenter)
        })?.key
    }

    func selectPrompt(_ id: UUID) {
        guard !matchedPairIDs.contains(id) else { return }
        selectedPromptID = id
        if let selectedAnswerID, selectedAnswerID == id {
            selectedPromptID = nil
            self.selectedAnswerID = nil
        }
    }

    func selectAnswer(_ id: UUID, in question: QuizMatchingQuestion) {
        guard !matchedPairIDs.contains(id) else { return }
        selectedAnswerID = id
        evaluateMatchingSelection(in: question)
    }

    func evaluateMatchingSelection(in question: QuizMatchingQuestion) {
        guard let selectedPromptID, let selectedAnswerID else { return }

        if selectedPromptID == selectedAnswerID {
            feedbackPlayer.playStudySuccess()
            let snapOffset = matchingSnapOffset(for: selectedPromptID, answerID: selectedAnswerID)

            withAnimation(.spring(response: 0.22, dampingFraction: 0.88)) {
                dragOffset = snapOffset
            }

            scheduleAdvance(after: 0.22) {
                matchedPairIDs.insert(selectedPromptID)
                draggingPromptID = nil
                dragOffset = .zero
                self.selectedPromptID = nil
                self.selectedAnswerID = nil
                hoveredAnswerID = nil

                // Wenn alle Paare gelegt sind, zur nächsten Frage weiter.
                // **Nicht** scheduleAdvance nutzen — ein nachfolgender
                // Gesten-Cancel (oder ein erneuter scheduleAdvance-Call
                // aus einem drag-released-Event) hätte sonst den
                // finalen Complete-Call weggecancelt → Screen blieb
                // stehen. Direkter asyncAfter-Call ist unkündbar.
                if matchedPairIDs.count == question.pairs.count {
                    let isCorrect = !matchingHadMistake
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
                        completeCurrentQuestion(correct: isCorrect)
                    }
                }
            }
        } else {
            feedbackPlayer.playStudyError()
            matchingHadMistake = true
            flashingPromptID = selectedPromptID
            flashingAnswerID = selectedAnswerID

            withAnimation(.easeOut(duration: 0.14)) {
                dragOffset = CGSize(width: dragOffset.width * 0.25, height: dragOffset.height * 0.25)
            }

            scheduleAdvance(after: 0.5) {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                    dragOffset = .zero
                }
                draggingPromptID = nil
                flashingPromptID = nil
                flashingAnswerID = nil
                hoveredAnswerID = nil
                self.selectedPromptID = nil
                self.selectedAnswerID = nil
            }
        }
    }

    func completeCurrentQuestion(correct: Bool) {
        resetPerQuestionState()
        session.completeCurrentQuestion(correct: correct)

        // **Stufe 4b-3 (2026-05-02, Branch `feature/training-session-flow`)** —
        // Soft-Cutoff-Force-Done für den Chain-Timer. Wenn der User
        // auf einer Chain-Step-Quiz-Session sitzt UND der Chain-Timer
        // im `TrainingChainStore` schon abgelaufen ist, schließen wir
        // das Quiz HIER ab — nach kompletter Eval der gerade
        // abgeschickten Antwort (R7-Schutz: alle 4(+1) Submit-Pfade —
        // MC / Typing / Matching / FillBlanks / Combo-Verben — laufen
        // durch ihren jeweiligen `scheduleAdvance(after:)`-Callback,
        // erst dort fällt `completeCurrentQuestion(correct:)`. Eval-
        // Audio + Animation + answeredResults + Lernstatus + Streak +
        // Snapshot sind beim Eintritt in diesen Wrapper alle
        // geschrieben). Statt zur nächsten Frage zu wechseln, springen
        // wir direkt auf den Result-Screen mit dem Stufe-3-Chain-
        // aware-CTA. R9 (Parallel-Timer): N/A — Quiz hat keinen
        // Mode-Split (kein Speed Round, kein Üben/Lernen).
        if TrainingChainStore.shared.timerExpired, !session.isShowingResult {
            forceQuizDoneFromChainTimer()
            return
        }
    }

    /// **Stufe 4b-3 (2026-05-02)** — Forciert das Quiz-Session-Ende
    /// durch den Chain-Timer-Soft-Cutoff. Setzt `session.isShowingResult
    /// = true` + räumt den Resume-Snapshot ab — exakt dieselben
    /// Mutationen wie der natürliche „letzte Frage"-Pfad in
    /// `QuizSessionController.completeCurrentQuestion(correct:)`
    /// (Z. 24-31). Direkt im Anschluss laufen `prepareQuizRewards()` +
    /// `persistHeartsIfNeeded()` synchron im Helper, damit
    /// `quizSessionOutcome` (gespeist aus
    /// `ProgressService.shared.record(...)`) garantiert vor dem ersten
    /// Render des Result-Screens gesetzt ist. Beide Reward-Helper
    /// haben eigene Idempotenz-Guards (`didPersistHearts`,
    /// `session.sessionRewardConsumed`) — der nachträgliche natürliche
    /// Trigger via `onChange(of: isShowingResult)` + Result-View-
    /// `onAppear` ist damit ein safe-no-op. Idempotent gegen Re-Call
    /// während `isShowingResult` schon true.
    func forceQuizDoneFromChainTimer() {
        guard !session.isShowingResult else { return }
        session.isShowingResult = true
        QuizSessionResumeStore.clear()
        prepareQuizRewards()
        persistHeartsIfNeeded()
        #if DEBUG
        print("🛑 [Quiz] Force-Done via chain-timer-soft-cutoff")
        #endif
    }

    func prepareQuizRewards() {
        // Nur noch für die Elumi-spezifischen Hearts-Rewards zuständig —
        // der XP-Teil läuft vollständig über `ProgressService`. Die Bonus-
        // XP aus dem alten System (Streak-Multiplier, Perfect-Bonus) würden
        // sonst parallel zur neuen SessionSummaryView doppelt erscheinen.
        let rewardOutcome = computeElumiRewardOutcome(
            baseWorms: correctCount,
            baseXP: 0,
            isPerfectLesson: isPerfectQuiz,
            currentXP: collectedXP,
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            lastRewardDayIndex: lastRewardDayIndex
        )

        awardedHearts = rewardOutcome.worms
        awardedWaterfloh = rewardOutcome.waterfloh
        awardedAlgenkugel = rewardOutcome.algenkugel
        unlockedRewardLevels = rewardOutcome.unlockedLevels
        if totalRewardCount > 0 {
            feedbackPlayer.playStudyAchievement()
        }
    }

    func persistHeartsIfNeeded() {
        guard !didPersistHearts else { return }
        // 1) Elumi-spezifische Rewards (Worms/Waterfloh/Algenkugel) bleiben
        //    über die alte Reward-Engine — hängen an der Hearts-Sammlung
        //    und Level-Unlock-Logik. `baseXP = 0` sperrt den parallelen
        //    XP-Pfad; XP läuft ausschließlich über `ProgressService`.
        let rewardOutcome = computeElumiRewardOutcome(
            baseWorms: correctCount,
            baseXP: 0,
            isPerfectLesson: isPerfectQuiz,
            currentXP: collectedXP,
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            lastRewardDayIndex: lastRewardDayIndex
        )

        collectedWorms += rewardOutcome.worms
        collectedWaterfloh += rewardOutcome.waterfloh
        collectedAlgenkugel += rewardOutcome.algenkugel
        lastRewardDayIndex = rewardOutcome.lastRewardDayIndex
        didPersistHearts = true

        // 2) XP + Streak + Credits über den neuen zentralen ProgressService.
        //    Single Source of Truth: konsistente Belohnung über alle Module.
        guard !session.sessionRewardConsumed else { return }
        let learningSession = LearningSession(
            origin: .quiz,
            correctCount: correctCount,
            wrongCount: wrongCount,
            longestCombo: session.sessionLongestCombo
        )
        session.sessionRewardConsumed = true
        let outcome = ProgressService.shared.record(session: learningSession)
        quizSessionOutcome = outcome
        // @AppStorage-Spiegel aktualisieren, damit Views die auf den Legacy-
        // Keys lesen (z. B. HomeView) sofort reaktiv sind.
        collectedXP = ProgressStore.shared.progress.totalXP
        currentStreak = ProgressStore.shared.progress.currentStreak
        bestStreak = ProgressStore.shared.progress.bestStreak
        arcadeCredits = ProgressStore.shared.progress.arcadeCredits
    }

    func resetPerQuestionState() {
        cancelAdvanceTask()
        selectedMultipleChoiceOption = nil
        multipleChoiceLocked = false
        selectedPromptID = nil
        selectedAnswerID = nil
        matchedPairIDs = []
        matchingHadMistake = false
        fillBlanksSelected = nil
        fillBlanksLocked = false
        fillBlanksHadMistake = false
        fillBlanksWrongOptions = []
        fillBlanksFlashWrong = nil
        comboSelectedVerbID = nil
        comboMatchedIDs = []
        comboHadMistake = false
        comboFlashVerbID = nil
        comboFlashNounID = nil
        flashingPromptID = nil
        flashingAnswerID = nil
        draggingPromptID = nil
        dragOffset = .zero
        hoveredAnswerID = nil
        answerFrames = [:]
        promptFrames = [:]
        typingInput = ""
        typingLocked = false
        typingShowCorrectAnswer = nil
        isTypingFieldFocused = false
    }

    func submitFillBlanks(for question: QuizFillBlanksQuestion) {
        guard let selected = fillBlanksSelected, !fillBlanksLocked else { return }
        let isCorrect = selected.lowercased() == question.correctAnswer.lowercased()

        if isCorrect {
            fillBlanksLocked = true
            feedbackPlayer.playStudySuccess()
            scheduleAdvance(after: 0.8) {
                completeCurrentQuestion(correct: !fillBlanksHadMistake)
            }
        } else {
            feedbackPlayer.playStudyError()
            fillBlanksHadMistake = true
            fillBlanksWrongOptions.insert(selected)
            fillBlanksFlashWrong = selected
            fillBlanksSelected = nil
            scheduleAdvance(after: 0.6) {
                fillBlanksFlashWrong = nil
            }
        }
    }

    func matchingSnapOffset(for promptID: UUID, answerID: UUID) -> CGSize {
        guard let promptFrame = promptFrames[promptID],
              let answerFrame = answerFrames[answerID] else {
            return dragOffset
        }

        return CGSize(
            width: answerFrame.midX - promptFrame.midX,
            height: answerFrame.midY - promptFrame.midY
        )
    }

    func scheduleAdvance(after delay: TimeInterval, action: @escaping () -> Void) {
        cancelAdvanceTask()
        let workItem = DispatchWorkItem(block: action)
        advanceTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelAdvanceTask() {
        advanceTask?.cancel()
        advanceTask = nil
    }

    func resetQuizToSetup() {
        cancelAdvanceTask()
        session.resetToSetup()
        awardedHearts = 0
        awardedWaterfloh = 0
        awardedAlgenkugel = 0
        unlockedRewardLevels = []
        didPersistHearts = false
        quizSessionOutcome = nil
        resetPerQuestionState()
    }

    func dismissToHome() {
        resetQuizToSetup()
        goHome()
    }

    func handleBackNavigation() {
        // Im aktiven Abfragemodus zurück zur Listenauswahl/Setup-Card statt Home.
        // Result-Screen und Setup-Screen dismissen weiterhin wie bisher.
        let isInQuizSession = !session.questions.isEmpty && !session.isShowingResult

        // **Chain-Mode Back-Chevron (2026-05-02)** — im Chain-Mode
        // führt der Back-Chevron immer zum Pre-Screen (NavigationStack-
        // Pop), unabhängig von Quiz-Session-Phase. `resetQuizToSetup()`
        // würde sonst die Setup-Card mit Anzahl-Fragen-Slider zeigen
        // (Setup-Skip-Verstoß). `cancelAdvanceTask()` stoppt einen
        // ggf. laufenden Eval-Animation-Tick, damit kein delayed
        // `completeCurrentQuestion`-Call nach Route-Pop noch State
        // mutiert.
        if launchContext?.chainContext != nil {
            cancelAdvanceTask()
            dismiss()
            return
        }

        if isInQuizSession {
            resetQuizToSetup()
        } else {
            resetQuizToSetup()
            dismiss()
        }
    }

}
