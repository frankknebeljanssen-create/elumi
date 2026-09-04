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
                ScanSectionLabel(stepNumber: 3, title: "Meine Scans (Entwürfe)")

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
            // „Meine Scans"-Abstand zu den WOHER-Cards (2026-05-21): 72 → 32
            // (insg. 40px höher gerückt). Footer-Padding 18 unverändert.
            .padding(.top, 32)
            .padding(.bottom, 18)
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

    // **Scan-Redesign (2026-05-21)** — einzeilige, kompakte Card. Breite fix,
    // Höhe intrinsisch (eine Zeile, ~64pt). 250pt, damit Titel + „· N Vok."
    // voll passen (180/200 hätten den Titel abgeschnitten).
    private static let cardWidth: CGFloat = 250

    var body: some View {
        HStack(spacing: 10) {
            // Checkbox (eigenes Tap-Target).
            Button(action: onToggleSelect) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(isSelected
                        ? AppSectionStyle.scan.accent
                        : AppTheme.Colors.textSecondary.opacity(0.5))
                    .frame(width: 26, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            thumbnailView
                .frame(width: 44, height: 44)

            // 3-zeilig (User-Wunsch 2026-05-21): Titel / Vokabel-Anzahl / Zeitstempel.
            VStack(alignment: .leading, spacing: 2) {
                // Zeile 1: Titel (Datum-only, ohne Uhrzeit).
                Text(displayTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                // Zeile 2: Vokabel-Anzahl (Coral-Akzent).
                Text("\(draft.previewPairs.count) Vokabeln")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(AppSectionStyle.scan.accent)
                    .lineLimit(1)
                // Zeile 3: Zeitstempel.
                Text(relativeDateString(for: draft.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Trash klein.
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
        // „Cards mehr Platz" (2026-05-21): vertikales Padding 16 → Card ~+20% höher.
        .padding(.horizontal, 14)
        .padding(.vertical, 16)
        .frame(width: Self.cardWidth)
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

    /// Titel ohne „· HH:MM"-Endung (Datum-Dedup). `autoTitle` erzeugt seit dem
    /// Redesign nur noch das Datum; dieser Strip deckt zusätzlich ältere Drafts,
    /// deren persistierter Titel die Uhrzeit noch enthält. Custom-Titel ohne
    /// dieses Muster bleiben unverändert.
    private var displayTitle: String {
        draft.title.replacingOccurrences(
            of: #" · \d{2}:\d{2}$"#,
            with: "",
            options: .regularExpression
        )
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
