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
        appDebugLog("🧩 [Quiz] startQuiz called, candidates=\(session.cachedCandidates.count), prepared=\(session.preparedQuestions.count)")
        // Launch-Sound beim Session-Start — systemweit identisch zum
        // Speed-Round-Start in Verbformen.
        // **Daily Drop Modul 2.12 (2026-05-23)** — im Count-Modus (Daily Drop)
        // stumm: der Quiz-Step wird nahtlos per chainAdvance erreicht, der
        // Start-Sound bei jedem Step-Wechsel wirkt wie ein störender
        // Übergangs-„Toast"-Ton (User-Befund; der in 2.10 geflaggte, aber
        // noch nicht stummgeschaltete `playLaunch`). Normales Quiz +
        // Zeit-Chain + isolierter Modul-1-Test (kein chainContext): bleibt.
        if !isCountChainStep {
            feedbackPlayer.playLaunch()
        }
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

        // **Daily Drop Modul 2.12 (2026-05-23)** — Count-Modus: kein
        // Auto-Advance. Antwort-Feedback (grün/rot Chips) bleibt sichtbar,
        // bis der User „Weiter" tappt (Anton-Stil). Gewertet + advanced
        // wird erst im Weiter-Tap (`completeCurrentQuestion`). Normales
        // Quiz/Zeit-Chain: 2.6-Auto-Advance-Delay wie bisher.
        if isCountChainStep {
            quizPendingCorrect = isCorrect
            quizAwaitingWeiter = true
        } else {
            scheduleAdvance(after: 0.95) {
                completeCurrentQuestion(correct: isCorrect)
            }
        }
    }

    func submitTyping(for question: QuizTypingQuestion) {
        guard !typingLocked else { return }
        let userInput = typingInput.trimmingCharacters(in: .whitespacesAndNewlines)
        // **Daily Drop Modul 2.12 (2026-05-23)** — leere Eingabe wird in
        // ALLEN Modi ignoriert: ohne Inhalt kein Check. Im Count-Modus
        // bleibt „Weiter" dadurch gedimmt, bis tatsächlich etwas eingegeben
        // und geprüft wurde (User-Spec).
        guard !userInput.isEmpty else { return }
        typingLocked = true
        isTypingFieldFocused = false

        let got = normalizedLookupText(userInput)
        let expected = normalizedLookupText(question.correctAnswer)
        // **Bug #4 Fix (2026-05-23)** — geteilter `approximateAnswerMatch`
        // (längen-geschützter Substring) statt der vorher inline-duplizierten
        // Kette mit nacktem `contains`. Verhindert, dass z. B. nur „das" als
        // „das schwimmbad" durchrutscht.
        let isCorrect = approximateAnswerMatch(got: got, expected: expected)

        if isCorrect {
            feedbackPlayer.playStudySuccess()
        } else {
            feedbackPlayer.playStudyError()
            typingShowCorrectAnswer = question.correctAnswer
        }

        // Count-Modus: Feedback halten bis „Weiter" (siehe submitMultipleChoice).
        if isCountChainStep {
            quizPendingCorrect = isCorrect
            quizAwaitingWeiter = true
        } else {
            scheduleAdvance(after: 1.2) {
                completeCurrentQuestion(correct: isCorrect)
            }
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
                    // **Daily Drop Modul 2.12 (2026-05-23)** — Matching zählt
                    // als GENAU 1 Übung (1 Tick). `correct = !matchingHadMistake`:
                    // grünes Segment nur ohne Fehlversuch, sonst rot. Im
                    // Count-Modus kein Auto-Advance — Feedback (alle Paare grün)
                    // bleibt, der externe „Weiter"-Button löst aus.
                    let isCorrect = !matchingHadMistake
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.72) {
                        if isCountChainStep {
                            quizPendingCorrect = isCorrect
                            quizAwaitingWeiter = true
                        } else {
                            completeCurrentQuestion(correct: isCorrect)
                        }
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
        // **Modal-Race-Fix 2026-05-02** — Modal-Visibility hat
        // Vorrang. Solange `cutoffModalVisible = true` ist, soll der
        // User explizit per CTA wählen (Modal-„Jetzt weiter" ruft
        // `forceQuizDoneFromChainTimer` über den Force-Advance-
        // Handler-Pfad). Implizite Pre-Emption nur wenn Modal weg
        // (User hat „Aufgabe fertigmachen" getappt). Siehe
        // `TrainingView+SessionFlow.loadNextTrainingCard` für die
        // ausführliche Begründung.
        if TrainingChainStore.shared.timerExpired,
           !TrainingChainStore.shared.cutoffModalVisible,
           !session.isShowingResult {
            forceQuizDoneFromChainTimer()
            return
        }

        // **Daily Drop Modul 2.12 (2026-05-23)** — Count-Cap: Mit allen
        // Fragetypen zurück werden combo/Lückentext SEPARAT eingefügt, daher
        // kann `questions.count` über N liegen (z. B. 7 statt 5). Nach genau
        // `dailyDropCount` beantworteten Fragen beenden wir das Quiz HIER —
        // egal wie viele Fragen generiert wurden — damit der Quiz-Anteil exakt
        // perStepCount bleibt (Count-Bar/Counter konsistent). Reuse des
        // bewährten `isShowingResult` → `handleQuizResultVisibilityChange` →
        // `chainAdvance`-Pfads. No-op außerhalb Count-Modus und wenn
        // `questions.count == N` (dann setzt `session` `isShowingResult` selbst).
        if isCountChainStep,
           let cap = launchContext?.dailyDropCount,
           session.answeredResults.count >= cap,
           !session.isShowingResult {
            session.isShowingResult = true
            QuizSessionResumeStore.clear()
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
        appDebugLog("🛑 [Quiz] Force-Done via chain-timer-soft-cutoff")
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
        // **Daily Drop Modul 2.10 (2026-05-23)** — im Count-Modus den
        // Abschluss-/Achievement-Sound unterdrücken: der Quiz-Step endet
        // dort nahtlos (kein sichtbarer Abschluss). Der Antwort-Sound pro
        // Aufgabe (`playStudySuccess`/`playStudyError`) bleibt unberührt.
        // Normales Quiz + Zeit-Chain: Sound bleibt.
        if totalRewardCount > 0, !isCountChainStep {
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
        // **Daily Drop Modul 2.12** — Weiter-Flow-States zurücksetzen,
        // damit die nächste Frage frisch ohne „Weiter"-Wartezustand startet.
        quizAwaitingWeiter = false
        quizPendingCorrect = nil
    }

    func submitFillBlanks(for question: QuizFillBlanksQuestion) {
        guard let selected = fillBlanksSelected, !fillBlanksLocked else { return }
        let isCorrect = selected.lowercased() == question.correctAnswer.lowercased()

        if isCorrect {
            fillBlanksLocked = true
            feedbackPlayer.playStudySuccess()
            // **Daily Drop Modul 2.12 (2026-05-23)** — 1 Übung (1 Tick),
            // `correct = !fillBlanksHadMistake`. Count-Modus: kein Auto-Advance,
            // „Weiter"-Button übernimmt (Feedback-Chip bleibt grün).
            let result = !fillBlanksHadMistake
            scheduleAdvance(after: 0.8) {
                if isCountChainStep {
                    quizPendingCorrect = result
                    quizAwaitingWeiter = true
                } else {
                    completeCurrentQuestion(correct: result)
                }
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
