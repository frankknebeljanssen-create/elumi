import Foundation

final class FlashcardSessionRepository {
    private enum Storage {
        static let sessionFileName = "flashcard-session-v1.json"
    }

    private let userDefaults: UserDefaults
    private let snapshotLock = NSLock()
    private var preloadedSnapshot: FlashcardSessionStoreSnapshot?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func prewarmStoredStateIfNeeded(
        defaultDeckID: String,
        selectedDeckKey: String,
        selectedDirectionKey: String,
        sessionKey: String
    ) {
        snapshotLock.lock()
        let hasCachedSnapshot = preloadedSnapshot != nil
        snapshotLock.unlock()
        guard !hasCachedSnapshot else { return }

        let snapshot = loadSnapshotFromStorage(
            defaultDeckID: defaultDeckID,
            selectedDeckKey: selectedDeckKey,
            selectedDirectionKey: selectedDirectionKey,
            sessionKey: sessionKey
        )
        cache(snapshot)
    }

    func loadSnapshot(
        defaultDeckID: String,
        selectedDeckKey: String,
        selectedDirectionKey: String,
        sessionKey: String
    ) -> FlashcardSessionStoreSnapshot {
        snapshotLock.lock()
        if let preloadedSnapshot {
            snapshotLock.unlock()
            return preloadedSnapshot
        }
        snapshotLock.unlock()

        let snapshot = loadSnapshotFromStorage(
            defaultDeckID: defaultDeckID,
            selectedDeckKey: selectedDeckKey,
            selectedDirectionKey: selectedDirectionKey,
            sessionKey: sessionKey
        )
        cache(snapshot)
        return snapshot
    }

    func cachedSnapshot() -> FlashcardSessionStoreSnapshot? {
        snapshotLock.lock()
        let snapshot = preloadedSnapshot
        snapshotLock.unlock()
        return snapshot
    }

    func persistSelectedDeckID(_ selectedDeckID: String, key: String) {
        userDefaults.set(selectedDeckID, forKey: key)
        snapshotLock.lock()
        if let snapshot = preloadedSnapshot {
            preloadedSnapshot = FlashcardSessionStoreSnapshot(
                selectedDeckID: selectedDeckID,
                selectedDirection: snapshot.selectedDirection,
                session: snapshot.session
            )
        }
        snapshotLock.unlock()
    }

    func persistSelectedDirection(_ selectedDirection: Direction, key: String) {
        userDefaults.set(selectedDirection.rawValue, forKey: key)
        snapshotLock.lock()
        if let snapshot = preloadedSnapshot {
            preloadedSnapshot = FlashcardSessionStoreSnapshot(
                selectedDeckID: snapshot.selectedDeckID,
                selectedDirection: selectedDirection,
                session: snapshot.session
            )
        }
        snapshotLock.unlock()
    }

    func persistSessionData(_ data: Data?, key: String) {
        if let data {
            AppPersistenceSupport.writeData(data, named: Storage.sessionFileName)
            userDefaults.removeObject(forKey: key)
        } else {
            AppPersistenceSupport.removeData(named: Storage.sessionFileName)
            userDefaults.removeObject(forKey: key)
        }

        let decodedSession = data.flatMap { try? JSONDecoder().decode(FlashcardSessionState.self, from: $0) }
        snapshotLock.lock()
        if let snapshot = preloadedSnapshot {
            preloadedSnapshot = FlashcardSessionStoreSnapshot(
                selectedDeckID: snapshot.selectedDeckID,
                selectedDirection: snapshot.selectedDirection,
                session: decodedSession
            )
        }
        snapshotLock.unlock()
    }

    private func loadSnapshotFromStorage(
        defaultDeckID: String,
        selectedDeckKey: String,
        selectedDirectionKey: String,
        sessionKey: String
    ) -> FlashcardSessionStoreSnapshot {
        let selectedDeckID = userDefaults.string(forKey: selectedDeckKey) ?? defaultDeckID

        let selectedDirection: Direction
        if let rawDirection = userDefaults.string(forKey: selectedDirectionKey),
           let decodedDirection = Direction(rawValue: rawDirection) {
            selectedDirection = decodedDirection
        } else {
            selectedDirection = .frenchToGerman
        }

        let session: FlashcardSessionState?
        if let data = AppPersistenceSupport.readData(
            named: Storage.sessionFileName,
            legacyDefaults: userDefaults,
            legacyKey: sessionKey
        ),
           let decoded = try? JSONDecoder().decode(FlashcardSessionState.self, from: data) {
            session = decoded
        } else {
            session = nil
        }

        return FlashcardSessionStoreSnapshot(
            selectedDeckID: selectedDeckID,
            selectedDirection: selectedDirection,
            session: session
        )
    }

    private func cache(_ snapshot: FlashcardSessionStoreSnapshot) {
        snapshotLock.lock()
        preloadedSnapshot = snapshot
        snapshotLock.unlock()
    }
}
