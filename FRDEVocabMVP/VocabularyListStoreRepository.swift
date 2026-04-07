import Foundation

final class VocabularyListStoreRepository {
    private enum Storage {
        static let customListsFileName = "vocabulary-lists-v2.json"
    }

    private let userDefaults: UserDefaults
    private let snapshotLock = NSLock()
    private var preloadedSnapshot: VocabularyListStoreSnapshot?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func prewarmStoredStateIfNeeded(
        customListsKey: String,
        selectedListKey: String,
        sampleListsSeededKey: String,
        builtInListID: UUID,
        sampleSeeds: [SampleVocabularyListSeed]
    ) {
        snapshotLock.lock()
        let hasCachedSnapshot = preloadedSnapshot != nil
        snapshotLock.unlock()
        guard !hasCachedSnapshot else { return }

        let snapshot = loadSnapshotFromDefaults(
            customListsKey: customListsKey,
            selectedListKey: selectedListKey,
            sampleListsSeededKey: sampleListsSeededKey,
            builtInListID: builtInListID,
            sampleSeeds: sampleSeeds
        )
        cache(snapshot)
    }

    func loadSnapshot(
        customListsKey: String,
        selectedListKey: String,
        sampleListsSeededKey: String,
        builtInListID: UUID,
        sampleSeeds: [SampleVocabularyListSeed]
    ) -> VocabularyListStoreSnapshot {
        snapshotLock.lock()
        if let preloadedSnapshot {
            snapshotLock.unlock()
            return preloadedSnapshot
        }
        snapshotLock.unlock()

        let snapshot = loadSnapshotFromDefaults(
            customListsKey: customListsKey,
            selectedListKey: selectedListKey,
            sampleListsSeededKey: sampleListsSeededKey,
            builtInListID: builtInListID,
            sampleSeeds: sampleSeeds
        )
        cache(snapshot)
        return snapshot
    }

    func cachedSnapshot() -> VocabularyListStoreSnapshot? {
        snapshotLock.lock()
        let snapshot = preloadedSnapshot
        snapshotLock.unlock()
        return snapshot
    }

    func persistCustomLists(
        _ customLists: [VocabularyList],
        key: String,
        snapshot: VocabularyListStoreSnapshot
    ) {
        if let data = try? JSONEncoder().encode(customLists) {
            AppPersistenceSupport.writeData(data, named: Storage.customListsFileName)
            userDefaults.removeObject(forKey: key)
        }
        cache(snapshot)
    }

    func persistSelectedListID(
        _ selectedListID: UUID,
        key: String,
        snapshot: VocabularyListStoreSnapshot
    ) {
        userDefaults.set(selectedListID.uuidString, forKey: key)
        cache(snapshot)
    }

    private func cache(_ snapshot: VocabularyListStoreSnapshot) {
        snapshotLock.lock()
        preloadedSnapshot = snapshot
        snapshotLock.unlock()
    }

    private func loadSnapshotFromDefaults(
        customListsKey: String,
        selectedListKey: String,
        sampleListsSeededKey: String,
        builtInListID: UUID,
        sampleSeeds: [SampleVocabularyListSeed]
    ) -> VocabularyListStoreSnapshot {
        var loadedCustomLists: [VocabularyList] = []
        var shouldPersistMigratedLists = false

        if let data = AppPersistenceSupport.readData(
            named: Storage.customListsFileName,
            legacyDefaults: userDefaults,
            legacyKey: customListsKey
        ),
           let decoded = try? JSONDecoder().decode([VocabularyList].self, from: data) {
            loadedCustomLists = decoded
        }

        if !userDefaults.bool(forKey: sampleListsSeededKey) {
            for seed in sampleSeeds {
                guard !loadedCustomLists.contains(where: {
                    $0.name.localizedCaseInsensitiveCompare(seed.name) == .orderedSame
                }) else { continue }

                loadedCustomLists.append(
                    VocabularyList(
                        name: seed.name,
                        items: seed.items,
                        isBuiltIn: false,
                        collectionPreset: seed.collectionPreset
                    )
                )
            }

            userDefaults.set(true, forKey: sampleListsSeededKey)
            shouldPersistMigratedLists = true
        }

        let selectedListID: UUID
        if let rawID = userDefaults.string(forKey: selectedListKey),
           let decodedID = UUID(uuidString: rawID),
           decodedID == builtInListID || loadedCustomLists.contains(where: { $0.id == decodedID }) {
            selectedListID = decodedID
        } else {
            selectedListID = builtInListID
        }

        let snapshot = VocabularyListStoreSnapshot(
            customLists: loadedCustomLists,
            selectedListID: selectedListID
        )

        if shouldPersistMigratedLists,
           let data = try? JSONEncoder().encode(loadedCustomLists) {
            AppPersistenceSupport.writeData(data, named: Storage.customListsFileName)
            userDefaults.removeObject(forKey: customListsKey)
        }

        return snapshot
    }
}
