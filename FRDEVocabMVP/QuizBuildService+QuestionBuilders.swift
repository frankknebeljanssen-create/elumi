import Foundation

extension QuizBuildService {
    static func makeMergedItems(from lists: [VocabularyList], direction: Direction) -> [VocabularyItem] {
        var seen = Set<String>()

        return lists
            .flatMap(\.items)
            .filter { $0.sourceLanguage == direction.sourceLanguage }
            .filter { item in
                let key = [
                    normalizedLookupText(item.french),
                    normalizedLookupText(item.german),
                    item.cardType.rawValue
                ].joined(separator: "|")

                guard !key.isEmpty, !seen.contains(key) else { return false }
                seen.insert(key)
                return true
            }
    }

    static func nextMultipleChoiceQuestion(
        from candidates: [QuizCandidate],
        usedPromptKeys: inout [String: Int],
        usedCandidateIDs: inout Set<String>,
        usedQuestionSignatures: inout Set<String>
    ) -> QuizQuestion? {
        guard let (question, consumedIDs) = makeMultipleChoiceQuestion(
            from: candidates,
            usedPromptKeys: &usedPromptKeys,
            usedCandidateIDs: usedCandidateIDs
        ) else {
            return nil
        }

        let wrappedQuestion = QuizQuestion.multipleChoice(question)
        let signature = signature(wrappedQuestion)
        guard usedQuestionSignatures.insert(signature).inserted else { return nil }
        usedCandidateIDs.formUnion(consumedIDs)
        return wrappedQuestion
    }

    static func nextMatchingQuestion(
        from candidates: [QuizCandidate],
        usedPromptKeys: inout [String: Int],
        usedCandidateIDs: inout Set<String>,
        usedQuestionSignatures: inout Set<String>
    ) -> QuizQuestion? {
        guard let (question, consumedIDs) = makeMatchingQuestion(
            from: candidates,
            usedPromptKeys: &usedPromptKeys,
            usedCandidateIDs: usedCandidateIDs
        ) else {
            return nil
        }

        let wrappedQuestion = QuizQuestion.matching(question)
        let signature = signature(wrappedQuestion)
        guard usedQuestionSignatures.insert(signature).inserted else { return nil }
        usedCandidateIDs.formUnion(consumedIDs)
        return wrappedQuestion
    }

    static func makeMultipleChoiceQuestion(
        from candidates: [QuizCandidate],
        usedPromptKeys: inout [String: Int],
        usedCandidateIDs: Set<String>
    ) -> (QuizMultipleChoiceQuestion, Set<String>)? {
        guard let correctCandidate = nextQuizPromptCandidate(
            from: candidates,
            usedPromptKeys: usedPromptKeys,
            usedCandidateIDs: usedCandidateIDs
        ) else {
            return nil
        }

        let distractors = bestDistractors(
            for: correctCandidate,
            in: candidates,
            usedCandidateIDs: usedCandidateIDs
        )
        guard !distractors.isEmpty else { return nil }

        let options = Array(([correctCandidate.answer] + distractors.map(\.answer)).shuffled())
        usedPromptKeys[correctCandidate.promptKey, default: 0] += 1

        return (
            QuizMultipleChoiceQuestion(
                prompt: correctCandidate.prompt,
                correctAnswer: correctCandidate.answer,
                options: options,
                category: correctCandidate.category
            ),
            [correctCandidate.id]
        )
    }

    static func makeMatchingQuestion(
        from candidates: [QuizCandidate],
        usedPromptKeys: inout [String: Int],
        usedCandidateIDs: Set<String>
    ) -> (QuizMatchingQuestion, Set<String>)? {
        let available = candidates
            .filter { !usedCandidateIDs.contains($0.id) }
            .filter { usedPromptKeys[$0.promptKey, default: 0] == 0 }
            .uniqued(by: \.promptKey)
            .uniqued(by: \.answerKey)

        let targetPairCount = min(4, available.count)
        guard targetPairCount >= 2 else { return nil }

        let selectedCandidates = Array(available.shuffled().prefix(targetPairCount))
        let pairs = selectedCandidates.map {
            QuizMatchingPair(prompt: $0.prompt, answer: $0.answer)
        }

        let answerKeys = Set(selectedCandidates.map { $0.answerKey })
        guard answerKeys.count == selectedCandidates.count else { return nil }

        for candidate in selectedCandidates {
            usedPromptKeys[candidate.promptKey, default: 0] += 1
        }

        return (
            QuizMatchingQuestion(
                pairs: pairs,
                shuffledAnswers: pairs.shuffled(),
                category: pairs.count == 1 ? selectedCandidates[0].category : "Paare"
            ),
            Set(selectedCandidates.map(\.id))
        )
    }

