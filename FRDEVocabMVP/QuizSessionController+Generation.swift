import Foundation

extension QuizSessionController {
    func prepareQuestionsIfPossible() {
        let candidates = cachedCandidates
        guard candidates.count >= 2 else { return }

        let generation = questionPrebuildGeneration + 1
        questionPrebuildGeneration = generation
        let requestedCount = questionCountOption.rawValue
        let items = cachedMergedItems
        let atomicOnly = self.atomicOnly

        Task {
            var generatedQuestions = await Task.detached(priority: .utility) {
                QuizBuildService.generateQuestions(
                    from: candidates,
                    count: requestedCount,
                    atomicOnly: atomicOnly
                )
            }.value

            // Insert special question types if possible.
            // **Daily Drop Modul 1 (2026-05-23)** — im Atomar-Modus
            // übersprungen, damit `questions.count == requestedCount`
            // exakt bleibt (nur MC + Tippen).
            if requestedCount >= 5, !generatedQuestions.isEmpty, !atomicOnly {
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
                    // **2026-08-06, Bug-Fix** — vorher `insert`, wodurch
                    // die Runde LÄNGER wurde als gewählt (User-Report:
                    // "ich hab ein Quiz mit fünf Fragen gemacht... jetzt
                    // sind's sechs"). Der Nutzer wählt oben ausdrücklich
                    // eine Anzahl; die darf die App nicht stillschweigend
                    // überschreiten. Ersetzen statt einfügen behält die
                    // Abwechslung und hält die Zahl exakt ein.
                    let idx = min(4, generatedQuestions.count - 1)
                    generatedQuestions[idx] = combo
                }

                // Lückentext etwa alle 4 Fragen — ebenfalls ersetzend
                // statt einfügend, siehe Begründung beim Word-Combo oben.
                let fillBlankInterval = 4
                for pos in stride(from: 2, to: generatedQuestions.count, by: fillBlankInterval) {
                    if let fillBlank = QuizBuildService.nextFillBlanksQuestion(
                        items: items,
                        usedSignatures: &comboSignatures
                    ) {
                        generatedQuestions[pos] = fillBlank
                    }
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
        // Resume: wenn ein kompatibler Snapshot liegt, direkt fortsetzen
        // und den gesamten Kandidaten/Generate-Pfad überspringen. Nur
        // ausgeführt, wenn noch keine Fragen im Controller geladen sind
        // (Schutz gegen doppelten Resume bei mehrfachem onAppear).
        if questions.isEmpty,
           tryRestoreResumeSnapshot(
               expectedDirection: direction,
               expectedListIDs: selectedListIDs,
               expectedCount: questionCountOption
           ) {
            appDebugLog("🧩 [Quiz] resumed from snapshot, questions=\(questions.count), index=\(currentQuestionIndex)")
            return
        }

        let candidates = cachedCandidates
        appDebugLog("🧩 [Quiz] session.startQuiz candidates=\(candidates.count)")
        guard candidates.count >= 2 else {
            appDebugLog("🧩 [Quiz] ❌ not enough candidates (<2)")
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
        let atomicOnly = self.atomicOnly

        Task {
            let initialQuestions = await Task.detached(priority: .userInitiated) {
                QuizBuildService.generateQuestions(
                    from: candidates,
                    count: initialBatchCount,
                    excludingCandidateIDs: roundExclusionCandidateIDs,
                    atomicOnly: atomicOnly
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
                    excludingQuestionSignatures: initialSignatures,
                    atomicOnly: atomicOnly
                )
            }.value
            guard generation == quizPreparationGeneration else { return }

            isPreparingQuiz = false
            guard !generatedQuestions.isEmpty else {
                isLoadingRemainingQuestions = false
                return
            }

            // **Daily Drop Modul 1 (2026-05-23)** — Atomar-Modus: keine
            // Combo-Insertion, damit `questions.count` exakt bleibt.
            if atomicOnly {
                appendPreparedQuizQuestions(generatedQuestions)
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
                appDebugLog("🧩 [WordCombo] ✅ inserted into quiz")
            } else {
                appendPreparedQuizQuestions(generatedQuestions)
                appDebugLog("🧩 [WordCombo] ❌ no matching pairs for user's vocabulary")
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
        // Frisch generierte Runde → Snapshot initial speichern, damit
        // schon nach Frage 0 ein Resume-Zustand auf der Platte liegt.
        persistResumeSnapshotIfEligible()
    }

    func applyInitialQuizQuestions(_ generatedQuestions: [QuizQuestion], plannedQuestionCount: Int) {
        questions = generatedQuestions
        preparedQuestions = generatedQuestions
        self.plannedQuestionCount = max(plannedQuestionCount, generatedQuestions.count)
        currentQuestionIndex = 0
        answeredResults = []
        isShowingResult = false
        persistResumeSnapshotIfEligible()
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
