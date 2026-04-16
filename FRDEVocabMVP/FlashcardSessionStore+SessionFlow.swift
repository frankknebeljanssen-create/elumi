import Foundation

extension FlashcardSessionStore {
    func startOrResumeSession() {
        if hasActiveSession {
            if currentCard == nil {
                chooseNextCard(avoiding: nil)
            }
            return
        }

        resetGamificationCounters()
        let ids = selectedDeck.cards.map(\.id)
        let firstID = ids.randomElement()
        session = FlashcardSessionState(
            deckID: selectedDeck.id,
            direction: selectedDirection,
            remainingCardIDs: ids,
            currentCardID: firstID,
            correctCount: 0,
            wrongCount: 0,
            isCompleted: ids.isEmpty
        )
    }

    /// Setzt Combo-Tracking + Mastered-Counter zurück. Wird bei jedem
    /// neuen Session-Start aufgerufen.
    func resetGamificationCounters() {
        sessionCurrentCombo = 0
        sessionLongestCombo = 0
        sessionMasteredThisRun = 0
        sessionRewardConsumed = false
    }

    func restartSession() {
        resetGamificationCounters()
        let ids = selectedDeck.cards.map(\.id)
        session = FlashcardSessionState(
            deckID: selectedDeck.id,
            direction: selectedDirection,
            remainingCardIDs: ids,
            currentCardID: ids.randomElement(),
            correctCount: 0,
            wrongCount: 0,
            isCompleted: ids.isEmpty
        )
    }

    func restoreSession(_ restoredSession: FlashcardSessionState) {
        guard restoredSession.deckID == selectedDeckID,
              restoredSession.direction == selectedDirection else { return }

        session = restoredSession
        ensureValidSession()
    }

    func markCorrect() {
        guard var session, let currentCardID = session.currentCardID else { return }

        // Update mastery
        var mastery = session.cardMastery[currentCardID] ?? CardMastery()
        mastery.markCorrect()
        session.cardMastery[currentCardID] = mastery
        session.correctCount += 1

        // Combo-Tracking für ProgressService (Combo-Bonus alle 5 in Folge).
        sessionCurrentCombo += 1
        sessionLongestCombo = max(sessionLongestCombo, sessionCurrentCombo)
        GamificationFeedbackPresenter.shared.noteComboProgress(currentCombo: sessionCurrentCombo)

        // Karte aus dem Stapel entfernen, wenn die konfigurierte Schwelle
        // (1/2/3 richtige Antworten hintereinander) erreicht ist.
        if mastery.consecutiveCorrect >= max(1, masteryThreshold) {
            session.remainingCardIDs.removeAll { $0 == currentCardID }
            sessionMasteredThisRun += 1
        }

        if session.remainingCardIDs.isEmpty {
            session.currentCardID = nil
            session.isCompleted = true
            self.session = session
            return
        }

        self.session = session
        chooseNextCard(avoiding: currentCardID)
    }

    func markWrong() {
        guard var session, let currentCardID = session.currentCardID else { return }

        // Reset mastery to open
        var mastery = session.cardMastery[currentCardID] ?? CardMastery()
        mastery.markWrong()
        session.cardMastery[currentCardID] = mastery
        session.wrongCount += 1

        // Combo bricht ab — `sessionLongestCombo` bleibt erhalten.
        sessionCurrentCombo = 0

        self.session = session
        chooseNextCard(avoiding: currentCardID)
    }

    func chooseNextCard(avoiding currentID: String?) {
        guard var session else { return }

        // Aktuelle Karte in den „recent"-Puffer schieben, damit sie (und die
        // letzten paar davor) bei der Zufallswahl gemieden wird. Bei kleinen
        // Stapeln wird der Puffer entsprechend klein gehalten, sonst bleibt
        // keine wählbare Karte übrig.
        if let currentID {
            recentCardIDs.removeAll { $0 == currentID }
            recentCardIDs.append(currentID)
        }
        let maxRecent = max(1, min(4, session.remainingCardIDs.count - 1))
        if recentCardIDs.count > maxRecent {
            recentCardIDs.removeFirst(recentCardIDs.count - maxRecent)
        }

        let recentSet = Set(recentCardIDs)
        let filtered = session.remainingCardIDs.filter { !recentSet.contains($0) }
        let candidates: [String]
        if !filtered.isEmpty {
            candidates = filtered
        } else if let currentID, session.remainingCardIDs.count > 1 {
            // Fallback: alles recent → wenigstens die unmittelbar aktuelle Karte meiden.
            candidates = session.remainingCardIDs.filter { $0 != currentID }
        } else {
            candidates = session.remainingCardIDs
        }

        session.currentCardID = candidates.randomElement() ?? session.remainingCardIDs.randomElement()
        self.session = session
    }

    func ensureValidSession() {
        guard let firstDeck = decks.first else { return }
        if !decks.contains(where: { $0.id == selectedDeckID }) {
            selectedDeckID = firstDeck.id
        }

        if !availableDirections.contains(selectedDirection), let fallbackDirection = availableDirections.first {
            selectedDirection = fallbackDirection
            return
        }

        guard let session else { return }
        guard session.deckID == selectedDeckID, session.direction == selectedDirection else {
            self.session = nil
            return
        }

        let validIDs = Set(selectedDeck.cards.map(\.id))
        let remaining = session.remainingCardIDs.filter { validIDs.contains($0) }
        let currentIsValid = session.currentCardID.map { validIDs.contains($0) } ?? false

        var updated = session
        updated.remainingCardIDs = remaining
        updated.currentCardID = currentIsValid ? session.currentCardID : remaining.randomElement()
        updated.isCompleted = remaining.isEmpty
        self.session = updated
    }
}
