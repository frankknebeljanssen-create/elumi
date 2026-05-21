// ListMergePickerSheet.swift
// **List-Merge Phase 1 (2026-05-21)** — Multi-Select-Sheet zum
// Zusammenführen mehrerer Listen in EINE neue Liste. Eigene View;
// `ListPickerSheet` bleibt bewusst unverändert (Single-Select, andere
// Caller). Zeigt alle übergebenen Listen (custom + Standard) mit
// Checkbox + Vokabel-Anzahl; die Action-Bar unten führt via
// `onMergeRequested(Set<UUID>)` weiter in die Namensabfrage
// (`NewListNameSheet`) — die Sheet-Kette + der Merge werden vom
// `ListMergeCoordinator` im Caller (`ListsView`) getrieben.
//
// **Size-Guards (Phase B, 2026-05-21):** schützen vor pathologisch
// großen Merges (Diagnose Daten-Verlust): ab `warnThreshold` Vokabeln
// kommt ein Bestätigungs-Dialog, ab `hardCap` ist der Button gesperrt.

import SwiftUI

struct ListMergePickerSheet: View {
    /// Anzuzeigende Listen — Caller reicht `listStore.allLists`
    /// (Eigene + Standard-Niveau/Themen-Listen).
    let lists: [VocabularyList]

    /// Wird mit der finalen Auswahl aufgerufen (garantiert ≥ 2 durch den
    /// disabled-State der Action-Bar). Der Caller startet die Sheet-Kette.
    let onMergeRequested: (Set<UUID>) -> Void
    let onCancel: () -> Void

    @State private var selectedListIDs: Set<UUID> = []
    @State private var showMergeConfirm = false

    /// Ab dieser Gesamt-Vokabel-Anzahl wird vor dem Merge rückgefragt.
    private static let warnThreshold = 2_000
    /// Harte Obergrenze — darüber ist der Merge gesperrt (Schutz gegen
    /// pathologisch große Persist-Payloads).
    private static let hardCap = 10_000

    private var accent: Color { AppSectionStyle.lists.accent }

    /// Summe der Vokabeln über alle aktuell selektierten Listen.
    private var selectedItemCount: Int {
        selectedListIDs.reduce(0) { sum, id in
            sum + (lists.first { $0.id == id }?.items.count ?? 0)
        }
    }

    private var exceedsHardCap: Bool { selectedItemCount > Self.hardCap }
    private var isMergeDisabled: Bool { selectedListIDs.count < 2 || exceedsHardCap }

    var body: some View {
        NavigationStack {
            List {
                ForEach(lists, id: \.id) { list in
                    Button {
                        toggle(list.id)
                    } label: {
                        row(for: list)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.plain)
            .navigationTitle("Listen zusammenführen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { onCancel() }
                }
            }
            .safeAreaInset(edge: .bottom) { actionBar }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for list: VocabularyList) -> some View {
        let isSelected = selectedListIDs.contains(list.id)
        HStack(spacing: 12) {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isSelected ? accent : AppTheme.Colors.textSecondary.opacity(0.5))

            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                // Built-in dezent markieren (ListPickerSheet trennt ebenfalls
                // nach `isBuiltIn`); rein informativ, nicht selektions-relevant.
                if list.isBuiltIn {
                    Text("Standardliste")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text("\(list.items.count) Vokabeln")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    // MARK: - Action-Bar

    private var actionBar: some View {
        VStack(spacing: 0) {
            Button {
                handleMergeTap()
            } label: {
                Text(actionBarLabel)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: accent))
            .disabled(isMergeDisabled)
            // AppPrimaryButtonStyle dimmt nicht selbst — Disabled-Look manuell.
            .opacity(isMergeDisabled ? 0.55 : 1.0)
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .confirmationDialog(
                "\(selectedItemCount) Vokabeln werden zusammengeführt — fortfahren?",
                isPresented: $showMergeConfirm,
                titleVisibility: .visible
            ) {
                Button("Fortfahren") { onMergeRequested(selectedListIDs) }
                Button("Abbrechen", role: .cancel) {}
            }
        }
        .frame(maxWidth: .infinity)
        .background(.ultraThinMaterial)
    }

    private var actionBarLabel: String {
        if exceedsHardCap {
            return "Zu viele Vokabeln (max. \(Self.hardCap))"
        }
        return "Zusammenführen (\(selectedListIDs.count))"
    }

    /// Tap-Handler: Hard-Cap sperrt (Button ist ohnehin disabled),
    /// Warn-Threshold löst Rückfrage aus, sonst direkt weiter.
    private func handleMergeTap() {
        guard selectedListIDs.count >= 2, !exceedsHardCap else { return }
        if selectedItemCount > Self.warnThreshold {
            showMergeConfirm = true
        } else {
            onMergeRequested(selectedListIDs)
        }
    }

    // MARK: - Selection

    private func toggle(_ id: UUID) {
        if selectedListIDs.contains(id) {
            selectedListIDs.remove(id)
        } else {
            selectedListIDs.insert(id)
        }
    }
}
