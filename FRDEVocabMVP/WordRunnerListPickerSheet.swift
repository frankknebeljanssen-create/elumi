import SwiftUI

/// **Liste-wählen-Sheet** für den Word-Runner-Start-Screen
/// (Phase 7.5 — Start-Flow-Final).
///
/// Präsentiert alle verfügbaren Vokabellisten (Built-in + Custom,
/// alphabetisch sortiert) in einer Standard-`List`, mit Häkchen
/// beim aktuell gewählten Eintrag. Tap auf eine Zeile schaltet die
/// Auswahl um; ein expliziter **„Fertig"-Button** oben rechts
/// schließt die Sheet (User-Spec).
///
/// Motion: Standard-SwiftUI-Sheet-Transition (Slide-Up). Keine
/// eigene Animation — die System-Navigation reicht für den
/// „ruhig, modern"-Look aus der Motion-Spec.
///
/// Rückkehr zum Start-Screen: Die neue Auswahl propagiert sofort
/// via `@ObservedObject`-Reaktivität auf `VocabularyListStore`.
/// Der WR-Start-Screen rechnet `hasUsableList` + Pool neu.
struct WordRunnerListPickerSheet: View {
    @ObservedObject var store: VocabularyListStore
    let onDismiss: () -> Void

    /// Liste aller wählbaren Listen (Built-in zuerst, danach Custom
    /// alphabetisch). Identisch zur Helper-Funktion im Start-Screen,
    /// bewusst lokal gehalten — kein shared Helper, weil dieser
    /// Sheet-Context keine anderen Abhängigkeiten braucht.
    private var availableLists: [VocabularyList] {
        var result: [VocabularyList] = [store.builtInList]
        result.append(contentsOf: store.customLists.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        })
        return result
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(availableLists, id: \.id) { list in
                    let isSelected = list.id == store.selectedListID
                    Button {
                        // State-Change-Animation (Phase 7.6): sanfter
                        // Highlight-Wechsel über `AppMotion.state` (180 ms).
                        withAnimation(AppMotion.state) {
                            store.selectedListID = list.id
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(list.name)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                Text("\(list.items.count) Einträge")
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
                        // Selection-Highlight aus `AppMotion` —
                        // minimaler Scale-Puls bei Auswahl-Wechsel
                        // (User-Spec „neue Auswahl bekommt Highlight:
                        // Fade + minimal Scale").
                        .appSelectionHighlight(isSelected: isSelected)
                    }
                    .buttonStyle(AppTapButtonStyle())
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Liste wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        onDismiss()
                    }
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                }
            }
        }
    }
}
