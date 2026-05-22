import Foundation

extension QuizBuildService {
    static func generateQuestions(
        from items: [VocabularyItem],
        direction: Direction,
        count: Int,
        excludingCandidateIDs: Set<String> = [],
        excludingQuestionSignatures: Set<String> = []
    ) -> [QuizQuestion] {
        let candidateSourceItems = sampledQuizSourceItems(
            from: items,
            requestedCount: count,
            minimumPoolSize: 16,
            densityMultiplier: 8
        )
        let candidates = makeQuizCandidates(from: candidateSourceItems, direction: direction)
        let questions = generateQuestions(
            from: candidates,
            count: count,
            excludingCandidateIDs: excludingCandidateIDs,
            excludingQuestionSignatures: excludingQuestionSignatures
        )

        return questions
    }

    static func generateQuestions(
        from candidates: [QuizCandidate],
        count: Int,
        excludingCandidateIDs: Set<String> = [],
        excludingQuestionSignatures: Set<String> = [],
        atomicOnly: Bool = false
    ) -> [QuizQuestion] {
        let candidatePool = sampledQuizCandidates(
            from: candidates,
            requestedCount: count,
            minimumPoolSize: 16,
            densityMultiplier: 8
        )
        let availableCandidates = candidatePool.filter { !excludingCandidateIDs.contains($0.id) }
        guard availableCandidates.count >= 2 else { return [] }

        let questionKinds = plannedQuizQuestionKinds(for: availableCandidates, requestedCount: count, atomicOnly: atomicOnly)
        guard !questionKinds.isEmpty else { return [] }

        var questions: [QuizQuestion] = []
        var usedPromptKeys: [String: Int] = [:]
        var usedCandidateIDs = excludingCandidateIDs
        var usedQuestionSignatures = excludingQuestionSignatures

        for kind in questionKinds {
            let nextQuestion: QuizQuestion?
            switch kind {
            case .multipleChoice:
                // **Daily Drop Modul 1 (2026-05-23)** — im Atomar-Modus
                // fällt MC bei nil NICHT auf Matching zurück (würde ein
                // Matching durchrutschen lassen), sondern auf Tippen.
                var mcPicked = nextMultipleChoiceQuestion(
                    from: availableCandidates,
                    usedPromptKeys: &usedPromptKeys,
                    usedCandidateIDs: &usedCandidateIDs,
                    usedQuestionSignatures: &usedQuestionSignatures
                )
                if mcPicked == nil {
                    if atomicOnly {
                        mcPicked = nextTypingQuestion(
                            from: availableCandidates,
                            usedPromptKeys: &usedPromptKeys,
                            usedCandidateIDs: &usedCandidateIDs,
                            usedQuestionSignatures: &usedQuestionSignatures
                        )
                    } else {
                        mcPicked = nextMatchingQuestion(
                            from: availableCandidates,
                            usedPromptKeys: &usedPromptKeys,
                            usedCandidateIDs: &usedCandidateIDs,
                            usedQuestionSignatures: &usedQuestionSignatures
                        )
                    }
                }
                nextQuestion = mcPicked
            case .matching:
                nextQuestion = nextMatchingQuestion(
                    from: availableCandidates,
                    usedPromptKeys: &usedPromptKeys,
                    usedCandidateIDs: &usedCandidateIDs,
                    usedQuestionSignatures: &usedQuestionSignatures
                ) ?? nextMultipleChoiceQuestion(
                    from: availableCandidates,
                    usedPromptKeys: &usedPromptKeys,
                    usedCandidateIDs: &usedCandidateIDs,
                    usedQuestionSignatures: &usedQuestionSignatures
                )
            case .typing:
                nextQuestion = nextTypingQuestion(
                    from: availableCandidates,
                    usedPromptKeys: &usedPromptKeys,
                    usedCandidateIDs: &usedCandidateIDs,
                    usedQuestionSignatures: &usedQuestionSignatures
                ) ?? nextMultipleChoiceQuestion(
                    from: availableCandidates,
                    usedPromptKeys: &usedPromptKeys,
                    usedCandidateIDs: &usedCandidateIDs,
                    usedQuestionSignatures: &usedQuestionSignatures
                )
            }

            if let nextQuestion {
                questions.append(nextQuestion)
            }
        }

        return questions
    }

