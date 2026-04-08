import Foundation

extension FlashcardSessionStore {
    func startOrResumeSession() {
        if hasActiveSession {
            if currentCard == nil {
                chooseNextCard(avoiding: nil)
            }
            return
        }

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

    func restartSession() {
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

        // Only remove from remaining if mastered (2+ consecutive correct)
        if mastery.level == .mastered {
            session.remainingCardIDs.removeAll { $0 == currentCardID }
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

        self.session = session
        chooseNextCard(avoiding: currentCardID)
    }

    func chooseNextCard(avoiding currentID: String?) {
        guard var session else { return }
        let candidates: [String]
        if let currentID, session.remainingCardIDs.count > 1 {
            let filtered = session.remainingCardIDs.filter { $0 != currentID }
            candidates = filtered.isEmpty ? session.remainingCardIDs : filtered
        } else {
            candidates = session.remainingCardIDs
        }

        session.currentCardID = candidates.randomElement()
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
