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
                    selectedListID: listStore.selectedListID,
                    onSelect: { pickedID in
                        listStore.selectedListID = pickedID
                        showingListPicker = false
                    },
                    onDelete: { deletedList in
                        listStore.deleteCustomList(id: deletedList.id)
                        feedbackPlayer.playListAction()
                        editableListName = listStore.selectedList.name
                        cancelEditing()
                        showToast("\(deletedList.name) wurde gel\u{f6}scht.")
                    },
                    onView: { list in
                        listStore.selectedListID = list.id
                        showingListPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingListDetail = true
                        }
                    },
                    onRename: { list in
                        listStore.selectedListID = list.id
                        editableListName = list.name
                        showingListPicker = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingRenameDialog = true
                        }
                    }
                )
            }
            .sheet(item: $listPickerFilter) { filter in
                ListPickerSheet(
                    style: sectionStyle,
                    lists: filteredListsForPicker(filter),
                    selectedListID: listStore.selectedListID,
                    onSelect: { pickedID in
                        listStore.selectedListID = pickedID
                        listPickerFilter = nil
                    },
                    onDelete: { deletedList in
                        listStore.deleteCustomList(id: deletedList.id)
                        feedbackPlayer.playListAction()
                        editableListName = listStore.selectedList.name
                        cancelEditing()
                        showToast("\(deletedList.name) wurde gel\u{f6}scht.")
                    },
                    onView: { list in
                        listStore.selectedListID = list.id
                        listPickerFilter = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingListDetail = true
                        }
                    },
                    onRename: { list in
                        listStore.selectedListID = list.id
                        editableListName = list.name
                        listPickerFilter = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingRenameDialog = true
                        }
                    }
                )
            }
            .sheet(isPresented: $showingListDetail) {
                ListDetailSheet(
                    style: sectionStyle,
                    list: selectedList,
                    onClose: {
                        showingListDetail = false
                        // From Import Completion → dismiss entire ListsView to return to Import screen
                        if launchContext?.preferredListID != nil {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                dismiss()
                            }
                        }
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
                .interactiveDismissDisabled()
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
                        feedbackPlayer.playListAction()
                        cancelEditing()
                        self.listPendingDeletion = nil
                        showToast("\(deletedName) wurde gel\u{00F6}scht.")
                    }
                }
            } message: {
                Text(listPendingDeletion.map { "\($0.name) wird gel\u{00F6}scht." } ?? "")
            }
    }
}
