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

    /// Welche Kategorie ist gerade als Sheet offen.
    @State private var activeCategory: Category? = nil

    private enum Category: Int, Identifiable {
        case own, level, topic, woerterbuch
        var id: Int { rawValue }
    }

    var body: some View {
        // Spacing 10 — identisch zur `categoryCardsSection` in ListsView,
        // damit die Cards überall gleich „atmen".
        VStack(spacing: 10) {
            ListCategoryRow(
                title: "Eigene Listen",
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
                ) { activeCategory = .woerterbuch }
            }
        }
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
                onHome: onHome
            )
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
