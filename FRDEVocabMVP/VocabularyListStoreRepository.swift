import Foundation

final class VocabularyListStoreRepository {
    enum Storage {
        /// **Globales** Legacy-File, pre-Multi-Account. Bleibt als
        /// Quelle für die einmalige Migration in den ersten Account
        /// stehen. Nach erfolgreicher Migration liest/schreibt die
        /// App ausschließlich in den per-Account-scoped Filenamen
        /// (siehe `accountScopedFileName(for:)`).
        static let customListsFileName = "vocabulary-lists-v2.json"

        /// Per-Account-Filename für die Custom-Listen. Account-UUID
        /// ist Teil des Dateinamens, damit jeder Account seinen
        /// eigenen JSON-Blob auf Disk hat.
        static func accountScopedFileName(for accountID: UUID) -> String {
            "vocabulary-lists-v2-\(accountID.uuidString).json"
        }
    }

    private let userDefaults: UserDefaults
    private let snapshotLock = NSLock()
    private var preloadedSnapshot: VocabularyListStoreSnapshot?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    /// Invalidiert den internen Snapshot-Cache. Wird nach einem
    /// Account-Wechsel vom Store gerufen, damit der nächste
    /// `loadSnapshot(...)` wieder von Disk/UserDefaults für den
    /// neuen Account liest statt den Cache des vorigen Accounts zu
    /// retourneren.
    func invalidateCache() {
        snapshotLock.lock()
        preloadedSnapshot = nil
        snapshotLock.unlock()
    }

    /// Aktuell gültige Account-ID für den File-Namen. Wird vom Store
    /// (MainActor) synchron via `setCurrentAccount(_:)` gesetzt, bevor
    /// irgendeine Persist-/Load-Methode läuft. Die Repository selbst
    /// ist **nicht** MainActor — sie lebt auf einem Background-Queue
    /// für I/O — deshalb kein direkter `AccountStore.shared`-Zugriff.
    private var currentAccountIDScope: UUID?

    /// Setter vom Store: vor jedem Load/Persist muss die aktive
    /// Account-ID (oder nil bei globalem Fallback) reingereicht
    /// werden. Gekapselt, damit Call-Sites den Zustand nicht
    /// versehentlich vergessen.
    func setCurrentAccount(_ accountID: UUID?) {
        currentAccountIDScope = accountID
    }

    /// Liefert den aktuell gültigen File-Namen für die Custom-Listen —
    /// per-Account, sofern ein Account aktiv ist, sonst der globale
    /// Legacy-Name.
    fileprivate func currentScopedFileName() -> String {
        if let id = currentAccountIDScope {
            return Storage.accountScopedFileName(for: id)
        }
        return Storage.customListsFileName
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
            AppPersistenceSupport.writeData(data, named: currentScopedFileName())
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
            named: currentScopedFileName(),
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
            AppPersistenceSupport.writeData(data, named: currentScopedFileName())
            userDefaults.removeObject(forKey: customListsKey)
        }

        return snapshot
    }
}
