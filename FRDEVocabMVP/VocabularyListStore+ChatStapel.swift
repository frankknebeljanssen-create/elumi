// VocabularyListStore+ChatStapel.swift
// **Schritt 3A (2026-05-10)** — Auto-Sammlung „Aus Chat mit Léa".
//
// Léa-Korrekturen + neue Wörter werden am Ende einer Chat-Session
// als VocabularyItems in eine spezielle Custom-Liste gepackt. Diese
// Liste ist von normalen User-Custom-Listen über die stabile UUID
// `chatStapelListID` identifizierbar — sie taucht via `allLists` im
// GlobalListPickerSheet auf wie jede andere Custom-Liste, ist also
// vom Karteikarten-Drill ohne Special-Handling nutzbar.
//
// **Architektur-Wahl** (siehe Schritt-3A-Diagnose, Path A):
// Wir verwenden NICHT das `PersonalDeck`-System, weil:
//   • Persönliche Stapel sind hard-capped auf 2 (User-Slots) und
//     haben Snapshot-Semantik — eine kontinuierlich wachsende
//     Auto-Sammlung würde den Mastery-State bei jedem Re-Snapshot
//     zerstören.
//   • Eine Custom-Liste kann mit existing Mutations-API beliebig
//     wachsen, der Picker zeigt sie automatisch, der Drill kennt
//     keine Sonderfälle.
//
// Items werden **case-insensitive auf der `french`+`german`-Pair**
// dedupliziert — wenn der User denselben Fehler dreimal macht, ist
// die Karte trotzdem nur einmal im Stapel.

import Foundation

extension VocabularyListStore {
    /// Stabile UUID für die Auto-Sammlung. Wird beim ersten Add lazy
    /// erzeugt und danach via `customLists.first(where: { $0.id == ... })`
    /// gefunden. Pattern analog zu
    /// `VocabularyListSelectionResolver.defaultGlobalSelectionListID`.
    static let chatStapelListID: UUID =
        UUID(uuidString: "C4A700A1-1EA0-1EA0-1EA0-000000000001")!

    /// Display-Name. Wird an einer Stelle im Code gehalten, damit die
    /// UI-Strings (Setup-Picker + Summary-Sheet) garantiert synchron
    /// bleiben.
    static let chatStapelDisplayName = "Aus Chat mit Léa"

    /// Stellt sicher, dass der Chat-Stapel im Store existiert. Bei
    /// erstem Aufruf wird die Liste mit der stabilen UUID + leeren
    /// Items angelegt UND in die globale Listen-Selection
    /// aufgenommen, damit sie sofort im Karteikarten-Setup-Picker
    /// auftaucht. Idempotent — mehrfache Aufrufe sind ok.
    /// Returns die UUID, damit Caller sie für FlashcardLaunchContext
    /// `preferredListID` weiterreichen können.
    ///
    /// **Schritt 3A Smoke-Fix Bug C (2026-05-10)** — vorher hat die
    /// Liste in `customLists` gelebt, war aber nicht in der globalen
    /// Auswahl — Karteikarten-Setup zeigt nur aktive Listen, also
    /// blieb die „Aus Chat"-Liste unsichtbar bis der User sie
    /// manuell im Picker aktivierte. Jetzt: Auto-Add zu
    /// `setGlobalSelectedListIDs` beim ersten Create. Bei Re-Calls
    /// (Liste schon vorhanden) wird die globale Selection NICHT
    /// erneut angefasst — User-Manual-Deselection wird respektiert.
    @discardableResult
    func ensureChatStapelList() -> UUID {
        if customLists.contains(where: { $0.id == Self.chatStapelListID }) {
            return Self.chatStapelListID
        }
        let list = VocabularyList(
            id: Self.chatStapelListID,
            name: Self.chatStapelDisplayName,
            items: [],
            isBuiltIn: false,
            collectionPreset: .other
        )
        customLists.append(list)

        // Auto-Add zur globalen Listen-Auswahl. Idempotent: wenn die
        // ID schon drin ist (theoretisch unmöglich beim ersten
        // Create, aber defensiv geprüft), no-op.
        let currentIDs = VocabularyListSelectionResolver.currentGlobalSelectedListIDs() ?? []
        if !currentIDs.contains(Self.chatStapelListID) {
            var newIDs = currentIDs
            newIDs.insert(Self.chatStapelListID)
            VocabularyListSelectionResolver.setGlobalSelectedListIDs(newIDs)
        }

        return Self.chatStapelListID
    }

    /// Fügt eine VocabularyItem in den Chat-Stapel hinzu, mit
    /// case-insensitive Dedupe auf dem (french, german)-Pair.
    /// Gibt `true` zurück, wenn die Karte tatsächlich neu war und
    /// eingefügt wurde — `false` bei Dupe-Skip oder fehlendem Store-
    /// State (kann theoretisch passieren wenn ensure-Pfad fehlschlägt).
    ///
    /// **Schritt 3A Smoke-Fix Bug A (2026-05-10)** — `french` darf
    /// jetzt leer sein. Frank's Spec-Fallback bei Quote-Extraction-
    /// Failure: Karte mit `french=""` + `german=germanTip` landet
    /// trotzdem im Stapel, User editiert nach. Nur `german` ist
    /// noch Pflicht — eine Karte ohne deutsche Aufgabe wäre
    /// inhaltsleer.
    @discardableResult
    func addChatStapelItem(
        french: String,
        german: String,
        cardType: CardType
    ) -> Bool {
        let frenchTrim = french.trimmingCharacters(in: .whitespacesAndNewlines)
        let germanTrim = german.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !germanTrim.isEmpty else { return false }

        ensureChatStapelList()
        guard let index = customLists.firstIndex(where: { $0.id == Self.chatStapelListID }) else {
            return false
        }

        // Dedupe — case-insensitive Pair-Match. Bei leerem French
        // wird gegen den deutschen Tipp dedupliziert (verhindert
        // Spam von Fallback-Karten desselben Tipps).
        let frenchLower = frenchTrim.lowercased()
        let germanLower = germanTrim.lowercased()
        let exists = customLists[index].items.contains { existing in
            existing.french.lowercased() == frenchLower
                && existing.german.lowercased() == germanLower
        }
        guard !exists else { return false }

        // Raw-Init (`rawFrench:rawGerman:`), weil wir vorgeprozessierte
        // Strings haben (Léa hat sie bereits sauber strukturiert) —
        // der Display-Init würde unnötig nochmal Genus/Kapitalisierung
        // anwenden und u.U. den Tipp-Text verändern.
        let item = VocabularyItem(
            rawFrench: frenchTrim,
            rawGerman: germanTrim,
            cardType: cardType,
            sourceLanguage: .french
        )
        customLists[index].items.append(item)
        return true
    }
}
