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

        var lists: [VocabularyList] = []
        lists.append(contentsOf: matchingPracticeLists)
        lists.append(contentsOf: StandardVocabularyLoader.levelLists)
        lists.append(contentsOf: StandardVocabularyLoader.topicLists)
        // **V1b Lernjahr-Filter (2026-04-28)** — Pro-Liste Items-Swap
        // BEVOR die Listen an Setup-UI/Builder weitergegeben werden.
        // Hierarchische Listen (A1 mit cumulativeChildren) bekommen
        // ihren Y_1...Y_max-Slice; flache Listen ihre vollen items.
        // Damit kaskadiert der Filter automatisch durch
        // selectedStackLists / selectedStackLanguages /
        // selectedStackCardCount.
        //
        // **Phase 2 Fix (2026-05-04)** — `children` + `cumulativeChildren`
        // beim Re-Build mitschleifen. Ohne diese Felder rendert der
        // `GlobalListPickerSheet` hierarchische Listen (A1) als flache
        // Row ohne Lernjahr-UI, weil `expandableLernjahrRow` nur greift
        // wenn `cumulativeChildren=true && children != nil`.
        let lernjahrMax = VocabularyListSelectionResolver.currentLernjahrMax()
        return lists.map { list in
            VocabularyList(
                id: list.id,
                name: list.name,
                items: VocabularyListSelectionResolver.effectiveItems(
                    for: list,
                    lernjahrMax: lernjahrMax
                ),
                isBuiltIn: list.isBuiltIn,
                collectionPreset: list.collectionPreset,
                isAggregateVocabulary: list.isAggregateVocabulary,
                children: list.children,
                cumulativeChildren: list.cumulativeChildren
            )
        }
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
        // **Infinitiv-Karten (2026-09-03)** — identisch zur Deck-
        // Erzeugung in `FlashcardSessionStore.configureCustomDeck`
        // ergänzt, sonst zeigt die MENGE-Card weniger Karten an, als der
        // Stapel am Ende enthält.
        return selectedStackLists(from: listStore, selectedAppDirection: selectedAppDirection)
            .reduce(0) { partialResult, list in
                let items = VerbInfinitiveSynthesizer.augmentedWithInfinitives(
                    list.items,
                    language: selectedAppDirection.sourceLanguage
                )
                return partialResult + items.filter {
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
