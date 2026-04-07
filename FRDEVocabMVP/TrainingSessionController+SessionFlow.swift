import Foundation

extension TrainingSessionController {
    func resetTrainingSessionState() {
        hasStartedTraining = false
        failedAttemptsOnCurrentCard = 0
        currentTrainingItem = nil
        preparedTrainingItems = []
        remainingTrainingItems = []
    }

    func returnToSetup() {
        isShowingSetup = true
    }

    func startTraining(
        listStore: VocabularyListStore,
        launchContext: TrainingLaunchContext?,
        selectedAppDirection: Direction
    ) -> Bool {
        let deck = buildTrainingDeck(
            listStore: listStore,
            launchContext: launchContext,
            selectedAppDirection: selectedAppDirection
        )
        guard !deck.isEmpty else {
            resetTrainingSessionState()
            return false
        }

        preparedTrainingItems = deck
        hasStartedTraining = true
        isShowingSetup = false
        loadNextTrainingCard()
        return currentTrainingItem != nil
    }

    func loadNextTrainingCard() {
        let previousItem = currentTrainingItem
        failedAttemptsOnCurrentCard = 0

        if remainingTrainingItems.isEmpty {
            remainingTrainingItems = TrainingDeckBuilder.shuffledRound(
                from: preparedTrainingItems,
                avoiding: previousItem
            )
        }

        guard !remainingTrainingItems.isEmpty else {
            hasStartedTraining = false
            currentTrainingItem = nil
            return
        }

        currentTrainingItem = remainingTrainingItems.removeFirst()
    }

    func incrementFailedAttempts() {
        failedAttemptsOnCurrentCard += 1
    }

    func buildTrainingDeck(
        listStore: VocabularyListStore,
        launchContext: TrainingLaunchContext?,
        selectedAppDirection: Direction
    ) -> [VocabularyItem] {
        TrainingDeckBuilder.buildDeck(
            from: activeItems(
                from: listStore,
                selectedAppDirection: selectedAppDirection,
                launchContext: launchContext
            )
        )
    }
}
