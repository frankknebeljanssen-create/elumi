import SwiftUI

/// **Multi-Capture-Review** (User-Spec 2026-04-22 Abend VI).
///
/// Wird präsentiert, wenn der User im Auto-Modus mehrere Bilder
/// aufgenommen hat und auf „Fertig" tippt. Statt sofort eine
/// asynchrone Sequenz-Verarbeitung über alle 10 Bilder zu starten
/// (vorheriges Verhalten — UI dead, Captures lost), öffnet sich
/// dieser Screen.
///
/// **UI-Aufbau**:
///   • Top-Bar mit „Zurück" (preserves capturedItems) und
///     „Verwerfen" (explizites Discard)
///   • Großer Preview-Bereich des aktuell ausgewählten Bildes
///   • Swipe-Gesture/TabView für horizontalen Wechsel
///   • Horizontale Filmstrip-Leiste unten (tappbar)
///   • Pro selektiertem Bild zwei Aktionen:
///     – „Überprüfen" (primär) → triggert bestehenden Single-Image-
///       Review-Pfad auf dieses Bild
///     – „Löschen" (sekundär) → entfernt nur dieses Bild aus der
///       Sammlung, nächstes/vorheriges wird selektiert
///
/// **Nicht-Ziele** (per Spec):
///   • Keine Bulk-Verarbeitung aller Bilder gleichzeitig (würde 10×
///     Claude-Vision-Calls auslösen — teuer und langsam)
///   • Keine Änderungen an OCR/Analyse-Pipeline
///
/// **Wichtig**: Solange der View existiert, bleiben die Captures in
/// `session.capturedItems`. Sie werden NUR durch
/// `onDiscardAll`-Callback komplett geleert (oder durch das
/// erfolgreiche Übernehmen via „Überprüfen" → Pipeline läuft → Items
/// werden durch den Caller entscheidet).
struct MultiCaptureReviewView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var items: [CapturedScanItem]
    @Binding var selectedItemID: UUID?
    let sectionStyle: AppSectionStyle
    /// Wird mit dem aktuell ausgewählten Bild aufgerufen, sobald der
    /// User „Überprüfen" tippt. Caller startet damit den bestehenden
    /// Single-Image-Review-Pfad. Der Sheet wird vorher geschlossen.
    let onReviewSelected: (CapturedScanItem) -> Void
    /// Callback zum Hinzufügen weiterer Aufnahmen — der User kommt
    /// damit zurück in den Scanner und kann dranbauen.
    let onAddMoreCaptures: () -> Void
    /// Explizites „alle verwerfen" — nur dann werden die capturedItems
    /// komplett geleert.
    let onDiscardAll: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if items.isEmpty {
                    emptyState
                } else {
                    bigPreview
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    filmstrip
                        .padding(.vertical, 12)
                    actionButtons
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                }
            }
            .background(AppTheme.Colors.background)
            .navigationTitle(navigationTitleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        // Zurück preserves items — der User kann später
                        // wiederkommen. Nur ein Sheet-Dismiss.
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button(role: .none) {
                            dismiss()
                            DispatchQueue.main.async { onAddMoreCaptures() }
                        } label: {
                            Label("Mehr aufnehmen", systemImage: "camera.fill")
                        }
                        Button(role: .destructive) {
                            dismiss()
                            DispatchQueue.main.async { onDiscardAll() }
                        } label: {
                            Label("Alle verwerfen", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
            }
        }
        .onAppear(perform: ensureSelection)
        .onChange(of: items) { _, newItems in
            ensureSelectionIfNeeded(in: newItems)
        }
    }

    // MARK: - Header-Title

    private var navigationTitleText: String {
        if items.isEmpty { return "Aufnahmen" }
        let total = items.count
        let pos = (currentIndex ?? 0) + 1
        return "\(pos) von \(total)"
    }

    // MARK: - Big-Preview (Swipe via TabView)

    @ViewBuilder
    private var bigPreview: some View {
        TabView(selection: bindingForSelection) {
            ForEach(items) { item in
                ZStack {
                    Color.black.opacity(0.55)
                    Image(uiImage: item.originalImage)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                    if item.status == .analyzed {
                        statusBadge(text: "Bereits geprüft", color: AppTheme.Colors.success, system: "checkmark.seal.fill")
                    } else if item.status == .failed {
                        statusBadge(text: "Analyse fehlgeschlagen", color: AppTheme.Colors.warning, system: "exclamationmark.triangle.fill")
                    }
                }
                .tag(item.id)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }

    private func statusBadge(text: String, color: Color, system: String) -> some View {
        VStack {
            HStack {
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: system)
                        .font(.system(size: 12, weight: .bold))
                    Text(text)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(color))
                .padding(12)
            }
            Spacer()
        }
    }

    /// Selection-Binding für TabView. Default zum ersten Item, falls
    /// `selectedItemID` (noch) nicht gesetzt ist — dadurch ist immer
    /// genau ein Bild aktiv (User-Spec).
    private var bindingForSelection: Binding<UUID> {
        Binding(
            get: {
                selectedItemID ?? items.first?.id ?? UUID()
            },
            set: { newID in
                selectedItemID = newID
            }
        )
    }

    // MARK: - Filmstrip

    private var filmstrip: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        thumbnailButton(for: item)
                            .id(item.id)
                    }
                }
                .padding(.horizontal, 14)
            }
            .onChange(of: selectedItemID) { _, newID in
                guard let newID else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    proxy.scrollTo(newID, anchor: .center)
                }
            }
        }
    }

    private func thumbnailButton(for item: CapturedScanItem) -> some View {
        let isSelected = item.id == selectedItemID
        return Button {
            withAnimation(AppMotion.state) {
                selectedItemID = item.id
            }
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(uiImage: item.originalImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                if item.status == .analyzed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.success)
                        .background(Circle().fill(.white))
                        .padding(3)
                } else if item.status == .failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.warning)
                        .background(Circle().fill(.white))
                        .padding(3)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? sectionStyle.accent : Color.white.opacity(0.18), lineWidth: isSelected ? 2.4 : 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Action-Buttons

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                guard let item = currentItem else { return }
                dismiss()
                DispatchQueue.main.async { onReviewSelected(item) }
            } label: {
                Label("Überprüfen", systemImage: "doc.text.viewfinder")
                    .font(AppTheme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 52)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            .disabled(currentItem == nil)

            Button(role: .destructive) {
                deleteCurrent()
            } label: {
                Label("Diese Aufnahme löschen", systemImage: "trash")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.Colors.warning)
            .disabled(currentItem == nil)
        }
    }

    // MARK: - Empty-State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text("Keine Aufnahmen mehr.")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            Button {
                dismiss()
            } label: {
                Text("Schließen")
                    .font(AppTheme.Typography.button)
                    .frame(minWidth: 180)
                    .frame(minHeight: 50)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            Spacer()
        }
    }

    // MARK: - Helpers

    private var currentIndex: Int? {
        guard let id = selectedItemID else { return nil }
        return items.firstIndex(where: { $0.id == id })
    }

    private var currentItem: CapturedScanItem? {
        guard let idx = currentIndex else { return nil }
        return items[idx]
    }

    private func ensureSelection() {
        if selectedItemID == nil || items.first(where: { $0.id == selectedItemID }) == nil {
            selectedItemID = items.first?.id
        }
    }

    private func ensureSelectionIfNeeded(in newItems: [CapturedScanItem]) {
        // Nach Delete/Reload: falls die Auswahl nicht mehr existiert,
        // springen wir auf das nächste verfügbare Item.
        if let id = selectedItemID, newItems.contains(where: { $0.id == id }) { return }
        selectedItemID = newItems.first?.id
    }

    private func deleteCurrent() {
        guard let id = selectedItemID,
              let idx = items.firstIndex(where: { $0.id == id }) else { return }
        let nextSelectionID: UUID? = {
            if items.count <= 1 { return nil }
            let nextIdx = idx < items.count - 1 ? idx + 1 : idx - 1
            return items[nextIdx].id
        }()
        withAnimation(.easeInOut(duration: 0.2)) {
            items.remove(at: idx)
            selectedItemID = nextSelectionID
        }
    }
}
