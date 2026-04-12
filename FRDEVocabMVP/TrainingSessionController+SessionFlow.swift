import Foundation

extension TrainingSessionController {
    func resetTrainingSessionState() {
        print("🏋️ [Session] resetTrainingSessionState called, was hasStarted=\(hasStartedTraining)")
        hasStartedTraining = false
        isSpeedRound = false
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
            print("🏋️ [Training] reshuffled: prepared=\(preparedTrainingItems.count) → remaining=\(remainingTrainingItems.count)")
        }

        guard !remainingTrainingItems.isEmpty else {
            print("🏋️ [Training] ❌ no cards left! prepared=\(preparedTrainingItems.count) remaining=\(remainingTrainingItems.count)")
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
        let items = activeItems(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )
        print("🏋️ [Training] buildDeck: mode=\(trainingMode) cardType=\(cardType) items=\(items.count)")
        return TrainingDeckBuilder.buildDeck(from: items)
    }
}
