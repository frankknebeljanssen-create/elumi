import Foundation

extension VocabularyListStore {
    func loadState() {
        repository.setCurrentAccount(AccountStore.shared.currentAccountID)
        let snapshot = repository.loadSnapshot(
            customListsKey: customListsKey,
            selectedListKey: selectedListKey,
            sampleListsSeededKey: sampleListsSeededKey,
            builtInListID: Self.builtInListID,
            sampleSeeds: sampleVocabularyListSeeds
        )
        apply(snapshot: snapshot)
    }

    /// **Phase E.2** — wird vom `AccountStore` nach jedem Account-
    /// Wechsel gerufen. Invalidiert den Repository-Snapshot-Cache und
    /// lädt das Custom-Listen-Paket des neu aktiven Accounts. Ohne
    /// diese Methode würden Views nach dem Switch weiter die Listen
    /// des vorigen Accounts zeigen.
    func reloadForCurrentAccount() {
        repository.invalidateCache()
        loadState()
    }

    /// Entfernt alle vom Nutzer angelegten Listen und laedt danach den
    /// Ausgangszustand — inklusive der Startlisten, weil das
    /// Sample-Seeding-Flag mitfaellt.
    ///
    /// **Codeaudit 2026-09-03, Stufe 3 (Punkt 19)** — bis hierher gab
    /// es diese API nicht, und der `GameStateResetService` griff
    /// deshalb an der Persistenz-Schicht vorbei direkt auf einen
    /// hartkodierten Dateinamen zu. Jetzt besitzt der Store seinen
    /// eigenen Reset: er raeumt alle Ebenen auf und aktualisiert sich
    /// selbst, sodass der Effekt sofort sichtbar ist und nicht erst
    /// nach einem App-Neustart.
    func resetToDefaults() {
        cancelPendingSave()

        repository.setCurrentAccount(AccountStore.shared.currentAccountID)
        repository.resetPersistedCustomLists(
            customListsKey: customListsKey,
            selectedListKey: selectedListKey,
            sampleListsSeededKey: sampleListsSeededKey
        )

        // Der Load legt die Startlisten neu an (Flag ist gefallen) und
        // schreibt sie ueber `shouldPersistMigratedLists` zurueck auf
        // Platte — der Ausgangszustand ist damit auch persistiert.
        loadState()
    }

    func apply(snapshot: VocabularyListStoreSnapshot) {
        isApplyingStoredState = true
        customLists = snapshot.customLists
        selectedListID = snapshot.selectedListID
        isApplyingStoredState = false
    }

    func saveCustomLists() {
        repository.setCurrentAccount(AccountStore.shared.currentAccountID)
        repository.persistCustomLists(
            customLists,
            key: customListsKey,
            snapshot: VocabularyListStoreSnapshot(
                customLists: customLists,
                selectedListID: selectedListID
            )
        )
    }

    func saveSelectedListID() {
        repository.setCurrentAccount(AccountStore.shared.currentAccountID)
        repository.persistSelectedListID(
            selectedListID,
            key: selectedListKey,
            snapshot: VocabularyListStoreSnapshot(
                customLists: customLists,
                selectedListID: selectedListID
            )
        )
    }

    func rebuildDerivedLists() {
        let sortedCustomLists = customLists.sorted { lhs, rhs in
            if lhs.collectionPreset.group.sortOrder != rhs.collectionPreset.group.sortOrder {
                return lhs.collectionPreset.group.sortOrder < rhs.collectionPreset.group.sortOrder
            }

            if lhs.collectionPreset.sortOrder != rhs.collectionPreset.sortOrder {
                return lhs.collectionPreset.sortOrder < rhs.collectionPreset.sortOrder
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }

        sortedCustomListsStorage = sortedCustomLists

        let allCustomItems = sortedCustomLists.flatMap(\.items)
        if allCustomItems.isEmpty {
            allCustomVocabularyListStorage = nil
            practiceListsStorage = sortedCustomLists
            return
        }

        let aggregateList = VocabularyList(
            id: Self.allCustomVocabularyListID,
            name: "Gesamter eigener Wortschatz",
            items: allCustomItems,
            isBuiltIn: false,
            collectionPreset: .other,
            isAggregateVocabulary: true
        )
        allCustomVocabularyListStorage = aggregateList
        practiceListsStorage = [aggregateList] + sortedCustomLists
    }

    func uniqueListName(from baseName: String) -> String {
        if !allLists.map(\.name).contains(where: { $0.localizedCaseInsensitiveCompare(baseName) == .orderedSame }) {
            return baseName
        }

        for index in 2...999 {
            let candidate = "\(baseName) \(index)"
            if !allLists.map(\.name).contains(where: { $0.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
                return candidate
            }
        }

        return "\(baseName) \(UUID().uuidString.prefix(4))"
    }
}