    static func makeQuizCandidates(from items: [VocabularyItem], direction: Direction) -> [QuizCandidate] {
        var seen = Set<String>()
        var candidates: [QuizCandidate] = []

        for item in items {
            let card = item.card(for: direction)
            let frenchHint = cleanedQuizDisplayText(item.french)
            let prompt = quizVisibleText(
                card.prompt,
                languageCode: card.promptLanguageCode,
                category: card.category,
                sourceHint: frenchHint
            )
            let rawAnswer = card.answerLanguageCode == "de-DE"
                ? canonicalGermanQuizText(
                    prompt: card.prompt,
                    promptLanguageCode: card.promptLanguageCode,
                    answer: card.answer,
                    category: card.category,
                    sourceHint: frenchHint
                )
                : card.answer
            let answer = quizVisibleText(
                rawAnswer,
                languageCode: card.answerLanguageCode,
                category: card.category,
                sourceHint: frenchHint
            )
            let promptKey = normalizedLookupText(prompt)
            let answerKey = normalizedLookupText(answer)

            guard !promptKey.isEmpty, !answerKey.isEmpty else { continue }
            let uniqueKey = [promptKey, answerKey, card.category].joined(separator: "|")
            guard seen.insert(uniqueKey).inserted else { continue }

            candidates.append(
                QuizCandidate(
                    id: uniqueKey,
                    prompt: prompt,
                    answer: answer,
                    category: card.category,
                    promptLanguageCode: card.promptLanguageCode,
                    answerLanguageCode: card.answerLanguageCode,
                    promptKey: promptKey,
                    answerKey: answerKey,
                    promptWordCount: prompt.split(separator: " ").count,
                    answerWordCount: answer.split(separator: " ").count,
                    answerCharacterCount: answer.count,
                    answerHasArticle: startsWithGermanArticle(answer),
                    answerLeadingArticle: leadingGermanArticle(in: answer),
                    answerInitial: answerKey.split(separator: " ").dropFirst(startsWithGermanArticle(answer) ? 1 : 0).first.map { String($0.prefix(1)) } ?? String(answerKey.prefix(1)),
                    isPhrase: card.category == CardType.phrases.categoryName
                )
            )
        }

        return candidates
    }

    static func nextQuizPromptCandidate(
        from candidates: [QuizCandidate],
        usedPromptKeys: [String: Int],
        usedCandidateIDs: Set<String>
    ) -> QuizCandidate? {
        let sorted = candidates
            .filter { !usedCandidateIDs.contains($0.id) }
            .shuffled()
            .sorted { lhs, rhs in
                let lhsUsage = usedPromptKeys[lhs.promptKey, default: 0]
                let rhsUsage = usedPromptKeys[rhs.promptKey, default: 0]
                return lhsUsage < rhsUsage
            }

        return sorted.first
    }

    static func bestDistractors(
        for correctCandidate: QuizCandidate,
        in candidates: [QuizCandidate],
        usedCandidateIDs: Set<String>
    ) -> [QuizCandidate] {
        let exactStructurePool = candidates.filter {
            $0.id != correctCandidate.id &&
            !usedCandidateIDs.contains($0.id) &&
            $0.answerKey != correctCandidate.answerKey &&
            $0.category == correctCandidate.category &&
            $0.isPhrase == correctCandidate.isPhrase
        }

        let scoringPool = exactStructurePool.count >= 3 ? exactStructurePool : candidates

        let coarseRanked = scoringPool.compactMap { candidate -> (QuizCandidate, Double)? in
            guard candidate.id != correctCandidate.id else { return nil }
            guard candidate.answerKey != correctCandidate.answerKey else { return nil }
            guard normalizedLookupText(candidate.answer) != normalizedLookupText(correctCandidate.answer) else { return nil }
            guard candidate.answer.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(correctCandidate.answer.trimmingCharacters(in: .whitespacesAndNewlines)) != .orderedSame else { return nil }

            let score = coarseDistractorScore(candidate, against: correctCandidate)
            guard score > 0 else { return nil }
            return (candidate, score)
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.answer.localizedCaseInsensitiveCompare(rhs.0.answer) == .orderedAscending
            }
            return lhs.1 > rhs.1
        }
        .prefix(16)

