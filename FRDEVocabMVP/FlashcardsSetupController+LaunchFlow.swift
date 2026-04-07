import Foundation

extension FlashcardsSetupController {
    func startFlashcardsFromSetup(
        listStore: VocabularyListStore,
        selectedAppDirection: Direction,
        sessionStore: FlashcardSessionStore
    ) -> Bool {
        let selectedLists = selectedStackLists(from: listStore, selectedAppDirection: selectedAppDirection)
        guard !selectedLists.isEmpty else { return false }

        sessionStore.configureCustomDeck(
            from: selectedLists,
            language: selectedAppDirection.sourceLanguage,
            preferredCardType: selectedSetupContent.preferredCardType,
            maxCardCount: isUsingAllCardCount ? nil : requestedCustomCardCount
        )
        guard let customDeck = sessionStore.customDeck else { return false }

        sessionStore.selectedDeckID = customDeck.id
        sessionStore.selectedDirection = selectedSetupDirection
        sessionStore.startOrResumeSession()
        clearLaunchScope()
        isShowingSetup = false
        return true
    }
}
