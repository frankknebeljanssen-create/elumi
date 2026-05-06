import SwiftUI

/// **Single-Select-Picker** für bestehende Custom-Listen — Schritt 2
/// im neuen Import-Flow, wenn der User „Zu bestehender Liste hinzufügen"
/// gewählt hat.
///
/// **Wichtig**: nur `customLists` werden angezeigt — Built-in-Listen
/// sind read-only und können nicht als Merge-Ziel dienen. Wenn der
/// User keine eigene Liste hat, zeigen wir einen leeren Zustand mit
/// einem CTA, der den Flow zum „neue Liste"-Pfad zurückleitet.
///
/// Style orientiert sich an `WordRunnerListPickerSheet` (insetGrouped
/// List + Checkmark + AppTapButtonStyle), damit das UI-Gefühl konsistent
/// bleibt.
struct ExistingListPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: VocabularyListStore
    let importableCount: Int
    let onConfirm: (UUID) -> Void
    let onFallbackToNewList: () -> Void

    @State private var selectedListID: UUID?

    private var pickerLists: [VocabularyList] {
        store.customLists.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if pickerLists.isEmpty {
                    emptyState
                } else {
                    listContent
                }
            }
            .navigationTitle("Liste wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !pickerLists.isEmpty {
                    confirmButton
                        .padding(.horizontal, 20)
                        .padding(.bottom, 18)
                        .background(AppTheme.Colors.surface)
                }
            }
        }
    }

    // MARK: - Subviews

    private var listContent: some View {
        List {
            Section(header: Text("\(importableCount) Einträge bereit zum Import")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .textCase(.uppercase)) {
                ForEach(pickerLists, id: \.id) { list in
                    rowFor(list)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func rowFor(_ list: VocabularyList) -> some View {
        let isSelected = list.id == selectedListID
        return Button {
            withAnimation(AppMotion.state) {
                selectedListID = list.id
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(list.name)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("\(list.items.count) \(list.items.count == 1 ? "Eintrag" : "Einträge")")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.elumiPink)
                        .transition(.opacity.combined(with: .scale))
                }
            }
            .contentShape(Rectangle())
            .appSelectionHighlight(isSelected: isSelected)
        }
        .buttonStyle(AppTapButtonStyle())
    }

    private var confirmButton: some View {
        Button {
            guard let id = selectedListID else { return }
            dismiss()
            DispatchQueue.main.async { onConfirm(id) }
        } label: {
            Text("In diese Liste einfügen")
                .font(AppTheme.Typography.button)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
        }
        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
        .disabled(selectedListID == nil)
        .opacity(selectedListID == nil ? 0.55 : 1.0)
    }

    private var emptyState: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text("Du hast noch keine eigenen Listen.")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
            Text("Lege eine neue Liste an und importiere die Scan-Einträge dort.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            Button {
                dismiss()
                DispatchQueue.main.async { onFallbackToNewList() }
            } label: {
                // **Naming-Sweep 2026-05-06** — „Neue Liste
                // anlegen" → „+ Neue Liste".
                Text("+ Neue Liste")
                    .font(AppTheme.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .padding(.horizontal, 24)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            .padding(.horizontal, 32)
            Spacer()
        }
    }
}
