import Foundation

/// **Stufe 1 (2026-04-28)** — zentrale Auflösung der „effektiven"
/// Item-Liste für eine ausgewählte VocabularyList unter
/// Berücksichtigung optionaler hierarchischer Filter (Lernjahr-
/// Children mit cumulativeChildren).
///
/// Single Source of Truth: jeder Consumer ruft hier hinein, statt
/// `list.items` direkt zu lesen. Damit ist die Filter-Logik an EINER
/// Stelle und Erweiterungen (Confidence-Filter, Topic-Filter etc.)
/// kommen automatisch durch alle Consumer durch.
///
/// **Konsumenten** (alle Module, die der Lernjahr-Filter erreicht):
///   • Word Runner (`LiveListRunnerTaskProvider`)
///   • Training (`TrainingSessionController.activeItems`) — alle Modi
///   • Akzente (`AccentContentBuilder.gatherSeeds`)
///   • Flashcards (`FlashcardSessionStore.configureCustomDeck`,
///     plus Setup-Pfad via `FlashcardsSetupController.availableStackLists`)
///   • Personal-Deck (`PersonalDeck.buildCardOrderSnapshot` — Snapshot
///     bei Erstellung; spätere Filter-Änderungen wirken nicht mehr)
///   • Quiz (`QuizBuildService.makeMergedItems`, Cache-Key
///     berücksichtigt `lernjahrMax`)
///
/// Die Funktion ist `pure` — kein Side-Effect, kein Logging,
/// deterministisch. Persistente State-Variablen (UserDefaults-Lookup)
/// macht der Caller, nicht der Resolver.
enum VocabularyListSelectionResolver {

    /// Liefert die effektive Item-Liste für eine ausgewählte Liste.
    ///
    /// Verhalten:
    ///   • Liste ohne `children` ODER ohne `cumulativeChildren=true`
    ///     → returns `list.items` unverändert.
    ///   • Liste mit cumulative-Children UND `lernjahrMax == nil`
    ///     → returns `list.items` (Parent voll = alle Lernjahre).
    ///   • Liste mit cumulative-Children UND `lernjahrMax = n` (1..5)
    ///     → returns `children.prefix(n).flatMap(\.items)`.
    ///
    /// Die letzte Variante slicet die Children-Items bis Index n
    /// (1-basiert; prefix(n) nimmt die ersten n Children = Y_1…Y_n).
    static func effectiveItems(
        for list: VocabularyList,
        lernjahrMax: Int?
    ) -> [VocabularyItem] {
        guard let children = list.children,
              list.cumulativeChildren,
              let max = lernjahrMax,
              max >= 1
        else {
            // Fallback: Parent-Items (alle Lernjahre, oder klassische
            // flache Liste ohne Hierarchie).
            return list.items
        }
        // Cumulative-Slice: Y_1...Y_max. Cap auf children.count, damit
        // ein out-of-range max-Wert (z. B. 99 aus alten UserDefaults)
        // nicht crasht.
        let cap = Swift.min(max, children.count)
        return children.prefix(cap).flatMap(\.items)
    }

    /// **Single-Source-of-Truth** für den aktuellen Lernjahr-Max-Wert.
    /// Alle Consumer (Word Runner / Quiz / Flashcards / Training) lesen
    /// hier statt direkt aus `UserDefaults.standard` — damit der
    /// AppStorage-Key an EINER Stelle gekapselt ist.
    ///
    /// Returns: nil wenn der User noch nie gewählt hat (= „alle
    /// Lernjahre"), sonst 1...5.
    static func currentLernjahrMax() -> Int? {
        UserDefaults.standard.object(forKey: appLernjahrMaxKey) as? Int
    }

    // MARK: - Globale Listen-Auswahl (Stufe 5, 2026-04-29)