        let scored = coarseRanked.map { candidate, coarseScore in
            (candidate, coarseScore + lexicalDistractorScore(candidate, against: correctCandidate))
        }
        .sorted { lhs, rhs in
            if lhs.1 == rhs.1 {
                return lhs.0.answer.localizedCaseInsensitiveCompare(rhs.0.answer) == .orderedAscending
            }
            return lhs.1 > rhs.1
        }

        var selected: [QuizCandidate] = []
        var seenAnswerKeys = Set<String>()

        for (candidate, _) in scored {
            guard seenAnswerKeys.insert(candidate.answerKey).inserted else { continue }
            selected.append(candidate)
            if selected.count == 3 { break }
        }

        if selected.count < 2 {
            let fallback = scoringPool.shuffled().filter {
                $0.id != correctCandidate.id &&
                !usedCandidateIDs.contains($0.id) &&
                $0.answerKey != correctCandidate.answerKey &&
                !seenAnswerKeys.contains($0.answerKey)
            }
            for candidate in fallback {
                guard seenAnswerKeys.insert(candidate.answerKey).inserted else { continue }
                selected.append(candidate)
                if selected.count == 3 { break }
            }
        }

        return selected
    }

    static func coarseDistractorScore(_ candidate: QuizCandidate, against correctCandidate: QuizCandidate) -> Double {
        var score = 0.0

        if candidate.category == correctCandidate.category {
            score += 4.0
        }

        if candidate.isPhrase == correctCandidate.isPhrase {
            score += 2.2
        }

        let answerWordDelta = abs(candidate.answerWordCount - correctCandidate.answerWordCount)
        score += max(0, 3.0 - Double(answerWordDelta))

        let answerCharacterDelta = abs(candidate.answerCharacterCount - correctCandidate.answerCharacterCount)
        score += max(0, 2.5 - Double(answerCharacterDelta) / 4.0)

        if candidate.answerHasArticle == correctCandidate.answerHasArticle {
            score += 1.5
        }

        if candidate.answerLeadingArticle == correctCandidate.answerLeadingArticle {
            score += 1.7
        }

        if candidate.answerInitial == correctCandidate.answerInitial {
            score += 1.2
        }

        if candidate.answer.contains(",") == correctCandidate.answer.contains(",") {
            score += 0.8
        }

        if candidate.promptWordCount == correctCandidate.promptWordCount {
            score += 0.7
        }

        return score
    }

    static func lexicalDistractorScore(_ candidate: QuizCandidate, against correctCandidate: QuizCandidate) -> Double {
        let lexicalDistance = Double(levenshteinDistance(candidate.answerKey, correctCandidate.answerKey))
        let normalizedDistance = lexicalDistance / Double(max(correctCandidate.answerKey.count, candidate.answerKey.count, 1))
        var score = max(0, 2.2 - normalizedDistance * 3.0)

        if normalizedDistance < 0.08 {
            score -= 8
        }

        return score
    }

    static func levenshteinDistance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs)
        let b = Array(rhs)
        var distances = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)

        for i in 0...a.count {
            distances[i][0] = i
        }
        for j in 0...b.count {
            distances[0][j] = j
        }

        for i in 1...a.count {
            for j in 1...b.count {
                if a[i - 1] == b[j - 1] {
                    distances[i][j] = distances[i - 1][j - 1]
                } else {
                    distances[i][j] = min(
                        distances[i - 1][j] + 1,
                        distances[i][j - 1] + 1,
                        distances[i - 1][j - 1] + 1
                    )
                }
            }
        }

        return distances[a.count][b.count]
    }
}
