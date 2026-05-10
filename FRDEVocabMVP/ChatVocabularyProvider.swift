// ChatVocabularyProvider.swift
// **Léa-Chat MVP Schritt 2B-1 (2026-05-10)** — liefert die aktiven
// Wortschatz-Wörter + ChatLevel für den Léa-System-Prompt. Wird vom
// `ChatService` bei jedem `sendMessage`-Call frisch ausgewertet,
// damit Listen-/Lernjahr-Wechsel live durchschlagen (Caching ist
// Edge-Function-side via Anthropic Prompt-Caching).
//
// **Architektur** (siehe Schritt 2B-1 Diagnose):
//   • Aktive Listen-IDs: `VocabularyListSelectionResolver
//     .currentGlobalSelectedListIDs()` — UserDefaults-backed Set<UUID>.
//     `nil` wenn User aktiv alle Listen deselected hat (oder noch nie
//     gewählt — Fresh-Install). Caller entscheidet, was passiert
//     (Léa-Spec: ChatView zeigt Modal).
//   • Lernjahr-Slider: `VocabularyListSelectionResolver
//     .currentLernjahrMax()` — UserDefaults-backed Int? (1-5 oder nil
//     = alle Lernjahre).
//   • Listen-Pool: `listStore.allLists` = customLists +
//     `StandardVocabularyLoader.levelLists` + `.topicLists`. Caller
//     muss den Store via Param mitliefern (kein Singleton).
//   • Item-Filter: `VocabularyListSelectionResolver.effectiveItems(
//     for:, lernjahrMax:)` macht das Cumulative-Slicing für
//     hierarchische Listen.
//
// **Niveau-Mapping** (Frank's Spec): LJ1=A1, LJ2=A2, LJ3+/nil=B1.
// Spezial: wenn User keine hierarchische Liste gewählt hat (z.B.
// nur Topic-Liste „Familie & Freunde"), fällt `lernjahrMax` ohnehin
// nicht ins Gewicht — wir mappen dann auf B1 als pragmatischen
// Default. B2-Auto-Mapping ist explizit nicht in 2B-1 — kommt
// später via Settings-Toggle wenn Frank das will.

import Foundation

/// Schnappschuss aller Wortschatz-Daten, die für eine Léa-Anfrage
/// gebraucht werden. Wird per `sendMessage` neu berechnet — keine
/// In-Memory-Caches im Provider.
struct ChatVocabularyContext: Equatable {
    /// Französische Wörter aus den aktiven Listen, dedupliziert
    /// (Case-insensitive auf der Roh-Form). Reihenfolge entspricht
    /// dem Listen-Iteration-Pfad — keine alphabetische Sortierung,
    /// damit die LJ1-Wörter zuerst erscheinen wenn die A1-Hierarchie
    /// aktiv ist.
    let words: [String]

    /// Niveau für die Léa-Sprachadaption. Aus dem `lernjahrMax` per
    /// `ChatLevel.fromLernjahrMax(_:)` abgeleitet, oder B1 als
    /// pragmatischer Default für Non-Hierarchie-Selections.
    let level: ChatLevel

    /// Display-Namen der aktiven Listen — für Debug-Logging und
    /// (später) UI-Anzeige im Listen-Wechsel-Modal.
    let listNames: [String]
}

enum ChatVocabularyProvider {
    /// Liest die aktive Selection aus dem Resolver, resolved sie
    /// gegen `listStore.allLists`, sammelt die effektiven Items
    /// (Lernjahr-gefiltert) und packt alles in einen
    /// `ChatVocabularyContext`. `nil`, wenn keine Liste aktiv ist
    /// — der Caller (ChatService) interpretiert das als
    /// „needsListSelection" und blockt den Send.
    @MainActor
    static func currentContext(from listStore: VocabularyListStore) -> ChatVocabularyContext? {
        guard let selectedIDs = VocabularyListSelectionResolver.currentGlobalSelectedListIDs(),
              !selectedIDs.isEmpty
        else {
            return nil
        }

        let lernjahrMax = VocabularyListSelectionResolver.currentLernjahrMax()
        let pool = listStore.allLists
        let activeLists = pool.filter { selectedIDs.contains($0.id) }
        guard !activeLists.isEmpty else {
            // IDs zeigen ins Leere (z.B. gelöschte Custom-Liste).
            // Defensive: behandeln wie „keine Auswahl".
            return nil
        }

        // Item-Aggregation mit Dedup (case-insensitive auf der
        // französischen Form). Reihenfolge bleibt iteration-stable.
        var aggregated: [String] = []
        var seen = Set<String>()
        for list in activeLists {
            let items = VocabularyListSelectionResolver.effectiveItems(
                for: list,
                lernjahrMax: lernjahrMax
            )
            for item in items {
                let raw = item.french.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !raw.isEmpty else { continue }
                let key = raw.lowercased()
                if seen.insert(key).inserted {
                    aggregated.append(raw)
                }
            }
        }

        // Niveau-Resolution: hierarchische Liste mit Lernjahr-Slider
        // → direktes Mapping. Sonst B1 als „User hat sich aktiv für
        // ein erweitertes Set entschieden"-Default (Frank's Spec
        // adressiert nur die Hierarchie, der Rest ist pragmatisch).
        let hasHierarchicalSelection = activeLists.contains {
            $0.cumulativeChildren && $0.children != nil
        }
        let level: ChatLevel = hasHierarchicalSelection
            ? .fromLernjahrMax(lernjahrMax)
            : .b1

        let names = activeLists.map(\.name)
        return ChatVocabularyContext(words: aggregated, level: level, listNames: names)
    }
}
