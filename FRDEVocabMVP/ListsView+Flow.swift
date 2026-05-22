import SwiftUI

extension ListsView {
    func saveEntry() {
        if let editingItemID {
            listStore.updateItem(
                itemID: editingItemID,
                in: selectedList.id,
                french: frenchText,
                german: germanText,
                type: cardType
            )
        } else {
            listStore.addItem(
                french: frenchText,
                german: germanText,
                type: cardType,
                to: selectedList.id,
                sourceLanguage: selectedList.items.first?.sourceLanguage ?? .french
            )
        }

        // **Nav-Bug-Fix (2026-05-22)** — kein manuelles `showingEntryEditor =
        // false` / `restoreListDetailIfNeeded()` mehr: der Editor-Save-Button
        // ruft `dismiss()` → Sheet schließt → `onDismiss` restored die Detail-
        // Sheet (deterministisch, kein Delay-Race).
        cancelEditing()
    }

    func beginEditing(_ item: VocabularyItem) {
        editingItemID = item.id
        frenchText = item.french
        germanText = item.german
        cardType = item.cardType
        showingEntryEditor = true
    }

    func startNewEntry() {
        cancelEditing()
        showingEntryEditor = true
    }

    func cancelEditing() {
        editingItemID = nil
        frenchText = ""
        germanText = ""
        cardType = .words
    }

    func createNewList() {
        let trimmedName = newListName.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedName.isEmpty else {
            showToast("Bitte gib zuerst einen Listennamen ein.", isSuccess: false)
            return
        }

        listStore.createList(named: trimmedName, collectionPreset: newListCollectionPreset)
        feedbackPlayer.playListAction()
        let createdName = listStore.selectedList.name
        newListName = ""
        newListCollectionPreset = .schoolbook
        showingCreateListForm = false
        editableListName = createdName
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        showToast("„\(createdName)“ wurde angelegt.")
    }

    func restoreListDetailIfNeeded() {
        guard shouldRestoreListDetailAfterEditing else { return }
        shouldRestoreListDetailAfterEditing = false
        // **Nav-Bug-Fix (2026-05-22)** — wird jetzt aus dem `onDismiss` der
        // Editor-Sheet aufgerufen, d. h. der Editor ist bereits vollständig
        // geschlossen → kein 0.18s-Race mehr. Ein Next-Runloop-Hop (kein fixer
        // Delay) stellt sicher, dass die Dismiss-Transaktion settled ist, bevor
        // die Detail-Sheet neu präsentiert wird.
        DispatchQueue.main.async {
            showingListDetail = true
        }
    }

    func showToast(_ message: String, isSuccess: Bool = true) {
        toastDismissWorkItem?.cancel()
        toastMessage = message
        toastIsSuccess = isSuccess

        withAnimation(.easeInOut(duration: 0.22)) {
            isShowingToast = true
        }

        let workItem = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.22)) {
                isShowingToast = false
            }
        }
        toastDismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8, execute: workItem)
    }
}
