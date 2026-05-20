// ScanDraftStoreRepository.swift
// **Meine Scans — Phase A (2026-05-20)** — Persistenz-Layer für
// `ScanDraft`s. 1:1-Spiegel des `VocabularyListStoreRepository`-Patterns:
//   • Per-Account-File-Namen (`scan-drafts-v1[-<accountID>].json`)
//   • Persist-Tripel: File + UserDefaults-Backup + Last-Known-Good
//   • 3-stufiges Recovery beim Load: main → LKG → UserDefaults
//   • Korruptions-Erkennung (File da, aber Decode-Fail)
//   • Pre-Save-Sanity (warnt bei n→0 / Halbierung)
//
// NICHT MainActor — lebt fürs Disk-I/O auf dem aufrufenden Kontext.
// Die aktive Account-ID wird vom Store synchron via `setCurrentAccount(_:)`
// reingereicht, bevor Load/Persist läuft (analog Vorbild).

import Foundation

final class ScanDraftStoreRepository {
    enum Storage {
        /// Globaler Legacy-Name (pre-Multi-Account-Fallback).
        static let draftsFileName = "scan-drafts-v1.json"

        /// Per-Account-Filename.
        static func accountScopedFileName(for accountID: UUID) -> String {
            "scan-drafts-v1-\(accountID.uuidString).json"
        }
    }

    private let userDefaults: UserDefaults
    private let cacheLock = NSLock()
    private var cachedDrafts: [ScanDraft]?
    private var currentAccountIDScope: UUID?

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    // MARK: - Account-Scope

    func setCurrentAccount(_ accountID: UUID?) {
        currentAccountIDScope = accountID
    }

    /// Invalidiert den Snapshot-Cache (nach Account-Wechsel), damit der
    /// nächste Load wieder von Disk für den neuen Account liest.
    func invalidateCache() {
        cacheLock.lock()
        cachedDrafts = nil
        cacheLock.unlock()
    }

    fileprivate func currentScopedFileName() -> String {
        if let id = currentAccountIDScope {
            return Storage.accountScopedFileName(for: id)
        }
        return Storage.draftsFileName
    }

    fileprivate func currentLastKnownGoodFileName() -> String {
        let main = currentScopedFileName()
        let base = main.hasSuffix(".json")
            ? String(main.dropLast(".json".count))
            : main
        return "\(base).lastKnownGood.json"
    }

    // MARK: - Load

    func loadDrafts(legacyKey: String) -> [ScanDraft] {
        cacheLock.lock()
        if let cachedDrafts {
            cacheLock.unlock()
            return cachedDrafts
        }
        cacheLock.unlock()

        let drafts = loadDraftsFromDisk(legacyKey: legacyKey)
        cache(drafts)
        return drafts
    }

    private func loadDraftsFromDisk(legacyKey: String) -> [ScanDraft] {
        var loaded: [ScanDraft] = []
        var loadSource = "none"
        var mainFileWasCorrupt = false

        let fileName = currentScopedFileName()
        let mainFileExisted = AppPersistenceSupport.fileExists(named: fileName)

        if let data = AppPersistenceSupport.readData(
            named: fileName,
            legacyDefaults: userDefaults,
            legacyKey: legacyKey
        ) {
            if let decoded = try? JSONDecoder().decode([ScanDraft].self, from: data) {
                loaded = decoded
                loadSource = decoded.isEmpty ? "file-empty" : "file"
            } else {
                mainFileWasCorrupt = true
                loadSource = "file-corrupt"
                #if DEBUG
                appDebugLog("🚨 [ScanDraftStore.load] CORRUPTION: main file present (\(data.count) bytes) but decode failed!")
                #endif
            }
        }

        // Recovery 1: Last-Known-Good (höchste Priorität).
        if loaded.isEmpty {
            let lkgFileName = currentLastKnownGoodFileName()
            if let lkgData = AppPersistenceSupport.readDataIfFileExists(named: lkgFileName),
               let decoded = try? JSONDecoder().decode([ScanDraft].self, from: lkgData),
               !decoded.isEmpty {
                loaded = decoded
                loadSource = "last-known-good"
                #if DEBUG
                appDebugLog("✅ [ScanDraftStore.load] recovered \(decoded.count) drafts from Last-Known-Good backup")
                #endif
            }
        }

        // Recovery 2: UserDefaults-Backup.
        if loaded.isEmpty {
            if let backup = userDefaults.data(forKey: legacyKey),
               let decoded = try? JSONDecoder().decode([ScanDraft].self, from: backup),
               !decoded.isEmpty {
                loaded = decoded
                loadSource = "userDefaults-recovery"
                #if DEBUG
                appDebugLog("⚠️ [ScanDraftStore.load] file empty/missing/corrupt — recovered \(decoded.count) drafts from UserDefaults backup")
                #endif
            }
        }

        #if DEBUG
        if loaded.isEmpty {
            appDebugLog("ℹ️ [ScanDraftStore.load] no drafts (source=\(loadSource), mainFileExisted=\(mainFileExisted), corrupt=\(mainFileWasCorrupt))")
        } else {
            appDebugLog("📦 [ScanDraftStore.load] \(loaded.count) drafts loaded from \(loadSource)")
        }
        #endif

        return loaded
    }

    // MARK: - Persist

    func persistDrafts(_ drafts: [ScanDraft], key: String) {
        // Pre-Save-Sanity: laute Warnung bei verdächtigem Schwund, aber
        // kein Block (echte „alles löschen"-Aktionen sind valide). LKG
        // bleibt bei Leer-Save erhalten.
        let cachedCount = cachedDraftsCount()
        let newCount = drafts.count
        #if DEBUG
        if cachedCount > 0 && newCount == 0 {
            appDebugLog("⚠️ [ScanDraftStore.save] DANGER: drafts wechselt von \(cachedCount) → 0. Last-Known-Good bleibt erhalten.")
        } else if cachedCount > 10 && newCount < cachedCount / 2 {
            appDebugLog("⚠️ [ScanDraftStore.save] DANGER: Draft-Zahl halbiert sich (\(cachedCount) → \(newCount)). Last-Known-Good bleibt erhalten.")
        }
        #endif

        guard let data = try? JSONEncoder().encode(drafts) else {
            #if DEBUG
            appDebugLog("❌ [ScanDraftStore.save] JSON encoding failed — data NOT saved!")
            #endif
            return
        }

        AppPersistenceSupport.writeData(data, named: currentScopedFileName())
        // Redundanter Backup-Pfad.
        userDefaults.set(data, forKey: key)

        // LKG nur bei non-empty aktualisieren.
        if newCount > 0 {
            AppPersistenceSupport.writeData(data, named: currentLastKnownGoodFileName())
        }

        #if DEBUG
        appDebugLog("💾 [ScanDraftStore] \(newCount) drafts persisted " +
              "(file + UserDefaults + \(newCount > 0 ? "LKG-backup" : "LKG-skipped"), \(data.count) bytes)")
        #endif

        cache(drafts)
    }

    // MARK: - Cache

    private func cache(_ drafts: [ScanDraft]) {
        cacheLock.lock()
        cachedDrafts = drafts
        cacheLock.unlock()
    }

    private func cachedDraftsCount() -> Int {
        cacheLock.lock()
        let count = cachedDrafts?.count ?? -1
        cacheLock.unlock()
        return count
    }
}
