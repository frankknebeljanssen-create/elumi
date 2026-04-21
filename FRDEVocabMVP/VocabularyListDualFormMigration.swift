import Foundation

/// One-shot Migration: splittet vorhandene Dual-Form-Einträge in
/// Custom-Listen in zwei separate Vokabeln.
///
/// Kontext (User-Report): vor Einführung des `ScanAIPostProcessor`
/// wurden Einträge wie „l'ami/l'amie" / „der Freund/die Freundin" oder
/// „le copain/la copine" / „der Kumpel/die Kumpelin" als **ein**
/// Datensatz gespeichert. Der User möchte sie als zwei einzeln
/// lernbare Vokabeln haben. Neue Scans werden vom Post-Processor
/// bereits korrekt gesplittet; diese Migration kümmert sich **um den
/// Bestand**.
///
/// Safety:
///   • Läuft genau einmal (UserDefaults-Flag mit Versionierung)
///   • Nur Custom-Listen — Standard-Pakete bleiben unverändert
///   • Split nur, wenn `/` in **beiden** (French UND German) vorkommt
///     und beide Seiten je 2 nicht-leere Teile liefern. Sonst würde
///     die Zuordnung zu Fehlpaarungen führen
///   • Keine Datei-Schreiboperation innerhalb dieses Moduls —
///     Caller muss selber `saveCustomLists()` triggern (passiert
///     automatisch via `customLists`-didSet im Store)
enum VocabularyListDualFormMigration {

    /// UserDefaults-Key. Versioniert, damit eine zukünftige erweiterte
    /// Regel unter `v2` / `v3` laufen kann, ohne die alte Migration
    /// nochmal zu triggern.
    static let migrationKey = "FRDEVocabMVP.migration.dualFormSplit.v1"

    /// Führt die Migration genau einmal aus. Gibt zurück, ob Listen
    /// tatsächlich verändert wurden — Caller kann dann z. B. einen
    /// Save erzwingen.
    @discardableResult
    static func applyIfNeeded(
        to lists: inout [VocabularyList],
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        if userDefaults.bool(forKey: migrationKey) { return false }
        var anyChange = false

        for index in lists.indices {
            let original = lists[index]
            // Standard-Pakete nicht anfassen (isBuiltIn).
            guard !original.isBuiltIn else { continue }

            // 1. Split-Pass: slash/comma-Einträge in N separate Items.
            let splitItems = original.items.flatMap { splitItemIfDualForm($0) }
            // 2. Merge-Pass: fragmentierte Einträge (z. B. „le" + „ami")
            //    zu „l'ami" zusammenziehen. Conservative — nur bei
            //    hoher Confidence (≥ 0.85) automatisch.
            let mergedItems = VocabDualFormMerger.mergeFragments(splitItems)

            if mergedItems.count != original.items.count {
                // Mindestens ein Item wurde verändert (Split-Add oder Merge-Remove).
                lists[index] = VocabularyList(
                    id: original.id,
                    name: original.name,
                    items: mergedItems,
                    isBuiltIn: original.isBuiltIn
                )
                anyChange = true
                #if DEBUG
                let delta = mergedItems.count - original.items.count
                print("📋 [DualForm-Migration] Liste \"\(original.name)\": \(delta >= 0 ? "+" : "")\(delta) Eintrag(e) nach Split+Merge.")
                #endif
            }
        }

        userDefaults.set(true, forKey: migrationKey)
        #if DEBUG
        print("📋 [DualForm-Migration] abgeschlossen. Änderungen: \(anyChange)")
        #endif
        return anyChange
    }

    // MARK: - Split-Logik

    /// Splittet ein `VocabularyItem`, wenn der shared
    /// `VocabDualFormSplitter` es mit ausreichender Confidence
    /// beurteilt. Sonst: Array mit dem unveränderten Item.
    ///
    /// Delegation an `VocabDualFormSplitter.attemptSplit` — dieselbe
    /// Logik gilt damit auch für Scan-Pipeline und Imports.
    static func splitItemIfDualForm(_ item: VocabularyItem) -> [VocabularyItem] {
        let decision = VocabDualFormSplitter.attemptSplit(source: item.french, target: item.german)
        guard let parts = decision.parts else {
            #if DEBUG
            if decision.confidence < VocabDualFormSplitter.autoApplyThreshold,
               decision.confidence > 0.0,
               (item.french.contains("/") || item.french.contains(",")) {
                print("📋 [DualForm] Eintrag NICHT gesplittet (\"\(item.french)\"): \(decision.rationale)")
            }
            #endif
            return [item]
        }
        return parts.map { part in
            VocabularyItem(
                rawFrench: part.source,
                rawGerman: part.target,
                cardType: item.cardType,
                level: item.level,
                sourceLanguage: item.sourceLanguage,
                wordClass: item.wordClass
            )
        }
    }
}
