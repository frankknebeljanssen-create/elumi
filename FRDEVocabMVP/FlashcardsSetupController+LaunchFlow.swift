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
            maxCardCount: isUsingAllCards ? nil : selectedCardCount
        )
        guard let customDeck = sessionStore.customDeck else { return false }

        sessionStore.selectedDeckID = customDeck.id
        sessionStore.selectedDirection = selectedSetupDirection
        // Schwelle aus dem Setup an den Store durchreichen, damit `markCorrect`
        // Karten nach 1, 2 oder 3 korrekten Antworten aus dem Stapel nimmt.
        sessionStore.masteryThreshold = max(1, min(3, masteryThreshold))
        sessionStore.startOrResumeSession()
        clearLaunchScope()
        isShowingSetup = false
        return true
    }
}
