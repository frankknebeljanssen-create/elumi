// MultiDraftMergeFlow.swift
// **Meine Scans — Phase E (2026-05-20)** — Bulk-Merge mehrerer ScanDrafts in
// EINE Liste. Coordinator hält den Merge-STATE (@Published) über die Sheet-
// Kette hinweg; die Sheets selbst leben in `ScanImportView` (geringeres Sheet-
// Stacking-Risiko — Phase D v2 hat gezeigt wie empfindlich das ist).
//
// `listStore` wird NICHT im init gehalten, sondern den Methoden übergeben
// (Wiring-Entscheidung 2026-05-20: kein fragiler Custom-View-init nötig,
// `@StateObject` bleibt mit parameterlosem init → korrekte Lifecycle).
//
// Reentrance-Guards (pendingMergePlan-Pattern) + Intra-Batch-Exact-Dedup
// (computePlan dedupt nur incoming-vs-existing, NICHT incoming-vs-incoming).

import Foundation
import SwiftUI

@MainActor
final class MultiDraftMergeCoordinator: ObservableObject {
    @Published var aggregatedItems: [VocabularyItem] = []
    @Published var pendingMergePlan: MergePlan?
    @Published var pendingTargetListID: UUID?
    @Published var pendingTargetListName: String = ""
    @Published var sourceDraftCount: Int = 0

    func reset() {
        aggregatedItems = []
        pendingMergePlan = nil
        pendingTargetListID = nil
        pendingTargetListName = ""
        sourceDraftCount = 0
    }

    /// Aggregiert importable Pairs aus mehreren Drafts und entfernt
    /// intra-batch Exact-Duplikate (normalisiert `french|german|cardType`).
    /// Stilles Dedup — kein User-Feedback (Entscheidung 2026-05-20).
    func aggregateAndDedupe(drafts: [ScanDraft]) -> [VocabularyItem] {
        let pairs = drafts.flatMap { $0.previewPairs.filter(\.isImportable) }
        let items = pairs.map { pair in
            VocabularyItem(
                french: pair.french,
                german: pair.german,
                cardType: pair.cardType,
                sourceLanguage: .french,
                wordClass: pair.wordClass
            )
        }

        var seen = Set<String>()
        var deduped: [VocabularyItem] = []
        for item in items {
            let key = "\(VocabularyMergeNormalization.key(item.french))|\(VocabularyMergeNormalization.key(item.german))|\(item.cardType.rawValue)"
            if seen.insert(key).inserted {
                deduped.append(item)
            }
        }

        appDebugLog("📋 [MultiDraftMerge] aggregated \(items.count) → deduped \(deduped.count) from \(drafts.count) drafts")
        return deduped
    }

    /// Bereitet einen Merge in eine BESTEHENDE Liste vor. Reentrance-geschützt
    /// über `pendingMergePlan == nil`. Returns den Plan; der Caller entscheidet,
    /// ob ein ConflictReview gezeigt werden muss.
    func prepareMergeIntoExisting(
        listID: UUID,
        listName: String,
        listStore: VocabularyListStore?
    ) -> MergePlan? {
        guard pendingMergePlan == nil else {
            appDebugLog("⚠️ [MultiDraftMerge] prepareMergeIntoExisting called while merge pending — ignoring")
            return nil
        }
        guard let listStore else { return nil }
        guard let targetList = listStore.customLists.first(where: { $0.id == listID }) else {
            return nil
        }

        let plan = VocabularyListMergePlanner.computePlan(
            incoming: aggregatedItems,
            existingItems: targetList.items
        )

        pendingMergePlan = plan
        pendingTargetListID = listID
        pendingTargetListName = listName

        appDebugLog("📋 [MultiDraftMerge] computePlan: requiresUserDecision=\(plan.requiresUserDecision), safeAdds=\(plan.safeAdds.count), conflicts=\(plan.conflicts.count)")
        return plan
    }

    /// Conflict-Auflösung übernehmen (wie Phase D v2). Reentrance-geschützt.
    func applyResolvedConflicts(_ resolved: [ImportConflict]) {
        guard var plan = pendingMergePlan else {
            appDebugLog("⚠️ [MultiDraftMerge] applyResolvedConflicts called without pending plan — ignoring")
            return
        }
        plan.conflicts = resolved
        pendingMergePlan = plan
    }

    /// Apply in die bestehende Liste. Toast-Trigger macht der Caller.
    func executeMerge(
        listStore: VocabularyListStore?
    ) -> (success: Bool, addedCount: Int, errorMessage: String?) {
        guard let plan = pendingMergePlan, let listID = pendingTargetListID, let listStore else {
            return (false, 0, "Interner Fehler: Merge-Plan fehlt.")
        }

        let result = listStore.applyMergePlan(plan, toListWithID: listID)
        switch result.status {
        case .success:
            appDebugLog("📋 [MultiDraftMerge] merged into \"\(pendingTargetListName)\" — added=\(result.added)")
            return (true, result.added, nil)
        case .targetListMissing:
            return (false, 0, "Die Liste wurde inzwischen gelöscht.")
        case .persistenceMismatch:
            return (false, 0, "Speichern fehlgeschlagen. Bitte erneut versuchen.")
        }
    }

    /// Neue Liste anlegen + aggregierte Items importieren (blunter Append; die
    /// Intra-Batch-Dedup ist bereits in `aggregateAndDedupe` passiert).
    func executeImportToNewList(
        name: String,
        listStore: VocabularyListStore?
    ) -> (success: Bool, addedCount: Int) {
        guard let listStore else { return (false, 0) }
        let listID = listStore.ensureCustomList(named: name)
        let imported = listStore.importItems(
            aggregatedItems,
            preferredListID: listID,
            suggestedListName: name
        )
        appDebugLog("📋 [MultiDraftMerge] imported \(imported) items into new list \"\(name)\"")
        pendingTargetListID = listID
        pendingTargetListName = name
        return (true, imported)
    }
}
