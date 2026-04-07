import Foundation

extension QuizSessionController {
    func clearMergedCache() {
        QuizBuildService.clearMergedItemsCache()
        lastMergedItemsRequest = nil
        cachedCandidates = []
    }

    func syncSelectedLists(availableLists: [VocabularyList]) {
        let validIDs = Set(availableLists.map(\.id))
        selectedListIDs = selectedListIDs.filter { validIDs.contains($0) }
        if selectedListIDs.isEmpty, let firstAvailable = availableLists.first {
            selectedListIDs = [firstAvailable.id]
        }
    }

    func invalidatePreparedQuestions() {
        questionPrebuildGeneration += 1
        preparedQuestions = []
        plannedQuestionCount = 0
    }

    func refreshMergedItemsIfNeeded(
        from selectedLists: [VocabularyList],
        direction: Direction,
        force: Bool = false
    ) {
        let request = MergeRequest(
            listIDs: selectedLists.map(\.id),
            direction: direction
        )

        if !force, request == lastMergedItemsRequest {
            return
        }

        lastMergedItemsRequest = request
        rebuildMergedItems(from: selectedLists, direction: direction)
    }

    func rebuildMergedItems(from selectedLists: [VocabularyList], direction: Direction) {
        quizMergeGeneration += 1
        let generation = quizMergeGeneration
        reusedCandidateIDs = []
        preparedQuestions = []
        plannedQuestionCount = 0
        isLoadingRemainingQuestions = false

        let totalItems = selectedLists.reduce(0) { $0 + $1.items.count }
        print("⏱ [Quiz] rebuildMergedItems starting (\(selectedLists.count) lists, \(totalItems) items)")

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                var start = CFAbsoluteTimeGetCurrent()
                let mergedItems = QuizBuildService.mergedItems(from: selectedLists, direction: direction)
                print("⏱ [Quiz] mergedItems: \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms (\(mergedItems.count) items)")

                start = CFAbsoluteTimeGetCurrent()
                let candidates = QuizBuildService.makeQuizCandidates(from: mergedItems, direction: direction)
                print("⏱ [Quiz] makeQuizCandidates: \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms (\(candidates.count) candidates)")

                return (mergedItems: mergedItems, candidates: candidates)
            }.value

            guard generation == quizMergeGeneration else { return }
            cachedMergedItems = result.mergedItems
            cachedCandidates = result.candidates
            prepareQuestionsIfPossible()
        }
    }
}
