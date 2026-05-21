// ScanDraftsSectionView.swift
// **Meine Scans — Phase C/D/E + Scan-Redesign (2026-05-21)** — Sektion im
// Scan-Tab. Zeigt gespeicherte `ScanDraft`s als **horizontal scrollbare** Reihe
// kompakter Cards (kleines Thumbnail + Counter-Pill + Title + Datum + Trash).
// Sitzt unter Schritt 2 im Choice-Screen; blendet sich bei leer aus.
//
// • Section-Label nutzt `ScanSectionLabel(stepNumber: 3, …)` — selbe Optik wie 1./2.
// • Multi-Select-Checkbox (Phase E) bleibt funktional; Card-Tap öffnet Detail.
// • Trash mit Confirmation-Alert (löscht via `ScanDraftStore.remove` inkl. Bilder).

import SwiftUI

struct ScanDraftsSectionView: View {
    @ObservedObject private var draftStore = ScanDraftStore.shared

    /// **Phase D** — öffnet die Detail-View eines Drafts.
    let onOpenDraft: (UUID) -> Void

    /// **Phase E** — Multi-Select-State lebt in `ScanImportView`; hier als Binding.
    @Binding var selectedDraftIDs: Set<UUID>

    var body: some View {
        if !draftStore.drafts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                // **Scan-Redesign** — selbe Komponente/Optik wie „1./2." (Schritt 3).
                ScanSectionLabel(stepNumber: 3, title: "Meine Scans")

                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 10) {
                        ForEach(draftStore.drafts) { draft in
                            HorizontalScanDraftCard(
                                draft: draft,
                                isSelected: selectedDraftIDs.contains(draft.id),
                                onOpenDraft: onOpenDraft,
                                onToggleSelect: { toggleSelection(draft.id) }
                            )
                        }
                    }
                    // 4 statt 16: die Section liegt bereits in `screenPadding`,
                    // 4 richtet die erste Card am Section-Label aus.
                    .padding(.horizontal, 4)
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

// MARK: - Horizontale Draft-Card (Scan-Redesign 2026-05-21)

private struct HorizontalScanDraftCard: View {
    let draft: ScanDraft
    let isSelected: Bool
    let onOpenDraft: (UUID) -> Void
    let onToggleSelect: () -> Void

    @State private var thumbnail: UIImage?
    @State private var showDeleteConfirm = false

    // Fixe Card-Maße — 110 (Spec) hätte die 4 Zeilen geklippt → 124.
    private static let cardWidth: CGFloat = 160
    private static let cardHeight: CGFloat = 124

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top-Row: Checkbox + Thumbnail (links), Counter-Pill (oben rechts).
            ZStack(alignment: .topTrailing) {
                HStack(alignment: .center, spacing: 8) {
                    Button(action: onToggleSelect) {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(isSelected
                                ? AppSectionStyle.scan.accent
                                : AppTheme.Colors.textSecondary.opacity(0.5))
                            .frame(width: 30, height: 30)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    thumbnailView
                        .frame(width: 38, height: 38)

                    Spacer(minLength: 0)
                }

                // Counter-Pill — Vokabelzahl (= previewPairs.count, wie bisher angezeigt).
                Text("\(draft.previewPairs.count) Vok.")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppSectionStyle.scan.accent.opacity(0.9), in: Capsule())
            }
            .padding(.top, 10)
            .padding(.horizontal, 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(draft.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                Text(relativeDateString(for: draft.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.top, 6)

            Spacer(minLength: 0)

            // Trash klein, unten rechts (gegenüberliegende Ecke zum Counter-Pill).
            HStack {
                Spacer()
                Button {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 4)
        }
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .fill(AppTheme.Colors.setupCardBackground)
        )
        .overlay(
            // Selected → Accent-Border (klareres Multi-Select-Signal neben der
            // Checkbox); sonst der ruhige setupCardBorder.
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .stroke(isSelected ? AppSectionStyle.scan.accent : AppTheme.Colors.setupCardBorder,
                        lineWidth: isSelected ? 1.5 : 1)
        )
        // Card-Tap öffnet Detail; Checkbox + Trash fangen ihre Taps selbst ab
        // (Button-Priorität über onTapGesture) → kein Tap-Konflikt (wie Phase D/E).
        .contentShape(Rectangle())
        .onTapGesture { onOpenDraft(draft.id) }
        .task { await loadThumbnail() }
        .alert("Entwurf löschen?", isPresented: $showDeleteConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) {
                ScanDraftStore.shared.remove(draft.id)
            }
        } message: {
            Text("\"\(draft.title)\" wird unwiderruflich gelöscht.")
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
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
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
        }
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
