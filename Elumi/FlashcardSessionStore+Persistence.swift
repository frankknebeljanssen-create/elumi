import Foundation

extension FlashcardSessionStore {
    func persistSessionIfNeeded() {
        pendingSessionSaveWorkItem?.cancel()

        if session == nil || session?.isCompleted == true {
            saveSessionNow()
            return
        }

        let workItem = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.saveSessionNow()
            }
        }
        pendingSessionSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + sessionSaveDelay, execute: workItem)
    }

    func saveSessionNow() {
        pendingSessionSaveWorkItem?.cancel()
        pendingSessionSaveWorkItem = nil

        if let session, let data = try? JSONEncoder().encode(session) {
            guard data != lastPersistedSessionData else { return }
            repository.persistSessionData(data, key: sessionKey)
            lastPersistedSessionData = data
        } else {
            guard lastPersistedSessionData != nil else { return }
            repository.persistSessionData(nil, key: sessionKey)
            lastPersistedSessionData = nil
        }
    }

    /// Liest Stapelwahl, Richtung und laufende Session des jetzt
    /// aktiven Accounts neu ein.
    ///
    /// **Codeaudit 2026-09-03, Stufe 3 (Punkt 18)** — der Store lebt im
    /// `AppRuntimeContainer` und ueberlebt den Account-Wechsel. Ohne
    /// diesen Reload lief die halb fertige Karteikarten-Session des
    /// vorigen Kindes beim neuen weiter, und der naechste debounced
    /// Save haette sie in dessen Slot geschrieben.
    ///
    /// Reihenfolge ist hier wichtig: erst den ausstehenden Save
    /// abbrechen (er traegt noch die Daten des alten Accounts), dann
    /// `lastPersistedSessionData` auf den frisch geladenen Stand
    /// setzen, damit das `didSet` auf `session` keinen ueberfluessigen
    /// Schreibvorgang ausloest.
    func reloadForCurrentAccount() {
        pendingSessionSaveWorkItem?.cancel()
        pendingSessionSaveWorkItem = nil

        let defaultDeckID = DataStore.flashcardDecks.first?.id ?? "flashcards-1"
        let snapshot = repository.loadSnapshot(
            defaultDeckID: defaultDeckID,
            selectedDeckKey: selectedDeckKey,
            selectedDirectionKey: selectedDirectionKey,
            sessionKey: sessionKey
        )

        lastPersistedSessionData = snapshot.session.flatMap { try? JSONEncoder().encode($0) }
        selectedDeckID = isTransientCustomDeckID(snapshot.selectedDeckID)
            ? defaultDeckID
            : snapshot.selectedDeckID
        selectedDirection = snapshot.selectedDirection
        if let loaded = snapshot.session, isTransientCustomDeckID(loaded.deckID) {
            session = nil
        } else {
            session = snapshot.session
        }

        // Eine Personal-Deck-Session gehoert immer dem vorigen Account.
        activePersonalDeckID = nil
        ensureValidSession()
    }

    func isTransientCustomDeckID(_ deckID: String) -> Bool {
        deckID.hasPrefix("custom-")
    }
}
