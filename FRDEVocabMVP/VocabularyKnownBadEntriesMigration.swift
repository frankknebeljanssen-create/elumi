import Foundation

/// One-shot Migration: korrigiert bekannte Fehler-Einträge in Custom-
/// Listen. Jeder Korrektur-Eintrag ist ein Paar (falsch → richtig).
/// Der Matcher schaut auf **Französisch + Deutsch** zusammen, damit nur
/// der spezifische Fehleintrag geändert wird — nicht versehentlich ein
/// anderer Eintrag mit demselben Französisch-Begriff aber korrekter
/// Übersetzung.
///
/// Architektur:
///   • Zentrale Liste `corrections` als Swift-Literal — schnell
///     erweiterbar, klar nachvollziehbar
///   • Pro Correction entscheiden wir: replace (Text + wordClass +
///     cardType anpassen) oder delete (Item komplett entfernen)
///   • Gesamter Pass durch alle Custom-Listen (keine Built-In — die
///     kommen bei jedem Launch frisch aus SQLite)
///   • Idempotent: läuft nur einmal pro Installation + Versions-Key
///
/// Entstehung 2026-04-22 (Abend):
///   User meldet „dur" → „gekochtes Ei" als falschen Eintrag in
///   seiner Custom-Liste. DB ist korrekt (`l'œuf dur` → `das gekochte
///   Ei` als noun, separater Eintrag `dur` → `hart` als adjective).
///   Der Mischungs-Eintrag muss aus einer alten User-Session stammen
///   (wahrscheinlich Scan-Fehler). Diese Migration macht es sauber.
enum VocabularyKnownBadEntriesMigration {

    /// **Ein Korrektur-Eintrag** — beschreibt, was in Custom-Listen
    /// gesucht und wie damit umgegangen werden soll.
    struct Correction {
        /// Zu suchender Französisch-Wert (exakter Match, case-insensitive,
        /// whitespace-trim).
        let matchFrench: String
        /// Zu suchender Deutsch-Wert (exakter Match, case-insensitive,
        /// whitespace-trim).
        let matchGerman: String
        /// Aktion: `.replace` mit neuen Werten, `.delete` entfernt das Item.
        let action: Action

        enum Action {
            case delete
            case replace(french: String, german: String, wordClass: String?, cardType: CardType)
        }
    }

    /// UserDefaults-Key. Bewusst `v1` — zukünftige erweiterte Regel-
    /// Listen laufen unter `v2` erneut, ohne die alte Migration wieder
    /// anzuwerfen.
    static let migrationKey = "elumi.migrations.vocabularyKnownBadEntries.v1"

    /// **Zentrale Liste** aller bekannten Fehleinträge. Erweiterbar,
    /// wenn neue Fälle auftauchen.
    static let corrections: [Correction] = [
        // User-Report 2026-04-22: „dur" (adj, = „hart") wurde mit der
        // deutschen Übersetzung von „l'œuf dur" (= „das gekochte Ei")
        // verheiratet. Wir löschen den hybriden Eintrag und legen den
        // korrekten Phrase-Eintrag neu an.
        Correction(
            matchFrench: "dur",
            matchGerman: "gekochtes Ei",
            action: .replace(
                french: "l'œuf dur",
                german: "das gekochte Ei",
                // Nomen-Kompositum mit Adjektiv-Modifier — Wortart:
                // noun (das eigentliche Lern-Ziel ist das Nomen „œuf"
                // mit seinem Genus + Adjektiv-Angleichung).
                wordClass: "noun",
                cardType: .words
            )
        )
    ]

    /// Führt die Migration einmal aus. Gibt zurück, ob überhaupt eine
    /// Änderung passiert ist (für Logging).
    @discardableResult
    static func applyIfNeeded(
        to lists: inout [VocabularyList],
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        if userDefaults.bool(forKey: migrationKey) { return false }
        var anyChange = false
        var totalDeleted = 0
        var totalReplaced = 0

        for listIndex in lists.indices {
            let original = lists[listIndex]
            // Standard-Pakete nicht anfassen.
            guard !original.isBuiltIn else { continue }

            var mutatedItems = original.items
            var listDidChange = false

            // Rückwärts iterieren, damit wir beim `.delete` den Index
            // nicht invalidieren.
            for itemIndex in mutatedItems.indices.reversed() {
                let item = mutatedItems[itemIndex]
                guard let correction = matchingCorrection(for: item) else { continue }

                switch correction.action {
                case .delete:
                    mutatedItems.remove(at: itemIndex)
                    listDidChange = true
                    totalDeleted += 1
                    #if DEBUG
                    print("📋 [KnownBad] gelöscht: \"\(item.french)\" → \"\(item.german)\" aus Liste \"\(original.name)\"")
                    #endif

                case .replace(let french, let german, let wordClass, let cardType):
                    let replaced = VocabularyItem(
                        rawFrench: french,
                        rawGerman: german,
                        cardType: cardType,
                        level: item.level,
                        sourceLanguage: item.sourceLanguage,
                        wordClass: wordClass
                    )
                    mutatedItems[itemIndex] = replaced
                    listDidChange = true
                    totalReplaced += 1
                    #if DEBUG
                    print("📋 [KnownBad] ersetzt: \"\(item.french)\" → \"\(item.german)\"  =>  \"\(french)\" → \"\(german)\"")
                    #endif
                }
            }

            if listDidChange {
                lists[listIndex] = VocabularyList(
                    id: original.id,
                    name: original.name,
                    items: mutatedItems,
                    isBuiltIn: original.isBuiltIn,
                    collectionPreset: original.collectionPreset,
                    isAggregateVocabulary: original.isAggregateVocabulary
                )
                anyChange = true
            }
        }

        userDefaults.set(true, forKey: migrationKey)
        #if DEBUG
        print("📋 [KnownBad-Migration] abgeschlossen. ersetzt=\(totalReplaced), gelöscht=\(totalDeleted).")
        #endif
        return anyChange
    }

    // MARK: - Helpers

    private static func matchingCorrection(for item: VocabularyItem) -> Correction? {
        let fr = item.french.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let de = item.german.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return corrections.first { correction in
            correction.matchFrench.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == fr
                && correction.matchGerman.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) == de
        }
    }
}
