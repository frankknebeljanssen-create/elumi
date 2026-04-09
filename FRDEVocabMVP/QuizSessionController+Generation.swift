import Foundation

extension QuizSessionController {
    func prepareQuestionsIfPossible() {
        let candidates = cachedCandidates
        guard candidates.count >= 2 else { return }

        let generation = questionPrebuildGeneration + 1
        questionPrebuildGeneration = generation
        let requestedCount = questionCountOption.rawValue
        let items = cachedMergedItems

        Task {
            var generatedQuestions = await Task.detached(priority: .utility) {
                QuizBuildService.generateQuestions(
                    from: candidates,
                    count: requestedCount
                )
            }.value

            // Insert special question types if possible
            if requestedCount >= 5, !generatedQuestions.isEmpty {
                var comboPromptKeys: [String: Int] = [:]
                var comboCandidateIDs = Set<String>()
                var comboSignatures = Set(generatedQuestions.map(QuizBuildService.signature))

                // Word Combo at position ~5
                if let combo = QuizBuildService.nextWordComboQuestion(
                    from: candidates,
                    items: items,
                    direction: (Direction(rawValue: UserDefaults.standard.string(forKey: appDirectionKey) ?? "") ?? .frenchToGerman).sanitizedForFrenchOnly,
                    usedPromptKeys: &comboPromptKeys,
                    usedCandidateIDs: &comboCandidateIDs,
                    usedQuestionSignatures: &comboSignatures
                ) {
                    let idx = min(4, generatedQuestions.count)
                    generatedQuestions.insert(combo, at: idx)
                }

                // Fill-in-Blank at position ~3
                if let fillBlank = QuizBuildService.nextFillBlanksQuestion(
                    items: items,
                    usedSignatures: &comboSignatures
                ) {
                    let idx = min(2, generatedQuestions.count)
                    generatedQuestions.insert(fillBlank, at: idx)
                }
            }

            guard generation == questionPrebuildGeneration else { return }
            guard !isPreparingQuiz else { return }
            guard !generatedQuestions.isEmpty else { return }

            preparedQuestions = generatedQuestions
            plannedQuestionCount = max(requestedCount, generatedQuestions.count)
        }
    }

    func startQuiz(direction: Direction) {
        let candidates = cachedCandidates
        print("🧩 [Quiz] session.startQuiz candidates=\(candidates.count)")
        guard candidates.count >= 2 else {
            print("🧩 [Quiz] ❌ not enough candidates (<2)")
            return
        }

        normalizeReuseHistory(using: candidates)
        let roundExclusionCandidateIDs = reusedCandidateIDs

        if !preparedQuestions.isEmpty {
            applyPreparedQuizQuestions(preparedQuestions)
            return
        }

        let generation = quizPreparationGeneration + 1
        quizPreparationGeneration = generation
        isPreparingQuiz = true
        isLoadingRemainingQuestions = false

        let requestedCount = questionCountOption.rawValue
        let initialBatchCount = min(3, requestedCount)

        Task {
            let initialQuestions = await Task.detached(priority: .userInitiated) {
                QuizBuildService.generateQuestions(
                    from: candidates,
                    count: initialBatchCount,
                    excludingCandidateIDs: roundExclusionCandidateIDs
                )
            }.value
            guard generation == quizPreparationGeneration else { return }

            guard !initialQuestions.isEmpty else {
                isPreparingQuiz = false
                isLoadingRemainingQuestions = false
                return
            }

            isPreparingQuiz = false
            isLoadingRemainingQuestions = initialQuestions.count < requestedCount
            applyInitialQuizQuestions(initialQuestions, plannedQuestionCount: requestedCount)

            let initialCandidateIDs = QuizBuildService.consumedCandidateIDs(from: initialQuestions)
            let initialSignatures = Set(initialQuestions.map(QuizBuildService.signature))
            let remainingQuestionCount = max(0, requestedCount - initialQuestions.count)
            guard remainingQuestionCount > 0 else {
                isLoadingRemainingQuestions = false
                return
            }

            let generatedQuestions = await Task.detached(priority: .utility) {
                QuizBuildService.generateQuestions(
                    from: candidates,
                    count: remainingQuestionCount,
                    excludingCandidateIDs: roundExclusionCandidateIDs.union(initialCandidateIDs),
                    excludingQuestionSignatures: initialSignatures
                )
            }.value
            guard generation == quizPreparationGeneration else { return }

            isPreparingQuiz = false
            guard !generatedQuestions.isEmpty else {
                isLoadingRemainingQuestions = false
                return
            }

            // Try to insert a Word Combo question
            let allItems = self.cachedMergedItems
            let allCandidates = self.cachedCandidates
            var comboPromptKeys: [String: Int] = [:]
            var comboCandidateIDs = Set<String>()
            var comboSignatures = Set((initialQuestions + generatedQuestions).map(QuizBuildService.signature))

            if let combo = QuizBuildService.nextWordComboQuestion(
                from: allCandidates,
                items: allItems,
                direction: direction,
                usedPromptKeys: &comboPromptKeys,
                usedCandidateIDs: &comboCandidateIDs,
                usedQuestionSignatures: &comboSignatures
            ) {
                var combined = generatedQuestions
                let insertIdx = min(1, combined.count)
                combined.insert(combo, at: insertIdx)
                appendPreparedQuizQuestions(combined)
                print("🧩 [WordCombo] ✅ inserted into quiz")
            } else {
                appendPreparedQuizQuestions(generatedQuestions)
                print("🧩 [WordCombo] ❌ no matching pairs for user's vocabulary")
            }
        }
    }

    func applyPreparedQuizQuestions(_ generatedQuestions: [QuizQuestion]) {
        questions = generatedQuestions
        preparedQuestions = generatedQuestions
        plannedQuestionCount = max(questionCountOption.rawValue, generatedQuestions.count)
        isLoadingRemainingQuestions = false
        currentQuestionIndex = 0
        answeredResults = []
        isShowingResult = false
    }

    func applyInitialQuizQuestions(_ generatedQuestions: [QuizQuestion], plannedQuestionCount: Int) {
        questions = generatedQuestions
        preparedQuestions = generatedQuestions
        self.plannedQuestionCount = max(plannedQuestionCount, generatedQuestions.count)
        currentQuestionIndex = 0
        answeredResults = []
        isShowingResult = false
    }

    func appendPreparedQuizQuestions(_ generatedQuestions: [QuizQuestion]) {
        isLoadingRemainingQuestions = false

        if questions.isEmpty {
            applyPreparedQuizQuestions(generatedQuestions)
            return
        }

        let existingSignatures = Set(questions.map(QuizBuildService.signature))
        let additionalQuestions = generatedQuestions
            .filter { !existingSignatures.contains(QuizBuildService.signature($0)) }
        questions.append(contentsOf: additionalQuestions)
        preparedQuestions = questions
        plannedQuestionCount = max(plannedQuestionCount, questions.count)
    }

    func normalizeReuseHistory(using candidates: [QuizCandidate]) {
        let availableCandidateIDs = Set(candidates.map(\.id))
        reusedCandidateIDs.formIntersection(availableCandidateIDs)

        let remainingCandidateCount = availableCandidateIDs.subtracting(reusedCandidateIDs).count
        if remainingCandidateCount < 2 {
            reusedCandidateIDs.removeAll()
        }
    }
}
