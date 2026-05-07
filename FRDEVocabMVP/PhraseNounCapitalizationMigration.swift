import Foundation

/// One-shot Migration: kapitalisiert in Phrasen-Einträgen (`cardType ==
/// .phrases`) jedes deutsche Wort, das im Nomen-Lexikon vorkommt, aber
/// aus Datenqualitäts-Gründen kleingeschrieben wurde.
///
/// Hintergrund (User-Wunsch 2026-04-22): Der Master-Export sowie
/// ältere Scan-Ergebnisse haben in zusammengesetzten Phrasen die
/// Nomen teils klein gelassen — z. B. „mein bester freund" statt
/// „mein bester Freund". In Karteikarten sieht das unsauber aus und
/// mindert den didaktischen Nutzen (Groß-/Kleinschreibung als
/// deutsche Lernkomponente).
///
/// Algorithmus:
///   1. Nomen-Set aufbauen aus zwei Quellen:
///      a) Alle deutschen Übersetzungen aus `StandardVocabularyLoader
///         .nounEntries` (Master-Lexikon) — deckt den Standard-Wortschatz
///      b) Alle `german`-Werte von Items in `lists`, deren
///         `wordClass == "noun"` oder deren `cardType == .words` und
///         die als Nomen-Kandidat plausibel sind — deckt individuelle
///         User-Additions
///   2. Pro Phrasen-Item (`cardType == .phrases`) das `german`-Feld
///      in Wörter splitten (Whitespace-separiert)
///   3. Für jedes Wort: Interpunktion vorn/hinten abziehen, den Kern
///      lowercasen. Wenn der Kern im Nomen-Set liegt → Kern mit
///      Großbuchstaben-Anfang zurückschreiben, Interpunktion wieder
///      anflanschen
///   4. Neuen zusammengesetzten String zurück in `german` schreiben
///
/// Safety:
///   • Läuft genau einmal pro Installation — UserDefaults-Flag mit
///     Versionierung (`v1`), damit zukünftige erweiterte Regeln
///     unter `v2` etc. erneut greifen können
///   • Nur Custom-Listen — Standard-Pakete (isBuiltIn) bleiben
///     unverändert (die werden sowieso bei jedem Launch frisch aus
///     SQLite gezogen)
///   • Punktuations-robust: "(freund)" → "(Freund)", „freund." →
///     „Freund.", vermeidet den naiven `prefix(1).uppercased()`-Bug
///   • Keine Datei-Schreiboperation innerhalb dieses Moduls — Caller
///     muss selber `saveCustomLists()` triggern (passiert automatisch
///     via `customLists`-didSet im Store)
///
/// **Bekannte Einschränkung**: Wörter, die sowohl Nomen als auch
/// andere Wortarten sind (z. B. "arm" = adj vs. "Arm" = Körperteil),
/// werden aggressiv kapitalisiert, wenn irgendein Nomen-Eintrag die
/// Form führt. Für V1 ist das ok — False-Positives sind seltener als
/// False-Negatives, und der User kann bei Bedarf nachbessern.
enum PhraseNounCapitalizationMigration {

    /// UserDefaults-Key. **V2** (2026-04-25): erweiterte Migration,
    /// die zusätzlich zu `.phrases`-Items auch `.words`-Items mit
    /// `wordClass == "noun"` abdeckt (Einzelwort-Nomen). v1 → v2
    /// Bump triggert Re-Run auf bestehenden Installationen und
    /// korrigiert Altbestände, die der neuen Regel nicht entsprechen.
    /// Idempotent — bereits korrekte Einträge bleiben unverändert.
    static let migrationKey = "elumi.migrations.phraseNounCapitalization.v2"