    /// **Single-Source-of-Truth** für den globalen Listen-Auswahl-Toggle
    /// (Spec 5.2). Default `true`, wenn der User noch nie umgeschaltet
    /// hat — neue Accounts und First-Launch starten mit globalem Modus.
    static func currentUseGlobalListSelection() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: appUseGlobalListSelectionKey) == nil {
            return true
        }
        return defaults.bool(forKey: appUseGlobalListSelectionKey)
    }

    /// Liest die globale Listen-Auswahl (UUID-Set). Returnt `nil`, wenn
    /// noch nie eine globale Auswahl gespeichert wurde — dann sollte
    /// der Caller den Default-Init-Pfad triggern (UUID der „A1
    /// Grundwortschatz"-Liste, Spec 5).
    ///
    /// **Hinweis:** der Caller darf den Toggle-Status NICHT in dieser
    /// Funktion entscheiden. Diese Funktion liefert nur die persistierten
    /// IDs. Toggle-Check geht über `currentUseGlobalListSelection()`.
    static func currentGlobalSelectedListIDs() -> Set<UUID>? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: appGlobalSelectedListIDsKey),
              let raw = try? JSONDecoder().decode([String].self, from: data) else {
            return nil
        }
        let ids = raw.compactMap(UUID.init(uuidString:))
        return ids.isEmpty ? nil : Set(ids)
    }

    /// Schreibt die globale Listen-Auswahl. Wird vom Settings-Toggle-
    /// Initial-Default (Stufe 1) und ab Stufe 2 von den Modul-Picker-
    /// Update-Pfaden aufgerufen.
    static func setGlobalSelectedListIDs(_ ids: Set<UUID>) {
        let raw = ids.map { $0.uuidString }
        let data = (try? JSONEncoder().encode(raw)) ?? Data()
        UserDefaults.standard.set(data, forKey: appGlobalSelectedListIDsKey)
        #if DEBUG
        let preview = raw.prefix(3).joined(separator: ", ")
        let suffix = raw.count > 3 ? ", …" : ""
        print("📋 [GlobalListSelection] setGlobalSelectedListIDs count=\(ids.count) → \(preview)\(suffix)")
        #endif
    }

    /// **UUID der „A1 Grundwortschatz"-Liste** — Single-Source für den
    /// Default-Initial-Wert der globalen Listen-Auswahl. Entspricht der
    /// stable UUID, mit der `StandardVocabularyLoader.levelLists` die
    /// A1-Parent-Liste anlegt (`"F1E1EEE1-A100-4000-A000-000000000001"`).
    /// Falls die UUID dort jemals geändert wird, MUSS dieser Helper
    /// nachgezogen werden — sonst zeigt der Initial-Default ins Leere.
    static let defaultGlobalSelectionListID: UUID =
        UUID(uuidString: "F1E1EEE1-A100-4000-A000-000000000001")!

    // MARK: - Effective-Selection-Helper (Stufe 5 Schritt 2, 2026-04-30)

    /// **Master-Read-Helper** für Quiz/Flashcards/Training/Word Runner.
    /// Routet zwischen globaler und Per-Modul-Auswahl auf Basis des
    /// Toggle-States in `appUseGlobalListSelectionKey`.
    ///
    ///   • Toggle ON → globale Auswahl (oder Default `Grundwortschatz A1`,
    ///     falls nichts persistiert war). Caller bekommt das gemeinsame
    ///     Set, das auch alle anderen Module sehen.
    ///   • Toggle OFF → Caller-spezifischer Fallback wird ausgeführt
    ///     (Per-Modul-UserDefaults-Key, mit historischem Migrations-Pfad
    ///     im Modul-Code).
    ///
    /// Closure-basierter Fallback: das Modul kapselt seine eigene
    /// Lese-Logik (z. B. JSON-Decoding aus seinem Per-Modul-Key oder
    /// Mode-spezifische Keys bei Training). Der Resolver kennt diese
    /// Details bewusst nicht.
    static func effectiveSelectedListIDs(
        perModuleFallback: () -> Set<UUID>
    ) -> Set<UUID> {
        if currentUseGlobalListSelection() {
            return currentGlobalSelectedListIDs() ?? [defaultGlobalSelectionListID]
        }
        return perModuleFallback()
    }

    /// **Master-Write-Helper** für Quiz/Flashcards/Training/Word Runner.
    /// Schreibt entweder in die globale Auswahl (Toggle ON) oder ruft
    /// den Per-Modul-Persist-Closure (Toggle OFF). Damit muss der Caller
    /// nur EINE Funktion aufrufen, wenn der User im Picker eine neue
    /// Auswahl trifft — die Routing-Entscheidung sitzt zentral.
    static func persistSelectedListIDs(
        _ ids: Set<UUID>,
        perModulePersist: (Set<UUID>) -> Void
    ) {
        if currentUseGlobalListSelection() {
            setGlobalSelectedListIDs(ids)
            return
        }
        perModulePersist(ids)
    }
}
