import SwiftUI

extension ListsView {
    func applyListsPresentations<Content: View>(to content: Content) -> some View {
        content
            .sheet(isPresented: $showingEntryEditor) {
                VocabularyEntryEditorSheet(
                    style: sectionStyle,
                    title: editingItemID == nil ? "Neue Vokabeln eingeben" : "Vokabel bearbeiten",
                    sourceFieldLabel: sourceFieldLabel,
                    frenchText: $frenchText,
                    germanText: $germanText,
                    cardType: $cardType,
                    onCancel: {
                        cancelEditing()
                        showingEntryEditor = false
                        restoreListDetailIfNeeded()
                    },
                    onSave: {
                        saveEntry()
                    }
                )
            }
            .sheet(isPresented: $showingListPicker) {
                ListPickerSheet(
                    style: sectionStyle,
                    lists: listStore.allLists,
                    selectedListID: listStore.selectedListID
                ) { pickedID in
                    listStore.selectedListID = pickedID
                    showingListPicker = false
                } onDelete: { deletedList in
                    listStore.deleteCustomList(id: deletedList.id)
                    editableListName = listStore.selectedList.name
                    cancelEditing()
                    showToast("„\(deletedList.name)“ wurde gelöscht.")
                }
            }
            .sheet(isPresented: $showingListDetail) {
                ListDetailSheet(
                    style: sectionStyle,
                    list: selectedList,
                    onClose: {
                        showingListDetail = false
                    },
                    onEdit: { item in
                        shouldRestoreListDetailAfterEditing = true
                        beginEditing(item)
                        showingListDetail = false
                    },
                    onDelete: { item in
                        listStore.removeItem(itemID: item.id, from: selectedList.id)
                        if editingItemID == item.id {
                            cancelEditing()
                        }
                    }
                )
            }
            .sheet(isPresented: $showingRenameDialog) {
                RenameListSheet(
                    style: sectionStyle,
                    listName: $editableListName,
                    onCancel: {
                        editableListName = selectedList.name
                        showingRenameDialog = false
                    },
                    onSave: {
                        listStore.renameList(id: selectedList.id, to: editableListName)
                        editableListName = listStore.selectedList.name
                        showingRenameDialog = false
                        showToast("Liste umbenannt.")
                    }
                )
            }
            .alert("Wirklich löschen?", isPresented: Binding(
                get: { listPendingDeletion != nil },
                set: { if !$0 { listPendingDeletion = nil } }
            )) {
                Button("Nein", role: .cancel) {
                    listPendingDeletion = nil
                }
                Button("Ja", role: .destructive) {
                    if let listPendingDeletion {
                        let deletedName = listPendingDeletion.name
                        if listPendingDeletion.id == listStore.selectedListID {
                            listStore.deleteSelectedCustomList()
                        } else {
                            listStore.deleteCustomList(id: listPendingDeletion.id)
                        }
                        cancelEditing()
                        self.listPendingDeletion = nil
                        showToast("„\(deletedName)“ wurde gelöscht.")
                    }
                }
            } message: {
                Text(listPendingDeletion.map { "„\($0.name)“ wird gelöscht." } ?? "")
            }
    }
}
