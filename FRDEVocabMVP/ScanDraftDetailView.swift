// ScanDraftDetailView.swift
// **Meine Scans — Phase D (2026-05-20)** — Detail-Screen für einen
// gespeicherten Scan-Entwurf. Top-level `AppScreen.scanDraftDetail(UUID)`-
// Destination (erbt den Footer-Inset aus RootContentView:187).
//
// Funktionen:
//   • Bild-Strip (horizontal) + KISS-Vollbild-Viewer (kein Zoom)
//   • Vokabel-Liste mit `isImportable`-Toggle pro Paar (lokale Kopie →
//     `ScanDraftStore.update` → debounced Save)
//   • „Zu Liste machen" → NUR „Neue Liste" (Phase D); „Bestehende Liste"
//     kommt in D v2 (braucht Merge-Planner + Conflict-Review)
//   • Toolbar-Menu (…): Umbenennen (RenameListSheet) + Löschen
//   • Nach Import: Alert „Entwurf jetzt löschen?"
//
// Back-Navigation via `@Environment(\.dismiss)` (NICHT `navigate`, das
// würde pushen statt poppen).

import SwiftUI

struct ScanDraftDetailView: View {
    let draftID: UUID
    let listStore: VocabularyListStore?
    // **Phase D v3 (2026-05-20)** — vom AppDestinationHost injiziert für die
    // ImportCompletionView-CTAs. `navigate` pusht Modul/Liste auf den Stack;
    // `goHome` wird im Single-Draft-„Später" NICHT genutzt (Detail bleibt offen),
    // aber konsistent mitgereicht.
    let navigate: (AppScreen) -> Void
    let goHome: () -> Void

    @ObservedObject private var draftStore = ScanDraftStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var localDraft: ScanDraft?
    @State private var isShowingNewListNameSheet = false
    @State private var isShowingRenameSheet = false
    @State private var renameText = ""
    @State private var isShowingDeleteConfirm = false
    @State private var fullscreenImage: IdentifiableImage?

    // **Phase D v2 (2026-05-20)** — „Zu bestehender Liste"-Merge-Pfad.
    @State private var isShowingTargetChoice = false
    @State private var isShowingExistingListPicker = false
    @State private var isShowingConflictReview = false
    @State private var pendingMergePlan: MergePlan?
    @State private var pendingTargetListID: UUID?
    @State private var pendingTargetListName = ""
    @State private var isShowingImportFailureAlert = false
    @State private var importFailureMessage = ""

    // **Phase D v3 (2026-05-20)** — Success-Pfad zeigt jetzt die ImportCompletion
    // View (CTAs) statt eines Toasts (Content-Swap im Body). `pendingImportCard
    // Type` merkt sich den Dominant-Typ aus dem Merge-Pfad (in `applyMerge` sind
    // die Original-Items nicht mehr verfügbar).
    @State private var isShowingImportCompletion = false
    @State private var importCompletionContext: ImportCompletionContext?
    @State private var pendingImportCardType: CardType = .words

