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
        // Bewusst kein Lernjahr-Filter: scoped-launch ist explicit user intent
        // (z.B. nach Import). preferredLaunchItemIDs sticht globalen Filter.
        //
        // Begründung: Wenn der User gerade 5 Items importiert hat und diese
        // direkt im Flashcards-Modul üben will, sind die ID-genauen Items
        // authoritativ — auch wenn einzelne Y3-getaggt sind und der globale
        // lernjahrMax=1 stehen würde. Die Caller-Site hat hier sehr explizit
        // „diese Items, jetzt". Globalen Filter zu applizieren wäre eine
        // verwirrende Verkleinerung des User-Intents.
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
