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
        session.syncSelectedLists(availableLists: availableQuizLists)
        session.startQuiz(direction: selectedAppDirection)
        awardedHearts = 0
        awardedWaterfloh = 0
        awardedAlgenkugel = 0
        awardedXP = 0
        unlockedRewardLevels = []
        didPersistHearts = false
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

                if matchedPairIDs.count == question.pairs.count {
                    let isCorrect = !matchingHadMistake
                    scheduleAdvance(after: 0.72) {
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
    }

    func prepareQuizRewards() {
        let rewardOutcome = computeElumiRewardOutcome(
            baseWorms: correctCount,
            baseXP: correctCount * 10,
            isPerfectLesson: isPerfectQuiz,
            currentXP: collectedXP,
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            lastRewardDayIndex: lastRewardDayIndex
        )

        awardedHearts = rewardOutcome.worms
        awardedWaterfloh = rewardOutcome.waterfloh
        awardedAlgenkugel = rewardOutcome.algenkugel
        awardedXP = rewardOutcome.xp
        unlockedRewardLevels = rewardOutcome.unlockedLevels
        if totalRewardCount > 0 || awardedXP > 0 {
            feedbackPlayer.playStudyAchievement()
        }
    }

    func persistHeartsIfNeeded() {
        guard !didPersistHearts else { return }
        let rewardOutcome = computeElumiRewardOutcome(
            baseWorms: correctCount,
            baseXP: correctCount * 10,
            isPerfectLesson: isPerfectQuiz,
            currentXP: collectedXP,
            currentStreak: currentStreak,
            bestStreak: bestStreak,
            lastRewardDayIndex: lastRewardDayIndex
        )

        collectedWorms += rewardOutcome.worms
        collectedWaterfloh += rewardOutcome.waterfloh
        collectedAlgenkugel += rewardOutcome.algenkugel
        collectedXP += rewardOutcome.xp
        currentStreak = rewardOutcome.currentStreak
        bestStreak = rewardOutcome.bestStreak
        lastRewardDayIndex = rewardOutcome.lastRewardDayIndex
        didPersistHearts = true

        // Arcade credits
        let credits = ArcadeCreditSystem.creditsEarned(
            totalQuestions: session.questions.count,
            correctAnswers: correctCount,
            wrongAnswers: wrongCount,
            isPerfect: isPerfectQuiz
        )
        if credits > 0 {
            arcadeCredits += credits
        }
    }

    func resetPerQuestionState() {
        cancelAdvanceTask()
        selectedMultipleChoiceOption = nil
        multipleChoiceLocked = false
        selectedPromptID = nil
        selectedAnswerID = nil
        matchedPairIDs = []
        matchingHadMistake = false
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
        awardedXP = 0
        unlockedRewardLevels = []
        didPersistHearts = false
        resetPerQuestionState()
    }

    func dismissToHome() {
        resetQuizToSetup()
        goHome()
    }

    func handleBackNavigation() {
        if session.isShowingResult || !session.questions.isEmpty {
            resetQuizToSetup()
        } else {
            dismiss()
        }
    }

}
