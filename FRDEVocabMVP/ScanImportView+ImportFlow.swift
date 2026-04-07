import SwiftUI

extension ScanImportView {
    func importScannedText() {
        commitPreviewEditsAndSyncImportText()
        let activeListStore = listStore ?? ensureListStoreReady()
        let items = previewPairs
            .filter(\.isImportable)
            .compactMap { pair in
                scanVocabularyItemFactory.makeVocabularyItem(
                    french: pair.french,
                    german: pair.german,
                    cardType: pair.cardType,
                    sourceLanguage: scanSourceLanguage
                )
            }
        let importedItemIDs = items.map(\.id)
        let trimmedListName = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetListID = activeListStore.ensureCustomList(
            named: trimmedListName.isEmpty ? activeListStore.suggestedListName(from: "Scan") : trimmedListName,
            collectionPreset: selectedCollectionPreset
        )
        let importedCount = activeListStore.importItems(
            items,
            preferredListID: targetListID,
            suggestedListName: trimmedListName.isEmpty ? "Scan" : trimmedListName,
            collectionPreset: selectedCollectionPreset
        )

        if importedCount == 0 {
            importMessage = "Keine Paare erkannt. Nutze pro Zeile ein Trennzeichen wie `=` oder `→`."
            return
        }

        let targetListName = activeListStore.selectedList.name
        importMessage = "\(importedCount) Einträge in „\(targetListName)“ importiert."
        importCompletionContext = ImportCompletionContext(
            importedCount: importedCount,
            targetListID: targetListID,
            targetListName: targetListName,
            language: scanSourceLanguage,
            preferredDirection: scanSourceLanguage.defaultDirectionToGerman,
            cardType: dominantImportedCardType(in: items),
            importedItemIDs: importedItemIDs
        )
        resetScanInputAfterSuccessfulImport(keepingListName: false)
        isShowingImportCompletion = true
    }

    func dominantImportedCardType(in items: [VocabularyItem]) -> CardType {
        let phraseCount = items.filter { $0.cardType == .phrases }.count
        let wordCount = items.count - phraseCount
        return phraseCount > wordCount ? .phrases : .words
    }

    func updateScanEvalReport(for result: ScanProviderResult) {
        session.updateEvalReport(for: result)
    }

    func resetScanInputAfterSuccessfulImport(keepingListName: Bool) {
        session.resetInputAfterSuccessfulImport(
            keepingListName: keepingListName,
            fallbackListName: listStore?.suggestedListName(from: "Scan") ?? "Scan"
        )
    }

    func handleCompletionSelection(_ destination: AppScreen?) {
        pendingCompletionDestination = destination
        isShowingImportCompletion = false
    }
}
