import Foundation

extension FlashcardsSetupController {
    func availableStackLists(
        from listStore: VocabularyListStore,
        selectedAppDirection: Direction
    ) -> [VocabularyList] {
        let preferredCardType = selectedSetupContent.preferredCardType
        let matchingPracticeLists = listStore.practiceLists.filter { list in
            list.items.contains {
                $0.sourceLanguage == selectedAppDirection.sourceLanguage &&
                (preferredCardType == nil || $0.cardType == preferredCardType)
            }
        }

        let builtInMatches = listStore.builtInList.items.contains { item in
            item.sourceLanguage == selectedAppDirection.sourceLanguage &&
            (preferredCardType == nil || item.cardType == preferredCardType)
        }

        var lists: [VocabularyList] = []
        if let dictionaryList = loadedDictionaryStackList,
           dictionaryList.items.contains(where: {
               $0.sourceLanguage == selectedAppDirection.sourceLanguage &&
               (preferredCardType == nil || $0.cardType == preferredCardType)
           }) {
            lists.append(dictionaryList)
        }
        lists.append(contentsOf: matchingPracticeLists)
        if builtInMatches {
            lists.append(listStore.builtInList)
        }
        return lists
    }

    func selectedStackLists(
        from listStore: VocabularyListStore,
        selectedAppDirection: Direction
    ) -> [VocabularyList] {
        let availableLists = availableStackLists(from: listStore, selectedAppDirection: selectedAppDirection)

        if let aggregateList = availableLists.first(where: { $0.isAggregateVocabulary }),
           selectedStackListIDs.contains(aggregateList.id) {
            return scopedFlashcardLaunchLists(from: [aggregateList])
        }

        return scopedFlashcardLaunchLists(
            from: availableLists.filter { selectedStackListIDs.contains($0.id) }
        )
    }

    func selectedStackLanguages(
        from listStore: VocabularyListStore,
        selectedAppDirection: Direction
    ) -> [StudyLanguage] {
        let languages = Set(
            selectedStackLists(from: listStore, selectedAppDirection: selectedAppDirection)
                .flatMap { $0.items.map(\.sourceLanguage) }
        )
        return StudyLanguage.allCases.filter { languages.contains($0) }
    }

    func selectedStackCardCount(
        from listStore: VocabularyListStore,
        selectedAppDirection: Direction
    ) -> Int {
        let preferredCardType = selectedSetupContent.preferredCardType
        return selectedStackLists(from: listStore, selectedAppDirection: selectedAppDirection)
            .reduce(0) { partialResult, list in
                partialResult + list.items.filter {
                    $0.sourceLanguage == selectedAppDirection.sourceLanguage &&
                    (preferredCardType == nil || $0.cardType == preferredCardType)
                }.count
            }
    }

    func isDictionarySelectedInStack() -> Bool {
        selectedStackListIDs.contains(VocabularyListStore.dictionaryListID)
    }

    func shouldPrepareDictionaryStackList(launchContext: FlashcardLaunchContext?) -> Bool {
        showingStackComposer ||
        isDictionarySelectedInStack() ||
        launchContext?.preferredListID == VocabularyListStore.dictionaryListID
    }

    func clearLaunchScope() {
        preferredLaunchItemIDs = []
    }

    func prepareReturnToSetup(
        selectedAppDirection: Direction,
        sessionStore: FlashcardSessionStore
    ) {
        clearLaunchScope()
        syncSetupSelection(selectedAppDirection: selectedAppDirection, sessionStore: sessionStore)
        isShowingSetup = true
    }

    func syncSetupSelection(
        selectedAppDirection: Direction,
        sessionStore: FlashcardSessionStore
    ) {
        selectedSetupDirection = selectedAppDirection
        sessionStore.selectedDirection = selectedAppDirection
    }
}
