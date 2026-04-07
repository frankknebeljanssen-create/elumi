import Foundation

extension TrainingSessionController {
    var placeholderDictionaryTrainingList: VocabularyList {
        VocabularyList(
            id: VocabularyListStore.dictionaryListID,
            name: "Wörterbuch",
            items: [],
            isBuiltIn: false,
            collectionPreset: .other
        )
    }

    func dictionaryTrainingList() -> VocabularyList? {
        loadedDictionaryTrainingList
    }

    func isDictionaryTrainingSelected() -> Bool {
        selectedTrainingListID == VocabularyListStore.dictionaryListID
    }

    func shouldPrepareDictionaryTrainingList(launchContext: TrainingLaunchContext?) -> Bool {
        showingTrainingListPicker ||
        isDictionaryTrainingSelected() ||
        launchContext?.preferredListID == VocabularyListStore.dictionaryListID
    }

    func availableTrainingLists(
        from listStore: VocabularyListStore,
        selectedAppDirection: Direction,
        launchContext: TrainingLaunchContext?
    ) -> [VocabularyList] {
        let dictionaryLists: [VocabularyList]
        if shouldPrepareDictionaryTrainingList(launchContext: launchContext) {
            dictionaryLists = [dictionaryTrainingList() ?? placeholderDictionaryTrainingList]
        } else {
            dictionaryLists = []
        }

        return dictionaryLists + listStore.practiceLists
    }

    func selectedTrainingList(
        from listStore: VocabularyListStore,
        selectedAppDirection: Direction,
        launchContext: TrainingLaunchContext?
    ) -> VocabularyList? {
        let availableLists = availableTrainingLists(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )

        if let selectedTrainingListID {
            return availableLists.first(where: { $0.id == selectedTrainingListID }) ?? availableLists.first
        }
        return availableLists.first
    }

    func activeItems(
        from listStore: VocabularyListStore,
        selectedAppDirection: Direction,
        launchContext: TrainingLaunchContext?
    ) -> [VocabularyItem] {
        selectedTrainingList(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )?.items.filter {
            $0.sourceLanguage == selectedAppDirection.sourceLanguage &&
            $0.cardType == cardType
        } ?? []
    }

    func selectedTrainingListLanguages(
        from listStore: VocabularyListStore,
        selectedAppDirection: Direction,
        launchContext: TrainingLaunchContext?
    ) -> [StudyLanguage] {
        let languages = Set(
            selectedTrainingList(
                from: listStore,
                selectedAppDirection: selectedAppDirection,
                launchContext: launchContext
            )?.items.map(\.sourceLanguage) ?? []
        )
        return StudyLanguage.allCases.filter { languages.contains($0) }
    }
}
