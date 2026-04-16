import Foundation

extension TrainingSessionController {
    func resetTrainingSessionState() {
        print("🏋️ [Session] resetTrainingSessionState called, was hasStarted=\(hasStartedTraining)")
        hasStartedTraining = false
        isSpeedRound = false
        isShowingSetup = true
        isShowingRoundComplete = false
        completedRound = 0
        failedAttemptsOnCurrentCard = 0
        currentTrainingItem = nil
        preparedTrainingItems = []
        remainingTrainingItems = []
        // Symmetrisch zu `VerbformsSessionController.reset()`: beim harten
        // Session-Reset auch die Gamification-Counters weglegen, damit keine
        // Altwerte in die nächste Session hineinbluten.
        resetGamificationCounters()
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
        resetGamificationCounters()
        loadNextTrainingCard()
        return currentTrainingItem != nil
    }

    func loadNextTrainingCard() {
        let previousItem = currentTrainingItem
        failedAttemptsOnCurrentCard = 0

        if remainingTrainingItems.isEmpty {
            // First call after startTraining: completedRound is 0, just shuffle
            // Subsequent rounds: show round-complete celebration
            if completedRound > 0, hasStartedTraining, !isSpeedRound, !preparedTrainingItems.isEmpty {
                isShowingRoundComplete = true
                return
            }
            completedRound += 1
            remainingTrainingItems = TrainingDeckBuilder.shuffledRound(
                from: preparedTrainingItems,
                avoiding: previousItem
            )
        }

        guard !remainingTrainingItems.isEmpty else {
            print("🏋️ [Training] ❌ no cards left! prepared=\(preparedTrainingItems.count) remaining=\(remainingTrainingItems.count)")
            hasStartedTraining = false
            currentTrainingItem = nil
            return
        }

        currentTrainingItem = remainingTrainingItems.removeFirst()
    }

    func continueNextRound() {
        isShowingRoundComplete = false
        completedRound += 1
        let previousItem = currentTrainingItem
        remainingTrainingItems = TrainingDeckBuilder.shuffledRound(
            from: preparedTrainingItems,
            avoiding: previousItem
        )
        guard !remainingTrainingItems.isEmpty else { return }
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