    static func generateImmediateStart(
        from items: [VocabularyItem],
        direction: Direction,
        requestedCount: Int,
        excludingCandidateIDs: Set<String> = [],
        excludingQuestionSignatures: Set<String> = []
    ) -> ImmediateQuizStartResult? {
        let candidateSourceItems = sampledQuizSourceItems(
            from: items,
            requestedCount: 1,
            minimumPoolSize: 10,
            densityMultiplier: 4
        )
        let candidates = sampledQuizCandidates(
            from: makeQuizCandidates(from: candidateSourceItems, direction: direction),
            requestedCount: 1,
            minimumPoolSize: 10,
            densityMultiplier: 4
        ).filter { !excludingCandidateIDs.contains($0.id) }
        guard candidates.count >= 2 else { return nil }

        let questionKinds = plannedQuizQuestionKinds(for: candidates, requestedCount: requestedCount)
        guard let firstKind = questionKinds.first else { return nil }
        let plannedCount = max(1, questionKinds.count)

        var usedPromptKeys: [String: Int] = [:]
        var usedCandidateIDs = excludingCandidateIDs
        var usedQuestionSignatures = excludingQuestionSignatures
        let question: QuizQuestion?

        switch firstKind {
        case .multipleChoice:
            question = nextMultipleChoiceQuestion(
                from: candidates,
                usedPromptKeys: &usedPromptKeys,
                usedCandidateIDs: &usedCandidateIDs,
                usedQuestionSignatures: &usedQuestionSignatures
            ) ?? nextMatchingQuestion(
                from: candidates,
                usedPromptKeys: &usedPromptKeys,
                usedCandidateIDs: &usedCandidateIDs,
                usedQuestionSignatures: &usedQuestionSignatures
            )
        case .matching:
            question = nextMatchingQuestion(
                from: candidates,
                usedPromptKeys: &usedPromptKeys,
                usedCandidateIDs: &usedCandidateIDs,
                usedQuestionSignatures: &usedQuestionSignatures
            ) ?? nextMultipleChoiceQuestion(
                from: candidates,
                usedPromptKeys: &usedPromptKeys,
                usedCandidateIDs: &usedCandidateIDs,
                usedQuestionSignatures: &usedQuestionSignatures
            )
        case .typing:
            question = nextTypingQuestion(
                from: candidates,
                usedPromptKeys: &usedPromptKeys,
                usedCandidateIDs: &usedCandidateIDs,
                usedQuestionSignatures: &usedQuestionSignatures
            ) ?? nextMultipleChoiceQuestion(
                from: candidates,
                usedPromptKeys: &usedPromptKeys,
                usedCandidateIDs: &usedCandidateIDs,
                usedQuestionSignatures: &usedQuestionSignatures
            )
        }

        guard let question else { return nil }
        return ImmediateQuizStartResult(question: question, plannedQuestionCount: plannedCount)
    }

    static func sampledQuizSourceItems(
        from items: [VocabularyItem],
        requestedCount: Int,
        minimumPoolSize: Int = 16,
        densityMultiplier: Int = 8
    ) -> [VocabularyItem] {
        let targetPoolSize = max(minimumPoolSize, requestedCount * densityMultiplier)
        guard items.count > targetPoolSize else { return items }

        var chosenIndices = Set<Int>()
        chosenIndices.reserveCapacity(targetPoolSize)

        while chosenIndices.count < targetPoolSize {
            chosenIndices.insert(Int.random(in: 0..<items.count))
        }

        return chosenIndices
            .sorted()
            .map { items[$0] }
    }

    static func sampledQuizCandidates(
        from candidates: [QuizCandidate],
        requestedCount: Int,
        minimumPoolSize: Int = 16,
        densityMultiplier: Int = 8
    ) -> [QuizCandidate] {
        let targetPoolSize = max(minimumPoolSize, requestedCount * densityMultiplier)
        guard candidates.count > targetPoolSize else { return candidates }

        var chosenIndices = Set<Int>()
        chosenIndices.reserveCapacity(targetPoolSize)

        while chosenIndices.count < targetPoolSize {
            chosenIndices.insert(Int.random(in: 0..<candidates.count))
        }

        return chosenIndices
            .sorted()
            .map { candidates[$0] }
    }

    static func plannedQuizQuestionKinds(for candidates: [QuizCandidate], requestedCount: Int, atomicOnly: Bool = false) -> [QuizQuestionKind] {
        let actualCount = min(requestedCount, max(1, candidates.count))
        // **Daily Drop Modul 1 (2026-05-23)** — Atomar-Modus erlaubt nur
        // MultipleChoice + Tippen (kein Matching).
        let canDoMatching = candidates.count >= 4 && !atomicOnly
        let pool: [QuizQuestionKind] = canDoMatching
            ? [.multipleChoice, .matching, .typing]
            : [.multipleChoice, .typing]

        var kinds: [QuizQuestionKind] = []
        for i in 0..<actualCount {
            let lastKind = kinds.last
            // First question: never typing
            var available = pool.filter { $0 != lastKind }
            if i == 0 {
                available = available.filter { $0 != .typing }
            }
            let picked = (available.isEmpty ? pool : available).randomElement() ?? .multipleChoice
            kinds.append(picked)
        }

        return kinds
    }
}
