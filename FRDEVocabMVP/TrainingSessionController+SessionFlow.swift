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
        // Harter Reset → auch Resume-Snapshot verwerfen. Wenn der Nutzer
        // „Fertig" drückt oder die Session regulär beendet, soll beim
        // nächsten Setup nichts mehr im Persistence-Ordner liegen, das
        // unbemerkt weiterlaufen würde.
        clearResumeSnapshot()
    }

    func returnToSetup() {
        isShowingSetup = true
    }

    func startTraining(
        listStore: VocabularyListStore,
        launchContext: TrainingLaunchContext?,
        selectedAppDirection: Direction
    ) -> Bool {
        // Session-Resume: erst prüfen, ob ein kompatibler Snapshot
        // vorliegt. Speed Round wird hier ausgelassen — Timer-basierte
        // Runden haben kein sinnvolles Fortsetzen; der Snapshot-Pfad
        // selbst schreibt in Speed Round ohnehin nichts raus.
        //
        // Launch-Context (z. B. Tap auf eine spezifische Liste von der
        // Home-Kachel) **umgeht** den Resume. Wir sehen das als explizite
        // Absicht des Nutzers, eine neue, kontextspezifische Session zu
        // starten. Ohne Launch-Context (Start aus dem Training-Setup)
        // greift der Resume.
        // `selectedAppDirection` (globaler @AppStorage-Wert) ist die
        // Wahrheits-Direction — lokaler `direction`-State auf dem
        // Controller wird nicht überall gepflegt. Wir schreiben ihn
        // einmal hier synchron, damit Save/Resume konsistent bleiben.
        direction = selectedAppDirection

        if launchContext == nil, !isSpeedRound {
            let restored = tryRestoreResumeSnapshot(
                expectedMode: trainingMode,
                expectedDirection: selectedAppDirection,
                expectedCardType: cardType,
                expectedListIDs: Array(selectedTrainingListIDs)
            )
            if restored {
                return currentTrainingItem != nil
            }
        }

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
        // Frische Session startet mit leerem Resume-Snapshot — ein
        // eventuell noch liegender Snapshot von einer früheren
        // Konfiguration wird weggeräumt.
        clearResumeSnapshot()
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
        // Snapshot auf jeden Karten-Wechsel aktualisieren — so trifft
        // der User beim Resume immer die **nächste** offene Karte, nie
        // eine bereits beantwortete.
        persistResumeSnapshotIfEligible()
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
