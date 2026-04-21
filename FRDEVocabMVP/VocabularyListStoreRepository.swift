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
            // **Redundanter Backup-Pfad** (Safety-Net gegen Datei-
            // Level-Verlust): zusätzlich eine Kopie in UserDefaults.
            // Wenn die Haupt-Datei irgendwie weg kommt (iCloud-Sync-
            // Glitch, Simulator-Quirk, Dev-Wipe), hat `loadSnapshotFromDefaults`
            // diesen Fallback-Weg über `AppPersistenceSupport.readData
            // (legacyDefaults:, legacyKey:)`. Der Pfad existierte
            // bereits für die ursprüngliche Migration UserDefaults→Datei;
            // wir reaktivieren ihn jetzt als dauerhaftes Backup.
            userDefaults.set(data, forKey: key)
            #if DEBUG
            print("💾 [ListStore.save] \(customLists.count) custom lists persisted " +
                  "(file + UserDefaults backup, \(data.count) bytes)")
            #endif
        } else {
            #if DEBUG
            print("❌ [ListStore.save] JSON encoding failed — data NOT saved!")
            #endif
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
        var loadSource = "none"

        if let data = AppPersistenceSupport.readData(
            named: Storage.customListsFileName,
            legacyDefaults: userDefaults,
            legacyKey: customListsKey
        ),
           let decoded = try? JSONDecoder().decode([VocabularyList].self, from: data) {
            loadedCustomLists = decoded
            loadSource = decoded.isEmpty ? "file-empty" : "file"
        }

        // **Recovery-Pfad** (Safety-Net): Wenn die Datei leer zurückkam
        // oder fehlschlug, aber der parallele UserDefaults-Backup-Key
        // noch Daten hat → von dort wiederherstellen. Das schützt
        // gegen Szenarien wie Application-Support-Ordner-Wipe durch
        // externe Tools (Dev-Klones, iCloud-Sync-Konflikte, Simulator-
        // Quirks).
        if loadedCustomLists.isEmpty {
            if let backup = userDefaults.data(forKey: customListsKey),
               let decoded = try? JSONDecoder().decode([VocabularyList].self, from: backup),
               !decoded.isEmpty {
                loadedCustomLists = decoded
                loadSource = "userDefaults-recovery"
                shouldPersistMigratedLists = true  // zurück in die Datei schreiben
                #if DEBUG
                print("⚠️ [ListStore.load] file was empty/missing — recovered \(decoded.count) lists from UserDefaults backup")
                #endif
            }
        }

        #if DEBUG
        if loadedCustomLists.isEmpty {
            print("⚠️ [ListStore.load] WARNING: no custom lists found (source=\(loadSource)). " +
                  "Fresh install OR data loss — check `Persistence/\(Storage.customListsFileName)` " +
                  "and UserDefaults key `\(customListsKey)`.")
        } else {
            print("📦 [ListStore.load] \(loadedCustomLists.count) custom lists loaded from \(loadSource)")
        }
        #endif

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
