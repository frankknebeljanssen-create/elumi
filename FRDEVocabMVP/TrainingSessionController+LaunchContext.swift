import Foundation

extension TrainingSessionController {
    func applyLaunchContextIfNeeded(
        _ launchContext: TrainingLaunchContext?,
        listStore: VocabularyListStore,
        updateAppDirectionRaw: (String) -> Void
    ) {
        guard let launchContext else { return }

        if let preferredListID = launchContext.preferredListID {
            if preferredListID == VocabularyListStore.dictionaryListID {
                selectedTrainingListID = preferredListID
            } else if let practiceList = listStore.practiceList(with: preferredListID) {
                listStore.selectedListID = practiceList.id
                selectedTrainingListID = practiceList.id
            } else if listStore.customList(with: preferredListID) != nil {
                listStore.selectedListID = preferredListID
                selectedTrainingListID = preferredListID
            } else if preferredListID == VocabularyListStore.allCustomVocabularyListID {
                selectedTrainingListID = preferredListID
            }
        }

        if let preferredDirection = launchContext.preferredDirection {
            direction = preferredDirection
            updateAppDirectionRaw(preferredDirection.rawValue)
        }

        if let preferredCardType = launchContext.preferredCardType {
            cardType = preferredCardType
        }

        isShowingSetup = true
    }

    func ensureTrainingSelectionValidity(
        listStore: VocabularyListStore,
        launchContext: TrainingLaunchContext?,
        selectedAppDirection: Direction
    ) {
        let availableLists = availableTrainingLists(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )

        if availableLists.isEmpty {
            selectedTrainingListID = nil
            return
        }

        if selectedTrainingListID == VocabularyListStore.dictionaryListID,
           shouldPrepareDictionaryTrainingList(launchContext: launchContext),
           dictionaryTrainingList() == nil {
            return
        }

        let validIDs = Set(availableLists.map(\.id))

        if let selectedTrainingListID, validIDs.contains(selectedTrainingListID) {
            return
        }

        if let visibleSelectionID = selectedTrainingList(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )?.id, validIDs.contains(visibleSelectionID) {
            selectedTrainingListID = visibleSelectionID
            return
        }

        if let launchPreferredID = launchContext?.preferredListID,
           validIDs.contains(launchPreferredID) {
            selectedTrainingListID = launchPreferredID
            return
        }

        if let selectedCustomID = listStore.selectedCustomList?.id,
           validIDs.contains(selectedCustomID) {
            selectedTrainingListID = selectedCustomID
            return
        }

        selectedTrainingListID = availableLists.first?.id
    }

    func ensureDirectionValidity(
        listStore: VocabularyListStore,
        launchContext: TrainingLaunchContext?,
        selectedAppDirection: Direction,
        updateAppDirectionRaw: (String) -> Void
    ) {
        let selectedLanguages = selectedTrainingListLanguages(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )

        if !selectedLanguages.isEmpty,
           !selectedLanguages.contains(selectedAppDirection.sourceLanguage),
           let fallbackLanguage = selectedLanguages.first {
            let fallbackDirection = fallbackLanguage.defaultDirectionToGerman
            updateAppDirectionRaw(fallbackDirection.rawValue)
            direction = fallbackDirection
            return
        }

        direction = selectedAppDirection
    }
}
