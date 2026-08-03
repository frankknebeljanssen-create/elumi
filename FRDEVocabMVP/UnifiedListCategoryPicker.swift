import SwiftUI

/// Vereinheitlichter Kategorie-Picker für die Übungsmodi.
///
/// **Listenpicker-Vereinheitlichung (2026-05-22)** — rendert die
/// „Meine Listen"-Kategorie-Cards über die geteilte `ListCategoryRow`:
/// Eigene / Niveau / Themen (optional Wörterbuch). Ein Tap öffnet einen
/// kategorie-gefilterten `GlobalListPickerSheet` (gleicher Sheet wie im
/// Setup-Modal, nur mit `filter` + `categoryHeaders: false`).
///
/// **Cross-Category:** die volle aktuelle Selektion wird als
/// `initialSelection` in jedes Sheet gereicht; der Sheet togglet nur die
/// gefilterten Listen und gibt das komplette Set zurück. So bleiben
/// Auswahlen aus anderen Kategorien erhalten und `onCommit` bekommt immer
/// die vollständige Gesamt-Selektion.
struct UnifiedListCategoryPicker: View {
    /// Alle für das Modul verfügbaren Listen (built-in + custom). Wird pro
    /// Kategorie gefiltert — sowohl für die Count-Badges der Cards als auch
    /// als `allLists` des jeweiligen Sheets.
    let availableLists: [VocabularyList]

    /// Aktuelle Gesamt-Selektion (über alle Kategorien). Geht als
    /// `initialSelection` in jeden geöffneten Sheet.
    let selectedIDs: Set<UUID>

    /// Liefert nach „Fertig" die neue Gesamt-Selektion (cross-category).
    let onCommit: (Set<UUID>) -> Void

    /// Sektionsfarbe des Moduls — wird an `ListCategoryRow` durchgereicht.
    /// (Nicht in der ursprünglichen Param-Liste, aber nötig: `ListCategoryRow`
    /// erwartet die Akzentfarbe explizit, damit jedes Modul seine Farbe behält.)
    let accent: Color

    /// Single-Select-Modus (Akzente / Word Runner). Default Multi-Select.
    var singleSelect: Bool = false

    /// Optionale 4. Card „Wörterbuch" (nur Vocabulary-Modus). Default aus.
    var includeWoerterbuch: Bool = false

    /// Item-Bezeichnung des Moduls (z. B. „Nomen"). Teil der Picker-API laut
    /// Spec; aktuell vom Aufrufer für die separate Lemma-/Count-Anzeige
    /// genutzt (siehe Pilot-Modus), im Picker selbst noch nicht gerendert.
    let itemLabel: String

    /// Footer-Chrome durchreichen (analog `GlobalListPickerSheet`). Default nil.
    var feedbackPlayer: FeedbackPlayer? = nil
    var onHome: (() -> Void)? = nil
    /// Settings-Callback — vom Aufrufer durchgereicht, damit der Footer-
    /// Settings-Button funktioniert (kein globaler Fallback vorhanden).
    /// Default nil → Button ausgegraut (Sheet-Nutzung ohne Footer).
    var onSettings: (() -> Void)? = nil

    /// **W2-Modus (2026-05-22)** — Wörterbuch-Direct-Select. Wenn gesetzt,
    /// ruft ein Tap auf die Wörterbuch-Card KEIN Sheet auf, sondern diese
    /// Closure — danach dismissed sich der Picker selbst. Aufrufer setzt
    /// `session.selectedTrainingListIDs` in der Closure. Fallback (nil):
    /// normales Sheet-Verhalten (W1).
    var onWoerterbuchDirectSelect: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    /// Steuert `.appLocalChrome`: wenn globales Chrome aktiv (Home-Ebene),
    /// kein lokales BottomBar-Inset nötig; pushed Screens: immer false.
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome

    /// Welche Kategorie ist gerade als Sheet offen.
    @State private var activeCategory: Category? = nil

    private enum Category: Int, Identifiable {
        case own, level, topic, woerterbuch
        var id: Int { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Push-Stil-Header — AppBackButton (64 pt Touch-Target) +
            // zentrierter Titel + Balance-Spacer rechts.
            // Ersetzt AppSheetHeader (war Sheet-Stil mit „Zurück"-Text).
            // @Environment(\.dismiss) poppt den NavStack korrekt.
            // .padding(.top, headerChevronTopPadding=0) → Chevron sitzt
            // auf systemweit identischer y-Position (analog TrainingView,
            // ListsView und allen anderen Push-Screens).
            HStack {
                AppBackButton(action: { dismiss() }, tint: AppTheme.Colors.elumiPink)
                Spacer(minLength: 0)
                Text("Ausgewählte Listen")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer(minLength: 0)
                // Balance-Spacer: gleiche Breite wie AppBackButton-Frame
                // (64 pt), damit der Titel exakt mittig sitzt.
                Color.clear.frame(width: 64, height: 64)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.headerChevronTopPadding)
            .background(AppTheme.Colors.surface)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppTheme.Colors.textSecondary.opacity(0.18))
                    .frame(height: 0.5)
            }

