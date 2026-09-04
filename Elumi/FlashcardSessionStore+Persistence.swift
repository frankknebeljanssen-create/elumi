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

    func isTransientCustomDeckID(_ deckID: String) -> Bool {
        deckID.hasPrefix("custom-")
    }
}
