import Foundation

extension FlashcardsSetupController {
    func refreshDictionaryStackListIfNeeded(
        launchContext: FlashcardLaunchContext?,
        selectedAppDirection: Direction,
        listStore: VocabularyListStore,
        updateAppDirectionRaw: @escaping (String) -> Void
    ) {
        guard shouldPrepareDictionaryStackList(launchContext: launchContext) else {
            dictionaryStackLoadGeneration += 1
            loadedDictionaryStackList = nil
            loadedDictionaryContext = nil
            return
        }

        let requestedContext = DictionaryStackLoadContext(
            learningLevel: selectedStackDictionaryLearningLevel,
            language: selectedAppDirection.sourceLanguage
        )

        if loadedDictionaryContext == requestedContext, loadedDictionaryStackList != nil {
            ensureStackSelectionValidity(
                listStore: listStore,
                selectedAppDirection: selectedAppDirection,
                updateAppDirectionRaw: updateAppDirectionRaw
            )
            return
        }

        Task {
            await reloadDictionaryStackList(for: requestedContext)
            ensureStackSelectionValidity(
                listStore: listStore,
                selectedAppDirection: selectedAppDirection,
                updateAppDirectionRaw: updateAppDirectionRaw
            )
        }
    }

    func reloadDictionaryStackList(for context: DictionaryStackLoadContext) async {
        dictionaryStackLoadGeneration += 1
        let generation = dictionaryStackLoadGeneration

        let loadedList = await Task.detached(priority: .utility) {
            makeDictionaryVocabularyList(
                for: context.learningLevel,
                language: context.language
            )
        }.value

        guard generation == dictionaryStackLoadGeneration else { return }
        loadedDictionaryStackList = loadedList
        loadedDictionaryContext = context
    }

    func scopedFlashcardLaunchLists(from lists: [VocabularyList]) -> [VocabularyList] {
        guard !preferredLaunchItemIDs.isEmpty else { return lists }

        return lists.compactMap { list in
            let filteredItems = list.items.filter { preferredLaunchItemIDs.contains($0.id) }
            guard !filteredItems.isEmpty else { return nil }

            return VocabularyList(
                id: list.id,
                name: list.name,
                items: filteredItems,
                isBuiltIn: list.isBuiltIn,
                collectionPreset: list.collectionPreset,
                isAggregateVocabulary: list.isAggregateVocabulary
            )
        }
    }
}
