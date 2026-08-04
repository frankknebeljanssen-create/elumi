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
        // **V1b (2026-04-28)** — `lernjahrMax` ist Teil des Equality-
        // Vergleichs UND der Cache-Key-Identität. Damit wird ein Filter-
        // Wechsel (gleiche Listen + Direction, anderer max) korrekt als
        // „muss neu gebaut werden" erkannt.
        let lernjahrMax = VocabularyListSelectionResolver.currentLernjahrMax()
        let request = MergeRequest(
            listIDs: selectedLists.map(\.id),
            direction: direction,
            lernjahrMax: lernjahrMax,
            itemFingerprint: MergeRequest.fingerprint(for: selectedLists)
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

        // **V1b (2026-04-28)** — Diagnostic zeigt raw vs effective Counts
        // damit Filter-Wirkung in Logs sofort sichtbar ist.
        let lernjahrMax = VocabularyListSelectionResolver.currentLernjahrMax()
        let rawTotal = selectedLists.reduce(0) { $0 + $1.items.count }
        let effectiveTotal = selectedLists.reduce(0) { acc, list in
            acc + VocabularyListSelectionResolver.effectiveItems(for: list, lernjahrMax: lernjahrMax).count
        }
        appDebugLog("⏱ [Quiz] rebuildMergedItems: lists=\(selectedLists.count) raw=\(rawTotal) effective=\(effectiveTotal) lernjahrMax=\(lernjahrMax.map(String.init) ?? "nil")")

        Task {
            let result = await Task.detached(priority: .userInitiated) {
                var start = CFAbsoluteTimeGetCurrent()
                let mergedItems = QuizBuildService.mergedItems(from: selectedLists, direction: direction)
                appDebugLog("⏱ [Quiz] mergedItems: \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms (\(mergedItems.count) items)")

                start = CFAbsoluteTimeGetCurrent()
                let candidates = QuizBuildService.makeQuizCandidates(from: mergedItems, direction: direction)
                appDebugLog("⏱ [Quiz] makeQuizCandidates: \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms (\(candidates.count) candidates)")

                return (mergedItems: mergedItems, candidates: candidates)
            }.value

            guard generation == quizMergeGeneration else { return }
            cachedMergedItems = result.mergedItems
            cachedCandidates = result.candidates
            prepareQuestionsIfPossible()
        }
    }
}