    /// Führt die Migration genau einmal aus. Gibt zurück, ob Listen
    /// tatsächlich verändert wurden — Caller kann dann z. B. einen
    /// Save erzwingen.
    @discardableResult
    static func applyIfNeeded(
        to lists: inout [VocabularyList],
        userDefaults: UserDefaults = .standard
    ) -> Bool {
        if userDefaults.bool(forKey: migrationKey) { return false }

        let nounLookup = buildNounLookup(from: lists)
        var anyChange = false
        var changedItemCount = 0

        for listIndex in lists.indices {
            let original = lists[listIndex]
            // Standard-Pakete nicht anfassen.
            guard !original.isBuiltIn else { continue }

            var mutatedItems = original.items
            var listDidChange = false

            for itemIndex in mutatedItems.indices {
                let item = mutatedItems[itemIndex]
                let before = item.german
                let after: String

                // **V2 erweitert (2026-04-25)**: Drei Kategorien.
                //   1. `.phrases`: bestehende Whole-Phrase-Scan —
                //      Nomen im Set werden mid-sentence kapitalisiert.
                //   2. `.words` + wordClass=="noun": deutsches Ziel
                //      ist per Definition Nomen → erstes Nicht-Artikel-
                //      Wort großschreiben.
                //   3. `.words` OHNE korrektes wordClass-Tag:
                //      Safety-Net via `capitalizeKnownNouns`. Wenn das
                //      Wort in `germanNounSet` liegt (= Master-Lexikon-
                //      Nomen), wird kapitalisiert — fängt Alt-Einträge
                //      mit fehlendem/falschem POS-Tag.
                if item.cardType == .phrases {
                    after = capitalizeKnownNouns(in: before, knownNouns: nounLookup)
                } else if item.cardType == .words,
                          item.wordClass?.lowercased() == "noun" {
                    after = capitalizeFirstNounWord(in: before)
                } else if item.cardType == .words {
                    // Safety-Net: wordClass leer/falsch, aber im
                    // Master-Nomen-Set → auch kapitalisieren.
                    after = capitalizeKnownNouns(in: before, knownNouns: nounLookup)
                } else {
                    continue
                }

                if before != after {
                    mutatedItems[itemIndex].german = after
                    listDidChange = true
                    changedItemCount += 1
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
        appDebugLog("📋 [PhraseNoun-Migration] abgeschlossen. Items verändert: \(changedItemCount).")
        #endif
        return anyChange
    }

    // MARK: - Nomen-Lookup aufbauen

    /// Sammelt lowercased deutsche Nomen aus Master-Lexikon und User-
    /// Custom-Listen. Doppelte Einträge werden durch die Set-Semantik
    /// implizit deduped.
    private static func buildNounLookup(from lists: [VocabularyList]) -> Set<String> {
        var nouns: Set<String> = []

        // Master-Lexikon (aus SQLite — deckt ~3000 Standard-Nomen).
        for entry in StandardVocabularyLoader.nounEntries {
            let key = entry.target
                .lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            nouns.insert(key)
        }

        // Custom-Listen: jedes Nomen-Item, das der User selbst
        // angelegt/importiert hat. wordClass `"noun"` ist der
        // verlässliche Marker (vom Scanner/AI gesetzt); zusätzlich
        // nehmen wir `cardType == .words` in Kombination mit einem
        // kapitalisierten ersten Buchstaben mit (Nomen-Heuristik für
        // Alt-Einträge ohne wordClass-Tag).
        for list in lists {
            for item in list.items {
                let germanTrim = item.german.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !germanTrim.isEmpty else { continue }

                let isTaggedNoun = (item.wordClass?.lowercased() == "noun")
                let isHeuristicNoun = item.cardType == .words
                    && germanTrim.first?.isUppercase == true
                    && !germanTrim.contains(" ")

                guard isTaggedNoun || isHeuristicNoun else { continue }
                nouns.insert(germanTrim.lowercased())
            }
        }

        return nouns
    }

    // MARK: - Word-Level-Capitalization (punctuation-safe)

    /// Splittet `text` an Whitespace, behandelt pro Wort führende und
    /// trailing Interpunktion separat, und kapitalisiert den Kern,
    /// wenn er in `knownNouns` liegt.
    ///
    /// Beispiele:
    ///   • „freund" → „Freund"
    ///   • „(freund)" → „(Freund)"
    ///   • „freund." → „Freund."
    ///   • „mein bester freund." → „mein bester Freund."
    ///   • „Freund" (schon korrekt) → „Freund" (Roundtrip)
    static func capitalizeKnownNouns(in text: String, knownNouns: Set<String>) -> String {
        guard !text.isEmpty else { return text }
        // Wir splitten bewusst an Whitespace (nicht an Punctuation),
        // damit Tokens wie „freund-name" als eine Einheit behandelt
        // werden — die Hyphen-Variante ist oft keine eigenständiges
        // Nomen im Lookup, und wir wollen sie nicht zerschreddern.
        let tokens = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        let fixed = tokens.map { token -> String in
            capitalizeTokenIfNoun(token, knownNouns: knownNouns)
        }
        return fixed.joined(separator: " ")
    }

    // MARK: - V2: Einzelwort-Nomen-Kapitalisierung

    /// Delegation an die Single-Source-of-Truth-Utility
    /// `GermanNounCapitalization`. Bewusst als dünner Wrapper
    /// erhalten, damit Migrations-Call-Sites `capitalizeFirstNounWord`
    /// weiterhin unter dem bekannten Namen aufrufen können.
    static func capitalizeFirstNounWord(in target: String) -> String {
        GermanNounCapitalization.capitalizeFirstNounWord(in: target)
    }

    private static func capitalizeTokenIfNoun(_ token: String, knownNouns: Set<String>) -> String {
        // Leading/trailing Punctuation peelen — alles dazwischen ist
        // der „Kern", den wir für den Lookup und die Kapitalisierung
        // verwenden.
        var leading = ""
        var core = token
        var trailing = ""

        while let first = core.first, first.isPunctuation {
            leading.append(first)
            core.removeFirst()
        }
        while let last = core.last, last.isPunctuation {
            trailing = String(last) + trailing
            core.removeLast()
        }

        guard !core.isEmpty else { return token }

        let key = core.lowercased()
        guard knownNouns.contains(key) else { return token }

        // Kern kapitalisieren — erstes Zeichen des Kerns auf
        // Großbuchstabe, Rest unangetastet.
        let firstScalar = core.prefix(1).uppercased()
        let rest = core.dropFirst()
        return leading + firstScalar + rest + trailing
    }
}
