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
                        // **Punkt 2 Fix (2026-05-04)** — Listen-Tab ist
                        // jetzt die kanonische „global selection"-UI.
                        // Eine hier gewählte Liste wirkt systemweit auf
                        // alle Module (Quiz, Training, Karteikarten,
                        // Akzente, Word Runner). Vorher schrieb der
                        // Listen-Tab nur den lokalen Editor-State —
                        // Quiz las davon nicht. Jetzt: zusätzlich in
                        // den globalen Slot.
                        VocabularyListSelectionResolver.setGlobalSelectedListIDs([pickedID])
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
                        VocabularyListSelectionResolver.setGlobalSelectedListIDs([list.id])
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
                    },
                    onMerge: { source, target in
                        listStore.mergeLists(sourceID: source.id, into: target.id)
                        feedbackPlayer.playListAction()
                        showToast("\(source.name) in \(target.name) zusammengef\u{00FC}hrt.")
                    },
                    lernjahrMax: lernjahrMax,
                    onLernjahrMaxChange: { newMax in
                        lernjahrMax = newMax
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
                        // Siehe Doc oben (zwei `.sheet`-Trigger, gleiche
                        // Semantik — Listen-Tab schreibt globalen Slot).
                        VocabularyListSelectionResolver.setGlobalSelectedListIDs([pickedID])
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
                        VocabularyListSelectionResolver.setGlobalSelectedListIDs([list.id])
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
                    },
                    onMerge: { source, target in
                        listStore.mergeLists(sourceID: source.id, into: target.id)
                        feedbackPlayer.playListAction()
                        showToast("\(source.name) in \(target.name) zusammengef\u{00FC}hrt.")
                    },
                    feedbackPlayer: feedbackPlayer,
                    onHome: { goHome() },
                    onSettings: { openSettings() },
                    lernjahrMax: lernjahrMax,
                    onLernjahrMaxChange: { newMax in
                        lernjahrMax = newMax
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
                    },
                    onRename: {
                        // Detail-Sheet schließen, Rename-Dialog öffnen.
                        // Zwei Sheets parallel (RenameSheet over
                        // ListDetailSheet) verursacht in iOS teils
                        // Remount-Flickern; der kleine Delay stellt
                        // sauberes Sequencing sicher.
                        editableListName = selectedList.name
                        showingListDetail = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingRenameDialog = true
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
                        // **Bug-Fix 2026-04-23**: Nach dem Schließen des
                        // Rename-Sheets MUSS das Detail-Sheet wieder
                        // aufgehen — sonst landet der User (besonders
                        // im Direct-Launch-Pfad aus Import-Completion)
                        // auf einem schwarzen Screen, weil
                        // `screenContent` bei `isDirectListLaunch`
                        // bewusst keinen `listsPrimaryContent` rendert.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingListDetail = true
                        }
                    },
                    onSave: {
                        listStore.renameList(id: selectedList.id, to: editableListName)
                        editableListName = listStore.selectedList.name
                        showingRenameDialog = false
                        showToast("Liste umbenannt.")
                        // **Bug-Fix 2026-04-23**: dito — Rename-Save
                        // schloss vorher das Rename-Sheet, ließ aber
                        // `showingListDetail = false` → schwarzer
                        // Screen. Re-trigger sequenziell mit kleinem
                        // Delay, damit zwei iOS-Sheets nicht im
                        // selben Frame Remount-Flackern auslösen.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showingListDetail = true
                        }
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
