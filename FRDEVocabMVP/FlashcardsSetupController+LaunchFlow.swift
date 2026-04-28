import Foundation

extension FlashcardsSetupController {
    func startFlashcardsFromSetup(
        listStore: VocabularyListStore,
        selectedAppDirection: Direction,
        sessionStore: FlashcardSessionStore
    ) -> Bool {
        let selectedLists = selectedStackLists(from: listStore, selectedAppDirection: selectedAppDirection)
        guard !selectedLists.isEmpty else { return false }

        // **User-Revision 2026-04-22**: Hard-Cap 200 Karten/Session auch
        // beim Launch durchziehen. „Alle" wird auf 200 gedeckelt; eine
        // explizite Slider-Auswahl > 200 ebenso.
        let maxPerSession = FlashcardsSetupController.maxCardsPerSession
        let effectiveMaxCardCount: Int = isUsingAllCards
            ? maxPerSession
            : min(selectedCardCount, maxPerSession)
        sessionStore.configureCustomDeck(
            from: selectedLists,
            language: selectedAppDirection.sourceLanguage,
            preferredCardType: selectedSetupContent.preferredCardType,
            maxCardCount: effectiveMaxCardCount
        )
        guard let customDeck = sessionStore.customDeck else { return false }

        sessionStore.selectedDeckID = customDeck.id
        sessionStore.selectedDirection = selectedSetupDirection
        // Schwelle aus dem Setup an den Store durchreichen, damit `markCorrect`
        // Karten nach 1, 2, 3 oder 4 korrekten Antworten aus dem Stapel nimmt
        // (User-Revision „4x Intensiv" 2026-04-22).
        sessionStore.masteryThreshold = max(1, min(4, masteryThreshold))
        sessionStore.startOrResumeSession()
        clearLaunchScope()
        isShowingSetup = false
        return true
    }
}