    var body: some View {
        Group {
            if isShowingImportCompletion, let ctx = importCompletionContext {
                // **Phase D v3** — Success-Pfad: Content-Swap zur CompletionView
                // (wie ScanImportView). Die Sheets unten sind dann inaktiv.
                importCompletionScreen(ctx)
            } else if let draft = localDraft {
                detailContent(draft: draft)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .appScreenBackground(.scan)
        .onAppear { loadDraft() }
        .sheet(isPresented: $isShowingNewListNameSheet) {
            NewListNameSheet(onCreate: { name in
                performImport(listName: name)
            })
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isShowingRenameSheet) {
            RenameListSheet(
                style: .scan,
                listName: $renameText,
                onCancel: {},
                onSave: { commitRename() }
            )
        }
        .sheet(item: $fullscreenImage) { wrapper in
            FullscreenImageView(image: wrapper.image)
        }
        .alert("Entwurf löschen?", isPresented: $isShowingDeleteConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { deleteDraft() }
        } message: {
            Text("\"\(localDraft?.title ?? "")\" wird unwiderruflich gelöscht.")
        }
        // **Phase D v2 (2026-05-20)** — Ziel-Wahl (Neue/Bestehende; kein
        // „Als Entwurf" → onSaveAsDraft ungesetzt → dritte Card unsichtbar).
        .sheet(isPresented: $isShowingTargetChoice) {
            ImportTargetChoiceSheet(
                onChooseNewList: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isShowingNewListNameSheet = true
                    }
                },
                onChooseExistingList: {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        isShowingExistingListPicker = true
                    }
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isShowingExistingListPicker) {
            if let listStore {
                ExistingListPickerSheet(
                    store: listStore,
                    importableCount: localDraft.map { activeCount($0) } ?? 0,
                    onConfirm: { listID in handleExistingListChosen(listID) },
                    onFallbackToNewList: {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            isShowingNewListNameSheet = true
                        }
                    }
                )
            }
        }
        .sheet(isPresented: $isShowingConflictReview) {
            if let plan = pendingMergePlan {
                ScanImportConflictReviewSheet(
                    workingConflicts: plan.conflicts,
                    safeAddCount: plan.safeAdds.count,
                    duplicateCount: plan.exactDuplicatesToSkip.count,
                    targetListName: pendingTargetListName,
                    onConfirm: { resolved in handleConflictReviewConfirmed(resolved) }
                )
            }
        }
        .alert("Hinzufügen fehlgeschlagen", isPresented: $isShowingImportFailureAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importFailureMessage)
        }
    }

    // MARK: - Phase D v3 — Import-Completion (CTAs statt Toast)

    /// Gespiegelt von `ScanImportView.importCompletionScreen` — identische 10
    /// CTAs, nur Routing über `handleSingleDraftCompletion` (eigenes „Später"-
    /// Verhalten: Completion aus, Detail bleibt offen).
    private func importCompletionScreen(_ context: ImportCompletionContext) -> some View {
        ImportCompletionView(
            context: context,
            onTrain: {
                handleSingleDraftCompletion(.train(TrainingLaunchContext(
                    preferredListID: context.targetListID,
                    preferredMode: .vocabulary,
                    shouldAutoStart: true
                )))
            },
            onNomen: {
                handleSingleDraftCompletion(.train(TrainingLaunchContext(
                    preferredListID: context.targetListID,
                    preferredMode: .nouns,
                    shouldAutoStart: true
                )))
            },
            onArticles: {
                handleSingleDraftCompletion(.train(TrainingLaunchContext(
                    preferredListID: context.targetListID,
                    preferredMode: .articles,
                    shouldAutoStart: true
                )))
            },
            onVerbs: {
                handleSingleDraftCompletion(.train(TrainingLaunchContext(
                    preferredListID: context.targetListID,
                    preferredMode: .verbs,
                    shouldAutoStart: true
                )))
            },
            onVerbforms: {
                handleSingleDraftCompletion(.train(TrainingLaunchContext(
                    preferredListID: context.targetListID,
                    preferredMode: .verbforms,
                    shouldAutoStart: false
                )))
            },
            onFlashcards: {
                handleSingleDraftCompletion(.flashcards(context.flashcardLaunchContext))
            },
            onQuiz: {
                handleSingleDraftCompletion(.quiz(context.quizLaunchContext))
            },
            onAccents: {
                handleSingleDraftCompletion(.accents(nil))
            },
            onViewList: {
                handleSingleDraftCompletion(.lists(context.listLaunchContext))
            },
            onLater: {
                handleSingleDraftCompletion(nil)
            }
        )
    }

    /// „Später" (destination == nil) → Completion aus, Detail bleibt offen
    /// (KEIN goHome, anders als ScanImportView). Sonst: navigate pusht das
    /// Modul/die Liste auf den Stack.
    private func handleSingleDraftCompletion(_ destination: AppScreen?) {
        isShowingImportCompletion = false
        importCompletionContext = nil
        if let destination {
            navigate(destination)
        }
    }

    /// Dominant-Typ (phrases vs. words) — gespiegelt von
    /// `ScanImportView.dominantImportedCardType`.
    private func dominantImportedCardType(in items: [VocabularyItem]) -> CardType {
        let phraseCount = items.filter { $0.cardType == .phrases }.count
        let wordCount = items.count - phraseCount
        return phraseCount > wordCount ? .phrases : .words
    }

    // MARK: - Content

    @ViewBuilder
    private func detailContent(draft: ScanDraft) -> some View {
        VStack(spacing: 0) {
            // **Phase D-Fix (2026-05-20)** — Custom-Header, weil die System-
            // Nav-Bar global versteckt ist (RootContentView:170 hängt
            // `.toolbar(.hidden, for: .navigationBar)` auf jede Destination).
            // AppBackButton (App-Chevron) + Titel + „…"-Menu.
            HStack(spacing: 8) {
                AppBackButton(
                    action: { dismiss() },
                    tint: AppSectionStyle.scan.accent
                )

                Text(draft.title)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Menu {
                    Button {
                        startRename()
                    } label: {
                        Label("Umbenennen", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        isShowingDeleteConfirm = true
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 22))
                        .foregroundStyle(AppSectionStyle.scan.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if !draft.imageFilenames.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(draft.imageFilenames, id: \.self) { filename in
                                    DraftImageThumbnail(filename: filename) { image in
                                        fullscreenImage = IdentifiableImage(image: image)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    // **Phase D v3 (2026-05-20)** — App-Standard-CTA statt
                    // generischem `.borderedProminent`: gespiegelt vom „Training
                    // starten"-Button (`SessionPrimaryCTA`). Flaches Amber, kein
                    // Icon, eingebautes Disabled-Graying über `isEnabled`.
                    SessionPrimaryCTA(
                        title: "Zu Lernliste machen",
                        isEnabled: canImport(draft),
                        action: { isShowingTargetChoice = true }
                    )
                    .padding(.horizontal, 16)

                    vocabularySection(draft: draft)
                }
                .padding(.vertical, 16)
            }
        }
    }

    private func vocabularySection(draft: ScanDraft) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("\(draft.previewPairs.count) Vokabeln")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(activeCount(draft)) aktiv")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)

            LazyVStack(spacing: 6) {
                ForEach(draft.previewPairs.indices, id: \.self) { idx in
                    DraftPairRow(pair: draft.previewPairs[idx]) {
                        toggleImportable(at: idx)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Derived

    private func activeCount(_ draft: ScanDraft) -> Int {
        draft.previewPairs.filter(\.isImportable).count
    }

    private func canImport(_ draft: ScanDraft) -> Bool {
        listStore != nil && activeCount(draft) > 0
    }

    // MARK: - Actions

    private func loadDraft() {
        localDraft = draftStore.drafts.first { $0.id == draftID }
    }

    private func toggleImportable(at idx: Int) {
        guard var updated = localDraft, idx < updated.previewPairs.count else { return }
        updated.previewPairs[idx].isImportable.toggle()
        localDraft = updated
        draftStore.update(updated)   // debounced Save im Store
    }

    private func startRename() {
        renameText = localDraft?.title ?? ""
        isShowingRenameSheet = true
    }

    private func commitRename() {
        guard var updated = localDraft else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updated.title = trimmed
        localDraft = updated
        draftStore.update(updated)
    }

    private func performImport(listName: String) {
        guard let listStore, let draft = localDraft else { return }
        let importable = draft.previewPairs.filter(\.isImportable)
        guard !importable.isEmpty else { return }

        let items: [VocabularyItem] = importable.map { pair in
            VocabularyItem(
                french: pair.french,
                german: pair.german,
                cardType: pair.cardType,
                sourceLanguage: .french,
                wordClass: pair.wordClass
            )
        }

        let listID = listStore.ensureCustomList(named: listName)
        let imported = listStore.importItems(
            items,
            preferredListID: listID,
            suggestedListName: listName
        )
        appDebugLog("📋 [ScanDraftDetail] imported \(imported) items into \"\(listName)\"")
        // **Phase D v3** — Neue-Liste-Pfad: echte Item-IDs verfügbar →
        // `importedItemIDs: items.map(\.id)` (Karteikarten scopen auf den Import).
        // Settle-Delay vor dem Content-Swap (NewListNameSheet dismissen lassen).
        let context = ImportCompletionContext(
            importedCount: imported,
            targetListID: listID,
            targetListName: listName,
            language: .french,
            preferredDirection: StudyLanguage.french.defaultDirectionToGerman,
            cardType: dominantImportedCardType(in: items),
            importedItemIDs: items.map(\.id)
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            importCompletionContext = context
            isShowingImportCompletion = true
        }
    }

    // MARK: - Phase D v2 — Bestehende Liste (Merge-Pfad)

    private func handleExistingListChosen(_ listID: UUID) {
        // **Reentrance-Guard (2026-05-20)** — der Picker kann seinen onConfirm-
        // Callback im selben Runloop-Tick doppelt feuern (SwiftUI-Sheet-Quirk).
        // Da `pendingMergePlan` unten SYNCHRON gesetzt wird, fängt dieser Guard
        // den 2. Call ab → kein Doppel-Merge / grauer Screen.
        guard pendingMergePlan == nil else {
            appDebugLog("⚠️ [ScanDraftDetail] handleExistingListChosen called while merge pending — ignoring duplicate")
            return
        }
        appDebugLog("📋 [ScanDraftDetail] handleExistingListChosen entry: listID=\(listID)")
        guard let listStore, let draft = localDraft else { return }
        guard let targetList = listStore.customLists.first(where: { $0.id == listID }) else {
            importFailureMessage = "Lernliste nicht gefunden."
            // Settle-Delay (Konsistenz): Alert nach Picker-Dismiss.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isShowingImportFailureAlert = true
            }
            return
        }

        let importable = draft.previewPairs.filter(\.isImportable)
        let items: [VocabularyItem] = importable.map { pair in
            VocabularyItem(
                french: pair.french,
                german: pair.german,
                cardType: pair.cardType,
                sourceLanguage: .french,
                wordClass: pair.wordClass
            )
        }

        appDebugLog("📋 [ScanDraftDetail] before computePlan, items=\(items.count), existing=\(targetList.items.count)")
        let plan = VocabularyListMergePlanner.computePlan(
            incoming: items,
            existingItems: targetList.items
        )
        appDebugLog("📋 [ScanDraftDetail] after computePlan: requiresUserDecision=\(plan.requiresUserDecision), safeAdds=\(plan.safeAdds.count), conflicts=\(plan.conflicts.count)")
        pendingMergePlan = plan
        pendingTargetListID = listID
        pendingTargetListName = targetList.name
        // **Phase D v3** — Dominant-CardType jetzt merken; in `applyMerge` sind
        // die Original-Items nicht mehr verfügbar (nur der Plan).
        pendingImportCardType = dominantImportedCardType(in: items)

        // Settle-Delay: das vorige Sheet (Picker) erst sauber dismissen
        // lassen, bevor Conflict-Review/Apply kommt (sonst Black-Screen).
        if plan.requiresUserDecision {
            appDebugLog("📋 [ScanDraftDetail] branching to ConflictReview after 0.4s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                appDebugLog("📋 [ScanDraftDetail] asyncAfter fired, setting isShowingConflictReview=true")
                isShowingConflictReview = true
            }
        } else {
            appDebugLog("📋 [ScanDraftDetail] branching to applyMerge after 0.4s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                appDebugLog("📋 [ScanDraftDetail] asyncAfter fired, calling applyMerge")
                applyMerge(plan)
            }
        }
    }

    private func handleConflictReviewConfirmed(_ resolved: [ImportConflict]) {
        // **Reentrance-Guard (2026-05-20)** — ohne pending Plan (z. B. Doppel-
        // Confirm nach bereits abgeschlossenem Merge) nichts tun. `guard let`
        // erfüllt zugleich die „pendingMergePlan != nil"-Bedingung.
        guard var plan = pendingMergePlan else {
            appDebugLog("⚠️ [ScanDraftDetail] handleConflictReviewConfirmed called without pending plan — ignoring")
            return
        }
        plan.conflicts = resolved
        pendingMergePlan = plan
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            applyMerge(plan)
        }
    }

    private func applyMerge(_ plan: MergePlan) {
        appDebugLog("📋 [ScanDraftDetail] applyMerge entry, plan.safeAdds=\(plan.safeAdds.count)")
        guard let listStore, let listID = pendingTargetListID else { return }
        appDebugLog("📋 [ScanDraftDetail] before applyMergePlan call")
        let result = listStore.applyMergePlan(plan, toListWithID: listID)
        appDebugLog("📋 [ScanDraftDetail] after applyMergePlan, status=\(result.status)")

        // Lokale Kopien für die Toast-Message, BEVOR der pending-State
        // zurückgesetzt wird.
        let addedCount = result.added
        let listName = pendingTargetListName
        // **Guard-Release (2026-05-20)** — Merge-Versuch abgeschlossen (Erfolg
        // ODER Fehler): pending-State zurücksetzen, damit handleExistingList-
        // Chosen für einen erneuten Import wieder freigegeben ist.
        pendingMergePlan = nil
        pendingTargetListID = nil

        switch result.status {
        case .success:
            appDebugLog("📋 [ScanDraftDetail] merged into \"\(listName)\" (\(listID))")
            // **Phase D v3** — Merge-Pfad: keine Item-IDs verfügbar → `[]`
            // (Karteikarten fallen auf die Gesamtliste zurück). cardType aus dem
            // in handleExistingListChosen gemerkten Dominant-Typ. Settle-Delay
            // vor dem Content-Swap.
            let context = ImportCompletionContext(
                importedCount: addedCount,
                targetListID: listID,
                targetListName: listName,
                language: .french,
                preferredDirection: StudyLanguage.french.defaultDirectionToGerman,
                cardType: pendingImportCardType,
                importedItemIDs: []
            )
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                importCompletionContext = context
                isShowingImportCompletion = true
            }
        case .targetListMissing:
            importFailureMessage = "Die Lernliste wurde inzwischen gelöscht."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isShowingImportFailureAlert = true
            }
        case .persistenceMismatch:
            importFailureMessage = "Speichern fehlgeschlagen. Bitte erneut versuchen."
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                isShowingImportFailureAlert = true
            }
        }
    }

    private func deleteDraft() {
        draftStore.remove(draftID)
        dismiss()
    }
}

