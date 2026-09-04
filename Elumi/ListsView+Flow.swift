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

        // **Editor-über-Detail (2026-05-22)** — der Editor liegt jetzt als
        // Sheet ÜBER dem Detail (in ListDetailSheet). Der Save-Button ruft
        // `dismiss()` → Editor schließt → das Detail (gemountet darunter)
        // erscheint wieder, Scroll erhalten. Kein manuelles
        // `showingEntryEditor = false`, kein Restore mehr nötig.
        cancelEditing()
    }

    func beginEditing(_ item: VocabularyItem) {
        editingItemID = item.id
        frenchText = item.french
        germanText = item.german
        cardType = item.cardType
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
            showToast("Bitte gib zuerst einen Lernlistennamen ein.", isSuccess: false)
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

    /// **2026-08-05** — Warnt, wenn die hier manuell gewählte Liste von der
    /// Zielliste abweicht. Das Ziel selbst bleibt unangetastet — nur ein
    /// Hinweis, keine Sperre.
    ///
    /// **2026-08-05, Korrektur** — ruft jetzt denselben globalen Hinweis
    /// wie die Übungs-Setup-Picker (`GlobalListPickerSheet`) statt des
    /// lokalen `showToast(...)`. Der lokale Toast war eine kleine Pille
    /// unten am Bildschirmrand — User-Report: „erscheint viel zu klein
    /// und unten, den sieht man kaum." Der globale Hinweis in
    /// `RootContentView` ist bewusst groß und mittig, damit er nicht zu
    /// übersehen ist, egal von welcher Auswahl-Stelle er kommt.
    func warnIfDivergesFromGoalList(_ pickedID: UUID) {
        LearningGoalStore.shared.noteManualListSelection([pickedID])
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
