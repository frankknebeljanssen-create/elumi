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

    // MARK: - Merge-Pipeline („Zu bestehender Liste hinzufügen")

    /// Wendet einen `MergePlan` auf eine bestehende Custom-Liste an
    /// und persistiert das Ergebnis (über das `customLists`-didSet).
    ///
    /// Die Plan-Berechnung passiert **vorher** in der UI via
    /// `VocabularyListMergePlanner.computePlan(...)`. Hier wird nur
    /// noch geschrieben — entweder direkt (keine Konflikte) oder
    /// nachdem der User pro Konflikt entschieden hat.
    ///
    /// Doppelte Einträge werden durch die Plan-Logik ausgeschlossen,
    /// die Liste kann also keine fachlichen Duplikate erzeugen.
    @discardableResult
    func applyMergePlan(
        _ plan: MergePlan,
        toListWithID listID: UUID
    ) -> MergeResult {
        // **Bug-Fix 2026-04-23 abends (Critical Import-Bug)**: Vorher
        // konnte ein nicht-gefundenes `listID` ein „erfolgreiches"
        // Result mit `added: 0` zurückgeben (silent failure), und der
        // Save war über das `customLists`-didSet erst nach 0,3s
        // geplant — die Success-Meldung erschien VOR der Persistenz.
        // Bei großen Importen (270 Items) konnte das zu sichtbarem
        // Inkonsistenzen führen.
        //
        // Jetzt:
        //   1. Pre-Check: Ziel-Liste vorhanden? → sonst `.targetListMissing`
        //   2. Snapshot der `beforeCount` für Validierung
        //   3. Apply mutiert die Items
        //   4. **Synchroner Save** — kein 0,3s-Delay
        //   5. Post-Check: `actualAfterCount == beforeCount + added`?
        //      → bei Mismatch `.persistenceMismatch`
        //   6. `selectedListID` erst nach erfolgreichem Apply setzen
        guard let index = customLists.firstIndex(where: { $0.id == listID }) else {
            #if DEBUG
            appDebugLog("📋 [applyMergePlan] FEHLER: Ziel-Liste nicht gefunden (id=\(listID))")
            #endif
            return MergeResult.failure(.targetListMissing)
        }

        let beforeCount = customLists[index].items.count
        let expectedAdded = plan.safeAdds.count
            + plan.conflicts.filter { $0.resolution == .replaceWithIncoming }.count
        // Bei Replace bleibt die Item-Count konstant (overwrite).
        let expectedNetGrowth = plan.safeAdds.count
        let expectedAfterCount = beforeCount + expectedNetGrowth

        #if DEBUG
        appDebugLog("""
        📋 [applyMergePlan] START
           targetListID=\(listID)
           targetListName=\(customLists[index].name)
           beforeCount=\(beforeCount)
           plan.safeAdds=\(plan.safeAdds.count)
           plan.exactDuplicatesToSkip=\(plan.exactDuplicatesToSkip.count)
           plan.conflicts=\(plan.conflicts.count) (replaces=\(plan.conflicts.filter { $0.resolution == .replaceWithIncoming }.count))
           expectedAdded=\(expectedAdded)  expectedNetGrowth=\(expectedNetGrowth)  expectedAfterCount=\(expectedAfterCount)
        """)
        #endif

        let (newItems, applyResult) = VocabularyListMergePlanner.apply(
            plan: plan,
            to: customLists[index].items
        )
        customLists[index].items = newItems

        // **Synchroner Save** — wir warten nicht auf den 0,3s-debounce
        // im didSet. Der User soll erst eine Success-Meldung sehen,
        // wenn die Daten tatsächlich auf Platte sind.
        saveCustomLists()

        // **Post-Apply-Validierung** (User-Spec): „Eine Meldung darf
        // nur gezeigt werden, wenn die Mutation wirklich angewendet
        // wurde und die Persistenz erfolgreich war." Wir prüfen das,
        // indem wir den aktuellen Item-Count gegen die Erwartung
        // vergleichen.
        guard let postIndex = customLists.firstIndex(where: { $0.id == listID }) else {
            #if DEBUG
            appDebugLog("📋 [applyMergePlan] POST-CHECK FEHLER: Liste nach Apply weg")
            #endif
            return MergeResult.failure(.targetListMissing)
        }
        let actualAfterCount = customLists[postIndex].items.count
        #if DEBUG
        appDebugLog("📋 [applyMergePlan] AFTER actualAfterCount=\(actualAfterCount), expected=\(expectedAfterCount)")
        #endif
        if actualAfterCount != expectedAfterCount {
            #if DEBUG
            appDebugLog("📋 [applyMergePlan] MISMATCH! actual=\(actualAfterCount) ≠ expected=\(expectedAfterCount)")
            #endif
            return MergeResult.failure(.persistenceMismatch(expected: expectedAfterCount, actual: actualAfterCount))
        }

        // Erst nach validem Apply die aktive Liste switchen.
        selectedListID = listID
        #if DEBUG
        appDebugLog("📋 [applyMergePlan] OK — added=\(applyResult.added), skipped=\(applyResult.skipped), replaced=\(applyResult.replaced)")
        #endif
        return applyResult
    }
}
