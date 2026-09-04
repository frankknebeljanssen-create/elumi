// ListMergeFlow.swift
// **List-Merge Phase 1 (2026-05-21)** — Coordinator für das
// Zusammenführen mehrerer Listen in EINE neue Custom-Liste. Spiegelt
// das Phase-E-Pattern (`MultiDraftMergeCoordinator`): `listStore` wird
// den Methoden als PARAM übergeben (kein Capture → parameterloser init,
// sauberer `@StateObject`-Lifecycle), Reentrance-Guard gegen Doppel-
// Callback, und Intra-Batch-Exact-Dedup über
// `VocabularyMergeNormalization.key` (FR+DE+CardType).
//
// Konflikt-Policy Phase 1: gleicher FR / anderes DE → BEIDE behalten
// (unterschiedliches DE ⇒ unterschiedlicher Key ⇒ kein Dedup). Ein
// Konflikt-Review-Sheet kommt erst in Phase 2.
//
// **Phase B Bug-Fix (2026-05-21):** Items werden FRISCH konstruiert
// (neue id via UUID()), NICHT als Struct kopiert. Die alte Struct-Kopie
// (`flatMap { $0.items }`) übernahm die Original-IDs → Duplikat-IDs über
// Listen hinweg → mitursächlich für den Daten-Verlust. Alle Daten-Felder
// werden vollständig übernommen (nur die id ist neu).

import Foundation

@MainActor
final class ListMergeCoordinator: ObservableObject {
    @Published var showListPicker: Bool = false
    @Published var showNameSheet: Bool = false
    @Published var pendingSourceIDs: Set<UUID> = []

    /// Reentrance-Guard — verhindert Doppel-Ausführung (z.B. doppelter
    /// Sheet-Callback, wie in Phase D v2 beobachtet).
    private var isPerformingMerge = false

    /// Sammelt die Items aller Quell-Listen, dedupt intra-batch und legt
    /// eine neue Custom-Liste mit dem Ergebnis an. Returns die Anzahl der
    /// importierten Vokabeln.
    @discardableResult
    func performMerge(
        sourceIDs: Set<UUID>,
        newName: String,
        listStore: VocabularyListStore
    ) async -> Int {
        guard !isPerformingMerge else { return 0 }
        isPerformingMerge = true
        defer { isPerformingMerge = false }

        // 1. Items aus allen Quell-Listen sammeln (custom + Standard via allLists).
        //    **Bug-Fix Phase B:** KEINE Struct-Kopie — jedes Item wird frisch
        //    konstruiert (neue id via UUID()), damit keine Duplikat-IDs über
        //    Listen entstehen. Alle Daten-Felder werden vollständig übernommen.
        let sourceLists = listStore.allLists.filter { sourceIDs.contains($0.id) }
        let freshItems = sourceLists.flatMap { $0.items }.map { item in
            VocabularyItem(
                french: item.french,
                german: item.german,
                sourcePhonetic: item.sourcePhonetic,
                targetPhonetic: item.targetPhonetic,
                cardType: item.cardType,
                level: item.level,
                sourceLanguage: item.sourceLanguage,
                wordClass: item.wordClass,
                variants: item.variants
            )
        }

        // 2. Intra-Batch-Exact-Dedup (gleicher Algorithmus wie
        //    MultiDraftMergeCoordinator). Konflikte (gleicher FR, anderes DE)
        //    bleiben automatisch beide erhalten, weil DE Teil des Keys ist.
        var seen = Set<String>()
        var dedupedItems: [VocabularyItem] = []
        for item in freshItems {
            let key = "\(VocabularyMergeNormalization.key(item.french))|\(VocabularyMergeNormalization.key(item.german))|\(item.cardType.rawValue)"
            if seen.insert(key).inserted {
                dedupedItems.append(item)
            }
        }

        // 3. Neue Custom-Liste anlegen + Items importieren.
        let newID = listStore.ensureCustomList(named: newName, collectionPreset: .other)
        let count = listStore.importItems(
            dedupedItems,
            preferredListID: newID,
            suggestedListName: newName,
            collectionPreset: .other
        )

        appDebugLog("📋 [ListMerge] \(sourceLists.count) Listen → \(freshItems.count) Items → \(dedupedItems.count) dedupt → \(count) importiert in \"\(newName)\"")
        return count
    }
}
