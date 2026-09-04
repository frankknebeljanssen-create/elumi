import Foundation

extension FlashcardsSetupController {
    func applyLaunchContextIfNeeded(
        _ launchContext: FlashcardLaunchContext?,
        listStore: VocabularyListStore,
        updateAppDirectionRaw: (String) -> Void,
        sessionStore: FlashcardSessionStore
    ) {
        guard let launchContext else {
            preferredLaunchItemIDs = []
            return
        }

        if let preferredListID = launchContext.preferredListID {
            if preferredListID == VocabularyListStore.dictionaryListID ||
                preferredListID == VocabularyListStore.builtInListID {
                selectedStackListIDs = [preferredListID]
            } else if let practiceList = listStore.practiceList(with: preferredListID) {
                listStore.selectedListID = practiceList.id
                selectedStackListIDs = [practiceList.id]
            } else if let targetList = listStore.customList(with: preferredListID) {
                listStore.selectedListID = targetList.id
                selectedStackListIDs = [targetList.id]
            }
        }

        if let preferredLanguage = launchContext.preferredLanguage {
            updateAppDirectionRaw(preferredLanguage.defaultDirectionToGerman.rawValue)
        }

        if let preferredDirection = launchContext.preferredDirection {
            selectedSetupDirection = preferredDirection
            sessionStore.selectedDirection = preferredDirection
        }

        if let preferredCardType = launchContext.preferredCardType {
            selectedSetupContent = preferredCardType == .words ? .words : .phrases
        } else {
            selectedSetupContent = .mixed
        }

        preferredLaunchItemIDs = Set(launchContext.preferredItemIDs ?? [])
        selectedCardCount = 0
        isUsingAllCardCount = true
        customCardCountText = ""
        shouldAutoStartFromLaunch = launchContext.shouldAutoStart
        isShowingSetup = !launchContext.shouldAutoStart
    }

    func ensureStackSelectionValidity(
        listStore: VocabularyListStore,
        selectedAppDirection: Direction,
        updateAppDirectionRaw: (String) -> Void
    ) {
        let availableLists = availableStackLists(from: listStore, selectedAppDirection: selectedAppDirection)
        let validIDs = Set(availableLists.map(\.id))
        selectedStackListIDs = selectedStackListIDs.filter { validIDs.contains($0) }

        if selectedStackListIDs.isEmpty, let builtIn = availableLists.first(where: { $0.isBuiltIn }) {
            selectedStackListIDs = [builtIn.id]
        } else if selectedStackListIDs.isEmpty, let firstAvailable = availableLists.first {
            selectedStackListIDs = [firstAvailable.id]
        }

        let selectedLanguages = selectedStackLanguages(from: listStore, selectedAppDirection: selectedAppDirection)
        if !selectedLanguages.isEmpty,
           !selectedLanguages.contains(selectedAppDirection.sourceLanguage),
           let fallbackLanguage = selectedLanguages.first {
            updateAppDirectionRaw(fallbackLanguage.defaultDirectionToGerman.rawValue)
        }
    }
}
