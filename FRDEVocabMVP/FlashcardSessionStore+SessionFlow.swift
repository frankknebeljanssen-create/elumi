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
        // **Personal-Deck-Resume (User-Revision 2026-04-22)**: Wenn ein
        // Personal-Deck aktiv ist, hat der Aufrufer die Karten BEREITS
        // in der richtigen Reihenfolge (ab `deck.currentIndex`) übergeben.
        // Wir starten daher bei `ids.first`, NICHT zufällig — sonst wirft
        // der Resume den gespeicherten Cursor weg.
        let firstID: String? = (activePersonalDeckID != nil)
            ? ids.first
            : ids.randomElement()
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
        streak.reset()
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
        // Streak aus dem Snapshot in den in-memory-Tracker zurückspielen —
        // ohne diesen Schritt startet die fortgesetzte Session mit Combo 0,
        // obwohl der User gerade 4× in Folge richtig beantwortet hat.
        streak = restoredSession.streak
        ensureValidSession()
    }

    func markCorrect() {
        guard var session, let currentCardID = session.currentCardID else { return }

        // Lernstatus-Signal: **vor** der Session-Mutation aus der
        // aktuellen Karte ziehen. `currentCard` resolv't über den noch
        // nicht überschriebenen `session.currentCardID`. Die Direction
        // spielt hier **keine** Rolle für den Store-Schlüssel (der basiert
        // rein auf french/german/cardType), muss also nicht mit übergeben
        // werden — der Store aggregiert automatisch über beide Richtungen.
        if let card = currentCard {
            ItemLearningStatusRecorder.record(
                french: card.french,
                german: card.german,
                cardType: card.cardType,
                correct: true
            )
        }

        // Update mastery
        var mastery = session.cardMastery[currentCardID] ?? CardMastery()
        mastery.markCorrect()
        session.cardMastery[currentCardID] = mastery
        session.correctCount += 1

        // Combo-Tracking für ProgressService (Combo-Bonus alle 5 in Folge).
        // Karteikarten haben pro Karte genau einen Antwort-Tap — deshalb
        // ist `firstAttempt` hier immer `true` und wird über den Default
        // der Convenience-API mitgenommen.
        streak.recordCorrect()
        // Streak-Snapshot in die `FlashcardSessionState` schreiben, damit
        // ein Resume den Combo-Stand nicht verliert. Persistiert
        // automatisch über den `didSet` auf `session`.
        session.streak = streak

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

    /// **Stufe 4b-1 (2026-05-01, Branch `feature/training-session-flow`)** —
    /// Forciert das Session-Ende durch den Chain-Timer-Soft-Cutoff.
    /// Wird vom `FlashcardsSessionController.scheduleNextPrompt`-Pfad
    /// gerufen, sobald die laufende Eval-Auswertung komplett durch ist
    /// und der Chain-Timer abgelaufen war (`TrainingChainStore.shared.
    /// timerExpired == true`). Setzt `isCompleted = true` plus räumt
    /// `currentCardID` ab — das ist genau die Mutation, die auch der
    /// natürliche „letzte Karte erledigt"-Pfad oben (Z. 108-113)
    /// vornimmt. Folgewirkung: `flashcardCompletionCard` rendert,
    /// `consumeFlashcardSessionReward()` läuft, und der Chain-aware
    /// Done-CTA aus Stufe 3 (`appChainAdvanceAction`) wird beim Tap
    /// auf „Weiter zu …" gerufen.
    ///
    /// Idempotent: ein zweiter Aufruf während der Done-Card sichtbar
    /// ist, ist ein No-Op (`isCompleted` ist schon `true`).
    func markCurrentSessionDoneFromChainTimer() {
        guard var session = self.session, !session.isCompleted else { return }
        session.currentCardID = nil
        session.isCompleted = true
        self.session = session
        #if DEBUG
        print("🛑 [Flashcards] Force-Done via chain-timer-soft-cutoff")
        #endif
    }

    /// **Peek-Protection (User-Revision 2026-04-22)**: Setzt den
    /// `consecutiveCorrect`-Counter einer Karte hart auf 0 zurück und
    /// markiert sie als „falsch". Wird aufgerufen, wenn der User die
    /// Karte manuell umdreht, ohne sie beantwortet zu haben —
    /// „spicken" darf keine Streaks bauen.
    ///
    /// Unterschied zu `markWrong()`: hier wird kein `wrongCount` erhöht,
    /// keine Combo gebrochen und das Lernstatus-Signal nicht getriggert —
    /// es ist ein reiner Mastery-Reset, kein echter Falsch-Tap.
    func resetMasteryDueToPeek(cardID: String) {
        guard var session else { return }
        var mastery = session.cardMastery[cardID] ?? CardMastery()
        mastery.consecutiveCorrect = 0
        mastery.hasBeenWrong = true
        session.cardMastery[cardID] = mastery
        self.session = session
    }

    /// Verschiebt die aktuelle Karte ans Ende des `remainingCardIDs`-
    /// Arrays und wählt die nächste Karte. Wird vom Peek-Flow
    /// aufgerufen, damit eine gepeekte Karte im aktuellen Durchgang
    /// nochmal drankommt — ohne dass ein „richtig" gewertet wird.
    func moveCurrentCardToEndAndAdvance() {
        guard var session, let currentCardID = session.currentCardID else { return }
        session.remainingCardIDs.removeAll { $0 == currentCardID }
        session.remainingCardIDs.append(currentCardID)
        self.session = session
        chooseNextCard(avoiding: currentCardID)
    }

    func markWrong() {
        guard var session, let currentCardID = session.currentCardID else { return }

        // Lernstatus-Signal (Gegenstück zu `markCorrect`): siehe dort für
        // die Rationale. Für das Tracking ist es wichtig, dass genau
        // **ein** Signal pro Antwort läuft — hier der Wrong-Path.
        if let card = currentCard {
            ItemLearningStatusRecorder.record(
                french: card.french,
                german: card.german,
                cardType: card.cardType,
                correct: false
            )
        }

        // Reset mastery to open
        var mastery = session.cardMastery[currentCardID] ?? CardMastery()
        mastery.markWrong()
        session.cardMastery[currentCardID] = mastery
        session.wrongCount += 1

        // Combo bricht ab — `longest` bleibt in `streak` erhalten.
        streak.recordWrong()
        // Auch bei falschen Antworten den Snapshot aktualisieren, damit
        // ein Resume den Reset auf 0 widerspiegelt (sonst könnte der
        // alte Combo-Stand nach Unterbrechung wieder sichtbar werden).
        session.streak = streak

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
