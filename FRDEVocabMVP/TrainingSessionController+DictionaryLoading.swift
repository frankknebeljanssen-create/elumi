import Foundation

extension TrainingSessionController {
    func refreshDictionaryTrainingListIfNeeded(
        launchContext: TrainingLaunchContext?,
        listStore: VocabularyListStore,
        selectedAppDirection: Direction,
        updateAppDirectionRaw: @escaping (String) -> Void
    ) {
        guard shouldPrepareDictionaryTrainingList(launchContext: launchContext) else {
            dictionaryTrainingLoadGeneration += 1
            loadedDictionaryTrainingList = nil
            loadedDictionaryContext = nil
            return
        }

        let requestedContext = DictionaryTrainingLoadContext(
            learningLevel: selectedDictionaryLearningLevel,
            language: selectedAppDirection.sourceLanguage
        )

        if loadedDictionaryContext == requestedContext, loadedDictionaryTrainingList != nil {
            ensureTrainingSelectionValidity(
                listStore: listStore,
                launchContext: launchContext,
                selectedAppDirection: selectedAppDirection
            )
            ensureDirectionValidity(
                listStore: listStore,
                launchContext: launchContext,
                selectedAppDirection: selectedAppDirection,
                updateAppDirectionRaw: updateAppDirectionRaw
            )
            return
        }

        Task {
            await reloadDictionaryTrainingList(for: requestedContext)
            ensureTrainingSelectionValidity(
                listStore: listStore,
                launchContext: launchContext,
                selectedAppDirection: selectedAppDirection
            )
            ensureDirectionValidity(
                listStore: listStore,
                launchContext: launchContext,
                selectedAppDirection: selectedAppDirection,
                updateAppDirectionRaw: updateAppDirectionRaw
            )
            resetTrainingSessionState()
        }
    }

    func reloadDictionaryTrainingList(for context: DictionaryTrainingLoadContext) async {
        dictionaryTrainingLoadGeneration += 1
        let generation = dictionaryTrainingLoadGeneration

        let loadedList = await Task.detached(priority: .utility) {
            makeDictionaryVocabularyList(
                for: context.learningLevel,
                language: context.language
            )
        }.value

        guard generation == dictionaryTrainingLoadGeneration else { return }
        loadedDictionaryTrainingList = loadedList
        loadedDictionaryContext = context
    }
}
