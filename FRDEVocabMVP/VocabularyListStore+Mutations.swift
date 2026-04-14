import Foundation

extension VocabularyListStore {
    @discardableResult
    func ensureCustomList(
        named proposedName: String,
        collectionPreset: ListCollectionPreset = .other
    ) -> UUID {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "Liste" : trimmed

        if let existingIndex = customLists.firstIndex(where: {
            $0.name.localizedCaseInsensitiveCompare(baseName) == .orderedSame
        }) {
            customLists[existingIndex].collectionPreset = collectionPreset
            selectedListID = customLists[existingIndex].id
            return customLists[existingIndex].id
        }

        return createList(named: baseName, collectionPreset: collectionPreset)
    }

    @discardableResult
    func createList(
        named proposedName: String = "",
        collectionPreset: ListCollectionPreset = .other
    ) -> UUID {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName = trimmed.isEmpty ? "Liste" : trimmed
        let uniqueName = uniqueListName(from: baseName)
        let list = VocabularyList(name: uniqueName, items: [], collectionPreset: collectionPreset)
        customLists.append(list)
        selectedListID = list.id
        return list.id
    }

    func deleteSelectedCustomList() {
        guard let index = customLists.firstIndex(where: { $0.id == selectedListID }) else { return }
        customLists.remove(at: index)
        selectedListID = Self.builtInListID
    }

    func deleteCustomList(id: UUID) {
        guard let index = customLists.firstIndex(where: { $0.id == id }) else { return }
        customLists.remove(at: index)
        if selectedListID == id {
            selectedListID = Self.builtInListID
        }
    }

    func renameList(id: UUID, to proposedName: String) {
        let trimmed = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let index = customLists.firstIndex(where: { $0.id == id }) else { return }

        let currentName = customLists[index].name
        if currentName.localizedCaseInsensitiveCompare(trimmed) == .orderedSame {
            customLists[index].name = trimmed
            return
        }

        let takenNames = allLists
            .filter { $0.id != id }
            .map(\.name)

        let uniqueName: String
        if !takenNames.contains(where: { $0.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }) {
            uniqueName = trimmed
        } else {
            var candidateIndex = 2
            var candidate = "\(trimmed) \(candidateIndex)"
            while takenNames.contains(where: { $0.localizedCaseInsensitiveCompare(candidate) == .orderedSame }) {
                candidateIndex += 1
                candidate = "\(trimmed) \(candidateIndex)"
            }
            uniqueName = candidate
        }

        customLists[index].name = uniqueName
        selectedListID = customLists[index].id
    }

    func updateCollectionPreset(id: UUID, to collectionPreset: ListCollectionPreset) {
        guard let index = customLists.firstIndex(where: { $0.id == id }) else { return }
        customLists[index].collectionPreset = collectionPreset
    }

    func addItem(
        french: String,
        german: String,
        type: CardType,
        to listID: UUID? = nil,
        sourceLanguage: StudyLanguage = .french
    ) {
        let frenchValue = french.trimmingCharacters(in: .whitespacesAndNewlines)
        let germanValue = german.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !frenchValue.isEmpty, !germanValue.isEmpty else { return }

        let targetID = listID ?? selectedListID
        guard let index = customLists.firstIndex(where: { $0.id == targetID }) else { return }

        customLists[index].items.append(
            VocabularyItem(
                french: frenchValue,
                german: germanValue,
                cardType: type,
                sourceLanguage: sourceLanguage
            )
        )
    }

    /// Merge source list into target list, then delete source
    func mergeLists(sourceID: UUID, into targetID: UUID) {
        guard sourceID != targetID,
              let sourceIndex = customLists.firstIndex(where: { $0.id == sourceID }),
              let targetIndex = customLists.firstIndex(where: { $0.id == targetID }) else { return }
        customLists[targetIndex].items.append(contentsOf: customLists[sourceIndex].items)
        customLists.remove(at: sourceIndex)
        if selectedListID == sourceID {
            selectedListID = targetID
        }
    }

    func removeItem(itemID: UUID, from listID: UUID) {
        guard let listIndex = customLists.firstIndex(where: { $0.id == listID }) else { return }
        customLists[listIndex].items.removeAll { $0.id == itemID }
    }

    func updateItem(
        itemID: UUID,
        in listID: UUID,
        french: String,
        german: String,
        type: CardType
    ) {
        let frenchValue = french.trimmingCharacters(in: .whitespacesAndNewlines)
        let germanValue = german.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !frenchValue.isEmpty, !germanValue.isEmpty else { return }
        guard let listIndex = customLists.firstIndex(where: { $0.id == listID }) else { return }
        guard let itemIndex = customLists[listIndex].items.firstIndex(where: { $0.id == itemID }) else { return }

        customLists[listIndex].items[itemIndex].french = frenchValue
        customLists[listIndex].items[itemIndex].german = germanDisplayText(
            germanValue,
            cardType: type,
            sourceHint: frenchValue
        )
        customLists[listIndex].items[itemIndex].cardType = type
    }

    @discardableResult
    func importItems(
        _ items: [VocabularyItem],
        preferredListID: UUID?,
        suggestedListName: String,
        collectionPreset: ListCollectionPreset = .other
    ) -> Int {
        guard !items.isEmpty else { return 0 }

        let targetID: UUID
        if let preferredListID, customLists.contains(where: { $0.id == preferredListID }) {
            targetID = preferredListID
        } else if let selectedCustomList {
            targetID = selectedCustomList.id
        } else {
            targetID = createList(named: suggestedListName, collectionPreset: collectionPreset)
        }

        guard let index = customLists.firstIndex(where: { $0.id == targetID }) else { return 0 }
        customLists[index].collectionPreset = collectionPreset
        customLists[index].items.append(contentsOf: items)
        selectedListID = targetID
        return items.count
    }
}
