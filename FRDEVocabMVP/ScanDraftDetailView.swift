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

    @ObservedObject private var draftStore = ScanDraftStore.shared
    @Environment(\.dismiss) private var dismiss

    @State private var localDraft: ScanDraft?
    @State private var isShowingNewListNameSheet = false
    @State private var isShowingRenameSheet = false
    @State private var renameText = ""
    @State private var isShowingDeleteConfirm = false
    @State private var isShowingPostImportConfirm = false
    @State private var fullscreenImage: IdentifiableImage?

    var body: some View {
        Group {
            if let draft = localDraft {
                detailContent(draft: draft)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(localDraft?.title ?? "Entwurf")
        .navigationBarTitleDisplayMode(.inline)
        .appScreenBackground(.scan)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
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
                }
            }
        }
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
        .alert("Liste wurde erstellt", isPresented: $isShowingPostImportConfirm) {
            Button("Behalten", role: .cancel) {}
            Button("Entwurf löschen", role: .destructive) { deleteDraft() }
        } message: {
            Text("Entwurf jetzt löschen?")
        }
    }

    // MARK: - Content

    @ViewBuilder
    private func detailContent(draft: ScanDraft) -> some View {
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

                Button {
                    isShowingNewListNameSheet = true
                } label: {
                    Label("Zu Liste machen", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!canImport(draft))
                .padding(.horizontal, 16)

                vocabularySection(draft: draft)
            }
            .padding(.vertical, 16)
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
        isShowingPostImportConfirm = true
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