            // Kategorie-Cards — Spacing 10 identisch zu
            // `categoryCardsSection` in ListsView.
            VStack(spacing: 10) {
                ListCategoryRow(
                    title: "Meine Listen",
                    iconAsset: "ListIconEigene",
                    count: lists(in: .own).count,
                    accent: accent
                ) { activeCategory = .own }

                ListCategoryRow(
                    title: "Nach Niveau",
                    iconAsset: "ListIconNiveau",
                    count: lists(in: .level).count,
                    accent: accent
                ) { activeCategory = .level }

                ListCategoryRow(
                    title: "Nach Themen",
                    iconAsset: "ListIconThemen",
                    count: lists(in: .topic).count,
                    accent: accent
                ) { activeCategory = .topic }

                if includeWoerterbuch {
                    ListCategoryRow(
                        title: "Wörterbuch",
                        iconAsset: "IconWoerterbuch",
                        count: lists(in: .woerterbuch).count,
                        accent: accent
                    ) {
                        // W2: Direct-Select wenn Caller-Closure gesetzt,
                        // sonst normaler Sheet-Fallback (W1).
                        if let directSelect = onWoerterbuchDirectSelect {
                            directSelect()
                            dismiss()
                        } else {
                            activeCategory = .woerterbuch
                        }
                    }
                }
            }
            .padding()

            Spacer(minLength: 0)
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .sheet(item: $activeCategory) { category in
            GlobalListPickerSheet(
                allLists: availableLists,
                initialSelection: selectedIDs,
                onCommit: { newSelection in
                    // Volle Gesamt-Selektion (cross-category) zurückspielen.
                    onCommit(newSelection)
                    activeCategory = nil
                },
                singleSelect: singleSelect,
                filter: predicate(for: category),
                categoryHeaders: false,
                feedbackPlayer: feedbackPlayer,
                onHome: onHome,
                onSettings: onSettings,
                accent: accent
            )
        }
        // **Push-Footer (2026-05-22)** — AppBottomBar via .appLocalChrome,
        // analog zu ListsView+Layout:70 und TrainingView+Layout:2227.
        // enabled: !usesGlobalChrome → true auf jedem gepushten Screen
        // (Home-Ebene hat usesGlobalChrome=true, pushed Screens false).
        // topBar-Closure: von .appLocalChrome nicht aufgerufen (vestigialer
        // Param), Dummy-Wert für Typ-Konsistenz mit anderen Call-Sites.
        // feedbackPlayer guard: FeedbackPlayer ist optional im Picker;
        // bei nil kein BottomBar-Render (kein Push-Einsatz ohne fp).
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: { dismiss() })
        } bottomBar: {
            if let fp = feedbackPlayer {
                AppBottomBar(
                    feedbackPlayer: fp,
                    onHome: { onHome?() },
                    onFavorite: nil,
                    onScan: nil,
                    onSettings: onSettings
                )
            }
        }
    }

    // MARK: - Kategorie-Klassifikation

    /// Built-in-Listen werden nicht per gespeichertem Flag in Niveau/Themen
    /// getrennt — die Aufteilung kommt aus `StandardVocabularyLoader`. Wir
    /// bauen die ID-Sets einmalig und prüfen Mitgliedschaft.
    private var levelIDs: Set<UUID> {
        Set(StandardVocabularyLoader.levelLists.map(\.id))
    }
    private var topicIDs: Set<UUID> {
        Set(StandardVocabularyLoader.topicLists.map(\.id))
    }
    private var woerterbuchID: UUID {
        StandardVocabularyLoader.allInOneList.id
    }

    private func lists(in category: Category) -> [VocabularyList] {
        availableLists.filter(predicate(for: category))
    }

    /// Prädikat passend zum `filter`-Param von `GlobalListPickerSheet`, damit
    /// Card-Count und Sheet-Inhalt garantiert deckungsgleich sind.
    private func predicate(for category: Category) -> (VocabularyList) -> Bool {
        switch category {
        case .own:
            return { !$0.isBuiltIn }
        case .level:
            let ids = levelIDs
            return { ids.contains($0.id) }
        case .topic:
            let ids = topicIDs
            return { ids.contains($0.id) }
        case .woerterbuch:
            let wid = woerterbuchID
            return { $0.id == wid }
        }
    }
}
