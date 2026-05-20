// ScanDraftsSectionView.swift
// **Meine Scans — Phase C (2026-05-20)** — Sektion im Scan-Tab, die
// gespeicherte `ScanDraft`s als vertikale Liste anzeigt. Sitzt unter
// den Capture-Optionen (Schritt 2) im Choice-Screen von ScanImportView.
//
// Blendet sich selbst aus, wenn keine Drafts existieren. Karten sind
// non-tappable (Detail-View kommt in Phase D); einzige Aktion ist der
// Trash-Button mit Confirmation-Alert (Delete ist irreversibel — löscht
// via `ScanDraftStore.remove` auch die zugehörigen Bilder).

import SwiftUI

struct ScanDraftsSectionView: View {
    @ObservedObject private var draftStore = ScanDraftStore.shared

    /// **Phase D (2026-05-20)** — öffnet die Detail-View eines Drafts.
    let onOpenDraft: (UUID) -> Void

    /// **Phase E (2026-05-20)** — Multi-Select. Der State lebt in
    /// `ScanImportView` (die Action-Bar braucht Screen-Ebene); hier nur als
    /// Binding, damit die Checkbox toggeln kann.
    @Binding var selectedDraftIDs: Set<UUID>

    var body: some View {
        if !draftStore.drafts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Meine Scans")
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 4)

                LazyVStack(spacing: 8) {
                    ForEach(draftStore.drafts) { draft in
                        ScanDraftCard(
                            draft: draft,
                            isSelected: selectedDraftIDs.contains(draft.id),
                            onOpenDraft: onOpenDraft,
                            onToggleSelect: { toggleSelection(draft.id) }
                        )
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    private func toggleSelection(_ id: UUID) {
        if selectedDraftIDs.contains(id) {
            selectedDraftIDs.remove(id)
        } else {
            selectedDraftIDs.insert(id)
        }
    }
}

private struct ScanDraftCard: View {
    let draft: ScanDraft
    // **Phase E (2026-05-20)** — Multi-Select-Zustand + Toggle-Callback.
    let isSelected: Bool
    let onOpenDraft: (UUID) -> Void
    let onToggleSelect: () -> Void
    @State private var thumbnail: UIImage?
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 12) {
            // **Phase E** — Checkbox als eigenes 44pt-Tap-Target, ganz links
            // vor dem Thumbnail. Card-Tap (öffnen) + Trash bleiben getrennt.
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(isSelected
                        ? AppSectionStyle.scan.accent
                        : AppTheme.Colors.textSecondary.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Thumbnail (erstes Bild, async geladen)
            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.sm)
                    .fill(AppTheme.Colors.secondarySurface)

                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm))
                } else {
                    Image(systemName: "doc.text.image")
                        .font(.system(size: 22))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 56, height: 56)

            // Title + Meta
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                Text(metaText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            // **Phase D** — Affordance, dass die Card öffnet.
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)

            // Trash-Button (44pt Tap-Target, subtil)
            Button {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .alert("Entwurf löschen?", isPresented: $showDeleteConfirm) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) {
                    ScanDraftStore.shared.remove(draft.id)
                }
            } message: {
                Text("\"\(draft.title)\" wird unwiderruflich gelöscht.")
            }
        }
        .padding(12)
        // **Phase E** — Selected-State über höhere Card-Intensität +
        // Accent-Border (gespiegelt von FlashcardStackComposerSheet).
        .appCardBackground(.scan, intensity: isSelected ? AppTheme.CardIntensity.selected : AppTheme.CardIntensity.soft)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .stroke(isSelected ? AppSectionStyle.scan.accent.opacity(0.5) : Color.clear, lineWidth: 1.5)
        )
        // **Phase D** — ganze Card öffnet die Detail-View. Der Trash-Button
        // fängt seine Taps selbst ab (Button) → kein Tap-Konflikt.
        .contentShape(Rectangle())
        .onTapGesture { onOpenDraft(draft.id) }
        .task {
            await loadThumbnail()
        }
    }

    private var metaText: String {
        let dateString = relativeDateString(for: draft.createdAt)
        let pairCount = draft.previewPairs.count
        var parts = ["\(dateString) · \(pairCount) Vokabeln"]
        if draft.imageFilenames.count > 1 {
            parts.append("\(draft.imageFilenames.count) Seiten")
        }
        return parts.joined(separator: " · ")
    }

    private func relativeDateString(for date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"
        let time = timeFormatter.string(from: date)

        if calendar.isDateInToday(date) {
            return "heute, \(time)"
        } else if calendar.isDateInYesterday(date) {
            return "gestern, \(time)"
        } else {
            let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
            if days < 7 {
                return "vor \(days) Tagen, \(time)"
            } else {
                let formatter = DateFormatter()
                formatter.dateFormat = "dd.MM., HH:mm"
                return formatter.string(from: date)
            }
        }
    }

    private func loadThumbnail() async {
        guard let filename = draft.imageFilenames.first else { return }
        let image = await Task.detached(priority: .userInitiated) {
            ScanDraftImageStore.loadImage(filename: filename)
        }.value
        await MainActor.run {
            self.thumbnail = image
        }
    }
}