// MARK: - Identifiable Image Wrapper (für .sheet(item:))

private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

// MARK: - Vokabel-Row (leicht, nur isImportable-Toggle)

private struct DraftPairRow: View {
    let pair: ImportPreviewPair
    let onToggle: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggle) {
                Image(systemName: pair.isImportable ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(pair.isImportable ? AppTheme.Colors.success : Color.secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(pair.french)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(!pair.isImportable)
                    .foregroundStyle(.primary)
                Text(pair.german)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(
            AppTheme.Colors.secondarySurface,
            in: RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
        )
        .opacity(pair.isImportable ? 1.0 : 0.55)
    }
}

// MARK: - Bild-Thumbnail (async)

private struct DraftImageThumbnail: View {
    let filename: String
    let onTap: (UIImage) -> Void
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 80, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                    .contentShape(Rectangle())
                    .onTapGesture { onTap(image) }
            } else {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(AppTheme.Colors.secondarySurface)
                    .frame(width: 80, height: 110)
                    .overlay(ProgressView())
            }
        }
        .task {
            let loaded = await Task.detached(priority: .userInitiated) {
                ScanDraftImageStore.loadImage(filename: filename)
            }.value
            await MainActor.run { self.image = loaded }
        }
    }
}

// MARK: - KISS Vollbild-Viewer (kein Zoom)

private struct FullscreenImageView: View {
    let image: UIImage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding()
            }
        }
    }
}
