import Foundation

extension VocabularyListStore {
    func loadState() {
        let snapshot = repository.loadSnapshot(
            customListsKey: customListsKey,
            selectedListKey: selectedListKey,
            sampleListsSeededKey: sampleListsSeededKey,
            builtInListID: Self.builtInListID,
            sampleSeeds: sampleVocabularyListSeeds
        )
        apply(snapshot: snapshot)
    }

    func apply(snapshot: VocabularyListStoreSnapshot) {
        isApplyingStoredState = true
        customLists = snapshot.customLists
        selectedListID = snapshot.selectedListID
        isApplyingStoredState = false
    }

    func saveCustomLists() {
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
