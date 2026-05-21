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

    /// Obergrenze für den UserDefaults-Backup-Blob (~3 MB). Größere
    /// `customLists`-Payloads (z. B. nach Kopieren von Built-in-Listen)
    /// werden NICHT mehr in UserDefaults gespiegelt — ein zu großer Blob
    /// kann die UserDefaults-plist destabilisieren (Diagnose 2026-05-21).
    /// Datei + LKG bleiben als zwei vollwertige Sicherungs-Ebenen.
    private static let maxUDBackupBytes = 3_000_000

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

    /// **Last-Known-Good-Backup** (Persistenz-Schutz 2026-04-23 nacht):
    /// neben der Hauptdatei pflegen wir eine `.lastKnownGood.json`-Kopie,
    /// die nur dann aktualisiert wird, wenn der Save mit **nicht-leerem**
    /// Inhalt erfolgreich durchläuft. Falls die Hauptdatei je korrupt
    /// wird (Decode-Fehler, leerer Read), wird der LKG-Backup beim
    /// Load als zusätzlicher Recovery-Pfad konsultiert — VOR dem
    /// UserDefaults-Backup.
    fileprivate func currentLastKnownGoodFileName() -> String {
        let main = currentScopedFileName()
        // .json → .lastKnownGood.json
        let base = main.hasSuffix(".json")
            ? String(main.dropLast(".json".count))
            : main
        return "\(base).lastKnownGood.json"
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
        // **Persistenz-Schutz 2026-04-23 nacht**: Pre-Save-Sanity-Check.
        // Wenn der neue Stand drastisch kleiner als der aktuell gecachte
        // ist (z. B. plötzlich leer obwohl vorher 100 Listen drin waren),
        // ist das ein starkes Indiz für einen UI-State-Bug. Wir blockieren
        // den Save NICHT (echte User-Aktionen wie „alles löschen" sind
        // gültig), aber wir loggen LAUT, sodass solche Vorfälle in der
        // Console sofort sichtbar sind.
        let cachedCount = preloadedSnapshot?.customLists.count ?? -1
        let newCount = customLists.count
        if cachedCount > 0 && newCount == 0 {
            #if DEBUG
            appDebugLog("⚠️ [ListStore.save] DANGER: customLists wechselt von \(cachedCount) → 0. " +
                  "Sicher dass das ein User-Action-Reset war? Last-Known-Good bleibt erhalten.")
            #endif
        } else if cachedCount > 10 && newCount < cachedCount / 2 {
            #if DEBUG
            appDebugLog("⚠️ [ListStore.save] DANGER: Listenzahl halbiert sich (\(cachedCount) → \(newCount)). " +
                  "Last-Known-Good bleibt vorerst erhalten.")
            #endif
        }

        guard let data = try? JSONEncoder().encode(customLists) else {
            #if DEBUG
            appDebugLog("❌ [ListStore.save] JSON encoding failed — data NOT saved! " +
                  "Last-Known-Good unverändert, aktueller Cache bleibt.")
            #endif
            return
        }

        AppPersistenceSupport.writeData(data, named: currentScopedFileName())
        // **Redundanter Backup-Pfad** (Safety-Net gegen Datei-Level-
        // Verlust): zusätzlich eine Kopie in UserDefaults — aber nur bis
        // `maxUDBackupBytes`. Große Blobs destabilisieren die
        // UserDefaults-plist; Datei + LKG bleiben als volle Sicherungen.
        if data.count <= Self.maxUDBackupBytes {
            userDefaults.set(data, forKey: key)
        } else {
            // Altes, kleineres UD-Backup entfernen — sonst Mismatch
            // gegenüber der (größeren) Datei beim Recovery.
            userDefaults.removeObject(forKey: key)
            #if DEBUG
            appDebugLog("⚠️ [ListStore.save] Skipping UD backup (\(data.count) bytes > \(Self.maxUDBackupBytes) limit) — File + LKG remain")
            #endif
        }

        // **Last-Known-Good-Update**: nur wenn der neue Stand
        // **non-empty** ist. So bleibt bei einem versehentlichen
        // Leer-Save der LKG-Stand mit den letzten echten Daten erhalten.
        // Caller (z. B. Migrations) können den LKG dadurch nicht
        // versehentlich „leer-überschreiben".
        if newCount > 0 {
            AppPersistenceSupport.writeData(data, named: currentLastKnownGoodFileName())
        }

        #if DEBUG
        appDebugLog("💾 [ListStore.save] \(newCount) custom lists persisted " +
              "(file + UserDefaults + \(newCount > 0 ? "LKG-backup" : "LKG-skipped"), \(data.count) bytes)")
        #endif

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
        // **Persistenz-Schutz 2026-04-23 nacht**: Korruption getrennt
        // tracken. Wenn die Hauptdatei VORHANDEN aber NICHT decodierbar
        // ist, ist das ein Datenverlust-Signal — kein „Fresh Install".
        // In diesem Fall NIEMALS Sample-Seeding triggern (würde die
        // Korruption stillschweigend mit Defaults überschreiben).
        var mainFileWasCorrupt = false

        let fileName = currentScopedFileName()
        let mainFileExisted = AppPersistenceSupport.fileExists(named: fileName)

        if let data = AppPersistenceSupport.readData(
            named: fileName,
            legacyDefaults: userDefaults,
            legacyKey: customListsKey
        ) {
            if let decoded = try? JSONDecoder().decode([VocabularyList].self, from: data) {
                loadedCustomLists = decoded
                loadSource = decoded.isEmpty ? "file-empty" : "file"
            } else {
                // Datei vorhanden, aber Decode fehlgeschlagen → Korruption.
                mainFileWasCorrupt = true
                loadSource = "file-corrupt"
                #if DEBUG
                appDebugLog("🚨 [ListStore.load] CORRUPTION detected: main file present (\(data.count) bytes) but decode failed!")
                #endif
            }
        }

        // **Recovery-Pfad 1**: Last-Known-Good-Backup (höchste Priorität,
        // weil nur befüllt wird, wenn ein erfolgreicher Save mit
        // non-empty Inhalt durchlief).
        if loadedCustomLists.isEmpty {
            let lkgFileName = currentLastKnownGoodFileName()
            if let lkgData = AppPersistenceSupport.readDataIfFileExists(named: lkgFileName),
               let decoded = try? JSONDecoder().decode([VocabularyList].self, from: lkgData),
               !decoded.isEmpty {
                loadedCustomLists = decoded
                loadSource = "last-known-good"
                shouldPersistMigratedLists = true
                #if DEBUG
                appDebugLog("✅ [ListStore.load] recovered \(decoded.count) lists from Last-Known-Good backup")
                #endif
            }
        }

        // **Recovery-Pfad 2**: UserDefaults-Backup (existierte schon
        // vorher — wir lassen es als Doppel-Sicherung drin).
        if loadedCustomLists.isEmpty {
            if let backup = userDefaults.data(forKey: customListsKey),
               let decoded = try? JSONDecoder().decode([VocabularyList].self, from: backup),
               !decoded.isEmpty {
                loadedCustomLists = decoded
                loadSource = "userDefaults-recovery"
                shouldPersistMigratedLists = true
                #if DEBUG
                appDebugLog("⚠️ [ListStore.load] file was empty/missing/corrupt — recovered \(decoded.count) lists from UserDefaults backup")
                #endif
            }
        }

        #if DEBUG
        if loadedCustomLists.isEmpty {
            if mainFileWasCorrupt {
                appDebugLog("🚨 [ListStore.load] CRITICAL: Main file corrupt AND no recovery backup available. " +
                      "Sample-Seeding wird übersprungen, um die Korruption nicht zu verschleiern.")
            } else {
                appDebugLog("ℹ️ [ListStore.load] no custom lists found (source=\(loadSource)). " +
                      "mainFileExisted=\(mainFileExisted) — \(mainFileExisted ? "empty file" : "fresh install").")
            }
        } else {
            appDebugLog("📦 [ListStore.load] \(loadedCustomLists.count) custom lists loaded from \(loadSource)")
        }
        #endif

        // **Persistenz-Schutz 2026-04-23 nacht**: Sample-Seeding NUR,
        // wenn die Hauptdatei nicht korrupt war. Sonst würde ein
        // Decode-Failure stillschweigend zu „neuer Account mit Samples"
        // werden und die echten User-Daten überschrieben werden.
        if !userDefaults.bool(forKey: sampleListsSeededKey) && !mainFileWasCorrupt {
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
            #if DEBUG
            appDebugLog("🌱 [ListStore.load] Sample-Seeding ausgeführt (\(sampleSeeds.count) Seeds geprüft)")
            #endif
        } else if mainFileWasCorrupt {
            #if DEBUG
            appDebugLog("🚨 [ListStore.load] Sample-Seeding ÜBERSPRUNGEN wegen Datei-Korruption — manueller Recovery nötig.")
            #endif
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
