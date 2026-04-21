import Foundation
import SQLite3

/// Loads all vocabulary from FRDEMasterLexicon.sqlite (unified source).
/// Single source of truth for all vocabulary in the app.
enum StandardVocabularyLoader {
    struct Entry {
        let sourceDisplay: String
        let target: String
        let cardType: CardType
        let level: String          // A1, A2, B1, B2, C1, C2
        let wordClass: String      // noun, verb, adjective, adverb, etc.
        let gender: String         // m, f, or empty
        let topic: String          // Essen & Trinken, Familie & Freunde, etc.
        let frequency: Double
    }

    static let allEntries: [Entry] = loadEntries()

    /// Vorgefilterter Pool für Distraktoren im Verb-Training (Verb-MC).
    /// `prepareVerbMCOptions` wird bei jedem Karten-Wechsel aufgerufen —
    /// ohne diesen Cache läuft der `wordClass == "verb"`-Filter bei einer
    /// 3000-Eintrag-Master-Liste pro Karte einmal über alle Einträge.
    /// Statischer `let` bedeutet: genau **einmal** pro App-Start berechnet.
    static let verbEntries: [Entry] = allEntries.filter {
        $0.wordClass == "verb" && !$0.target.isEmpty && !$0.sourceDisplay.isEmpty
    }

    /// Analog zu `verbEntries` — für den Nomen-MC-Distraktor-Pool.
    /// `prepareNounMCOptions` nutzt denselben O(1)-Zugriff.
    static let nounEntries: [Entry] = allEntries.filter {
        $0.wordClass == "noun" && !$0.target.isEmpty && !$0.sourceDisplay.isEmpty
    }

    /// Lookup-Tabelle Französisch-Lemma → Genus (Roh-String aus DB: „m",
    /// „f", gelegentlich auch leere Einträge = keine Aussage). Wird vom
    /// `ArticleModeClassifier` als schnellster Weg genutzt, um für einen
    /// Lernkern das Genus zu bestimmen, **bevor** die teureren
    /// Supplemental-Lexikon-Lookups angestoßen werden.
    ///
    /// Wir pflegen zwei Keys pro Eintrag: die Rohform (z. B. „la maison")
    /// UND die Artikel-gestrippte Form („maison"). Damit trifft der
    /// Lookup egal ob der Lernkern schon sauber extrahiert ist oder
    /// ausnahmsweise mit führendem Artikel reinkommt.
    static let frenchGenderMap: [String: String] = {
        var map: [String: String] = [:]
        for entry in allEntries where entry.wordClass == "noun" && !entry.gender.isEmpty {
            let key = entry.sourceDisplay.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            map[key] = entry.gender
            // `strippingLeadingFrenchArticle` ist die appweite Artikel-Strip-
            // Funktion (siehe `LexiconGenderUtilities+Articles.swift`) — sie
            // kennt auch die langen Formen („de la", „à l'"). Für den
            // Classifier reicht die Standardform; die Variante hier
            // indiziert zusätzlich die Artikel-gestrippte Version.
            let stripped = strippingLeadingFrenchArticle(from: key)
            if stripped != key, !stripped.isEmpty {
                map[stripped] = entry.gender
            }
        }
        return map
    }()

    /// Convenience-Accessor mit case-insensitiver Normalisierung. `nil`
    /// wenn kein Genus bekannt.
    nonisolated static func frenchGender(for lemma: String) -> String? {
        let key = lemma.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return frenchGenderMap[key]
    }

    static let vocabularyItems: [VocabularyItem] = {
        var seen = Set<String>()
        return allEntries.compactMap { entry -> VocabularyItem? in
            // Use cardType from DB (is_phrase), not word-count heuristic
            let cardType = entry.cardType
            let key = [
                entry.sourceDisplay.lowercased()
                    .folding(options: .diacriticInsensitive, locale: .current),
                entry.target.lowercased()
                    .folding(options: .diacriticInsensitive, locale: .current),
                cardType.rawValue
            ].joined(separator: "|")
            guard seen.insert(key).inserted else { return nil }

            return VocabularyItem(
                rawFrench: entry.sourceDisplay,
                rawGerman: entry.target,
                cardType: cardType,
                level: vocabularyLevel(for: entry.level),
                sourceLanguage: .french,
                wordClass: entry.wordClass.isEmpty ? nil : entry.wordClass
            )
        }
    }()

    static func items(for level: String) -> [VocabularyItem] {
        vocabularyItems.enumerated().compactMap { index, item in
            allEntries[index].level == level ? item : nil
        }
    }

    static func items(forLevels levels: Set<String>) -> [VocabularyItem] {
        vocabularyItems.enumerated().compactMap { index, item in
            levels.contains(allEntries[index].level) ? item : nil
        }
    }

    static func items(forWordClass wordClass: String) -> [VocabularyItem] {
        vocabularyItems.enumerated().compactMap { index, item in
            allEntries[index].wordClass == wordClass ? item : nil
        }
    }

    static func items(forTopic topic: String) -> [VocabularyItem] {
        vocabularyItems.enumerated().compactMap { index, item in
            allEntries[index].topic == topic ? item : nil
        }
    }

    static var allTopics: [String] {
        let topics = Set(allEntries.map(\.topic))
        return topics.sorted().filter { $0 != "Allgemein" } + ["Allgemein"]
    }

    static var allLevels: [String] {
        ["A1", "A2", "B1", "B2", "C1", "C2"]
    }

    /// Fast lookup set of French verb forms (lowercase)
    static let verbSet: Set<String> = {
        Set(allEntries.filter { $0.wordClass == "verb" }.map { $0.sourceDisplay.lowercased() })
    }()

    /// Fast lookup: is this French word a verb? (includes conjugated forms)
    /// Respektiert `wordClassOverrides` — „voilà" zählt z.\u{00A0}B. NICHT als Verb.
    static func isVerb(_ frenchText: String) -> Bool {
        let key = frenchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let override = wordClassOverrides[key] { return override == "verb" }
        if verbSet.contains(key) { return true }
        if wordClassMap[key] == "verb" { return true }
        return inflectionWordClassMap[key] == "verb"
    }

    /// Fast lookup set of French nouns (lowercase, includes article-stripped + accent-stripped)
    static let nounSet: Set<String> = {
        var set = Set<String>()
        for entry in allEntries where entry.wordClass == "noun" {
            let lower = entry.sourceDisplay.lowercased()
            set.insert(lower)
            let stripped = strippedArticle(lower)
            if stripped != lower {
                set.insert(stripped)
                let accentStripped = stripDiacritics(stripped)
                if accentStripped != stripped { set.insert(accentStripped) }
            }
        }
        return set
    }()

    /// Fast lookup: is this French word a noun? (includes plural forms)
    static func isNoun(_ frenchText: String) -> Bool {
        let key = frenchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if nounSet.contains(key) { return true }
        if wordClassMap[key] == "noun" { return true }
        return inflectionWordClassMap[key] == "noun"
    }

    /// Strip diacritics: é→e, ç→c, etc.
    private static func stripDiacritics(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: .current)
    }

    /// Fast lookup: word class for a French term (lowercase key → word class)
    /// Includes full lemma, article-stripped, AND accent-stripped versions
    static let wordClassMap: [String: String] = {
        var map: [String: String] = [:]
        for entry in allEntries where !entry.wordClass.isEmpty {
            let key = entry.sourceDisplay.lowercased()
            map[key] = entry.wordClass
            // Article-stripped: "la maison" → "maison"
            let stripped = strippedArticle(key)
            if stripped != key {
                map[stripped] = entry.wordClass
                // Also accent-strip the article-stripped version: "garçon" → "garcon"
                let accentStripped = stripDiacritics(stripped)
                if accentStripped != stripped { map[accentStripped] = entry.wordClass }
            }
            // Accent-stripped full key: "le garçon" → "le garcon"
            let accentStripped = stripDiacritics(key)
            if accentStripped != key { map[accentStripped] = entry.wordClass }
        }
        return map
    }()

    /// Inflection form → word class map (lazy loaded from SQLite forms table)
    static let inflectionWordClassMap: [String: String] = {
        var map: [String: String] = [:]
        _ = SupplementalFreeDictLexicon.withReadOnlyDatabase { database -> Bool in
            let sql = """
                SELECT DISTINCT f.form, e.word_class
                FROM forms f
                JOIN entries e ON f.entry_id = e.entry_id
                WHERE f.form_type = 'inflection' AND e.word_class != ''
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let stmt = statement else { return false }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let form = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let wc = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                guard !form.isEmpty, !wc.isEmpty else { continue }
                let lower = form.lowercased()
                // Store bare form (no spaces = single word like "maisons", "sais")
                if !lower.contains(" ") {
                    map[lower] = wc
                } else {
                    // Multi-word: store last word (e.g. "je suis" → "suis")
                    if let lastWord = lower.split(separator: " ").last {
                        let lastStr = String(lastWord)
                        if map[lastStr] == nil { map[lastStr] = wc }
                    }
                }
            }
            return true
        }
        return map
    }()

    /// Inflection form → infinitive map (lazy loaded from SQLite)
    static let inflectionInfinitiveMap: [String: String] = {
        var map: [String: String] = [:]
        _ = SupplementalFreeDictLexicon.withReadOnlyDatabase { database -> Bool in
            let sql = """
                SELECT DISTINCT f.form, e.lemma_fr
                FROM forms f
                JOIN entries e ON f.entry_id = e.entry_id
                WHERE f.form_type = 'inflection' AND e.word_class = 'verb'
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let stmt = statement else { return false }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let form = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let lemma = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                guard !form.isEmpty, !lemma.isEmpty else { continue }
                let lower = form.lowercased()
                if !lower.contains(" ") {
                    // bare form: "sais" → "savoir"
                    map[lower] = lemma
                } else {
                    // "je sais" → last word "sais" → "savoir"
                    if let lastWord = lower.split(separator: " ").last {
                        let key = String(lastWord)
                        if map[key] == nil { map[key] = lemma }
                    }
                }
            }
            return true
        }
        return map
    }()

    /// Look up the infinitive for a conjugated verb form (e.g. "sais" → "savoir")
    static func infinitive(for conjugatedForm: String) -> String? {
        let key = conjugatedForm.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        return inflectionInfinitiveMap[key]
    }

    /// Flexion → Lemma (alle Wortarten). „maisons" → „maison", „heureuse" → „heureux", „petites" → „petit".
    /// Artikel-Präfixe (la/le/les/l') werden aus dem Lemma entfernt.
    static let inflectionLemmaMap: [String: String] = {
        var map: [String: String] = [:]
        _ = SupplementalFreeDictLexicon.withReadOnlyDatabase { database -> Bool in
            let sql = """
                SELECT DISTINCT f.form, e.lemma_fr, e.word_class
                FROM forms f
                JOIN entries e ON f.entry_id = e.entry_id
                WHERE f.form_type = 'inflection' AND e.word_class != 'phrase'
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let stmt = statement else { return false }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                let form = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let lemma = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                guard !form.isEmpty, !lemma.isEmpty else { continue }
                let cleanedLemma = stripFrenchLemmaArticle(lemma)
                let lower = form.lowercased()
                if !lower.contains(" ") {
                    if map[lower] == nil { map[lower] = cleanedLemma }
                } else if let lastWord = lower.split(separator: " ").last {
                    let key = String(lastWord)
                    if map[key] == nil { map[key] = cleanedLemma }
                }
            }
            return true
        }
        return map
    }()

    /// Liefert das Lemma (Grundform) für eine beliebige Oberflächenform.
    /// Reihenfolge: Volltext-Lemma-Treffer → Flexion → nil.
    static func lemma(for text: String) -> String? {
        let key = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if wordClassMap[key] != nil { return stripFrenchLemmaArticle(key) }
        let strippedArticleKey = strippedArticle(key)
        if strippedArticleKey != key, wordClassMap[strippedArticleKey] != nil {
            return strippedArticleKey
        }
        if let inf = inflectionInfinitiveMap[key] { return inf }
        if let lem = inflectionLemmaMap[key]     { return lem }
        return nil
    }

    /// Direkter Zugriff auf die Flexions-Lemma-Map — **umgeht** den Vorrang,
    /// den `lemma(for:)` für Volltext-Einträge gibt. Wichtig für die Plural-
    /// Erkennung im Artikel-Modus: „amis" steht in `wordClassMap` ggf. als
    /// eigener Eintrag mit maskulinem Genus-Marker, in `inflectionLemmaMap`
    /// aber als Flexion von „ami". `lemma(for: "amis")` würde den Volltext-
    /// Pfad nehmen und `amis` zurückgeben — wir brauchen hier aber den
    /// Flexions-Hinweis auf „ami", um Plural zu erkennen.
    static func inflectionLemma(for text: String) -> String? {
        let key = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let inf = inflectionInfinitiveMap[key] { return inf }
        return inflectionLemmaMap[key]
    }

    /// Entfernt führende französische Artikel aus einem Lemma („la maison" → „maison").
    private static func stripFrenchLemmaArticle(_ text: String) -> String {
        let lower = text.lowercased()
        let prefixes = ["le ", "la ", "les ", "un ", "une ", "des ", "l'", "du ", "de la ", "de l'"]
        for prefix in prefixes where lower.hasPrefix(prefix) {
            return String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return lower
    }

    /// Verben, die beim Phrase-Split NICHT zur Verb-Einstufung führen (Hilfsverben).
    /// „c'est fini" enthält „est" (être) — reicht nicht als Verb-Lernziel.
    static let helperVerbInfinitives: Set<String> = [
        "\u{00EA}tre", "etre",   // être
        "avoir"
    ]

    /// Einheitliche Wortart-Auflösung — legacy-API, delegiert jetzt an die zentrale
    /// `FrenchEntryAnalyzer`. Pfad durch die EINE Analyse-Pipeline.
    ///
    /// Reihenfolge:
    ///  1) Vom Nutzer gesetzt (`item.wordClass`)
    ///  2) Analyzer-`primaryPos` (falls bestimmbar — noun/verb/adjective/adverb)
    ///  3) Erste erkannte Wortart aus `detectedPos`
    ///  4) DisplayType-Fallback (phrase/sentence)
    ///  5) Volltext-Lookup für Spezialfälle (pronoun, preposition, conjunction, interjection)
    static func resolvedWordClass(forItem item: VocabularyItem) -> String? {
        if let stored = item.wordClass, !stored.isEmpty {
            return stored
        }

        let result = FrenchListStatisticsAggregator.cachedAnalyze(item.french)

        switch result.primaryPos {
        case .noun:      return "noun"
        case .verb:      return "verb"
        case .adjective: return "adjective"
        case .adverb:    return "adverb"
        case .phrase:
            if let first = result.detectedPos.first {
                return first.rawValue
            }
            // Fallback: direkte DB-Wortart für Funktionswörter/Pronomen etc.
            let cleaned = item.french.trimmingCharacters(
                in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
            )
            if let direct = wordClass(for: cleaned) { return direct }
            return "phrase"
        case .sentence:  return "phrase"
        case .unknown:
            let cleaned = item.french.trimmingCharacters(
                in: CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
            )
            return wordClass(for: cleaned)
        }
    }

    /// Zentrale Overrides für falsch oder irreführend klassifizierte DB-Einträge.
    /// Werden VOR der DB konsultiert — eine Stelle für alle App-weiten Korrekturen.
    /// Erweiterbar — Key ist das normalisierte (lowercase, trim) Französisch.
    /// Zentrale Overrides für Wortart-Fehler in der DB-Export.
    ///
    /// WICHTIG: Dies ist nur ein SICHERHEITSNETZ für Einzelfälle.
    /// Langfristig sollen solche Einträge im Master-Export (TSV) korrigiert werden.
    /// Strukturelle Fixes (z. B. Compound-Nomen) laufen im Python-Build-Script
    /// via `promote_compound_nouns(db)` — nicht hier.
    static let wordClassOverrides: [String: String] = [
        // Interjektionen, die in der DB teilweise als „verb" oder „phrase" klassifiziert werden.
        // Diese haben keine strukturelle Kennung — zentraler Override bleibt bis DB-Fix.
        "voil\u{00E0}":  "interjection",   // voilà
        "voila":         "interjection",
        "voici":         "interjection",
        "merci":         "interjection",
        "bonjour":       "interjection",
        "salut":         "interjection",
        "bonsoir":       "interjection",
        "au revoir":     "interjection",
        "bienvenue":     "interjection",
        "d'accord":      "interjection",
        "oui":           "interjection",
        "non":           "interjection",
        "s'il vous pla\u{00EE}t": "interjection",
        "s'il te pla\u{00EE}t":   "interjection",
        "comment":       "adverb"          // interrogatives Adverb, nicht Pronomen
    ]

    /// Lookup word class for a French term — returns "noun", "verb", etc. or nil.
    /// Overrides-Tabelle gewinnt vor der DB, damit „voilà" nicht als Verb durchgeht.
    static func wordClass(for frenchText: String) -> String? {
        let key = frenchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let override = wordClassOverrides[key] { return override }
        if let wc = wordClassMap[key] { return wc }
        let stripped = strippedArticle(key)
        if stripped != key, let wc = wordClassMap[stripped] { return wc }
        // Accent-insensitive fallback: "garcon" → "garçon"
        let accentStripped = stripDiacritics(key)
        if accentStripped != key, let wc = wordClassMap[accentStripped] { return wc }
        let accentStrippedArticle = stripDiacritics(stripped)
        if accentStrippedArticle != stripped, let wc = wordClassMap[accentStrippedArticle] { return wc }
        // Check inflection forms (conjugated verbs, plural nouns, etc.)
        if let wc = inflectionWordClassMap[key] { return wc }
        if stripped != key, let wc = inflectionWordClassMap[stripped] { return wc }
        if accentStripped != key, let wc = inflectionWordClassMap[accentStripped] { return wc }
        return nil
    }

    /// Fast lookup set of non-noun French words (verbs, adjectives, adverbs, etc.)
    static let nonNounSet: Set<String> = {
        Set(allEntries.filter { $0.wordClass != "noun" && !$0.wordClass.isEmpty }.map { $0.sourceDisplay.lowercased() })
    }()

    /// Fast lookup: is this French word explicitly NOT a noun (verb, adjective, adverb, etc.)?
    static func isNonNoun(_ frenchText: String) -> Bool {
        let lower = frenchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if nonNounSet.contains(lower) { return true }
        // Also check without article (in case "le super" was passed)
        let stripped = strippedArticle(lower)
        return stripped != lower && nonNounSet.contains(stripped)
    }

    private static func strippedArticle(_ text: String) -> String {
        for art in ["le ", "la ", "l'", "l\u{2019}", "les ", "un ", "une ", "des ", "du "] {
            if text.hasPrefix(art) { return String(text.dropFirst(art.count)).trimmingCharacters(in: .whitespaces) }
        }
        return text
    }

    // MARK: - Pre-built VocabularyLists for the list picker

    private static let levelNames: [String: String] = [
        "A1": "A1 Grundwortschatz",
        "A2": "A2 Aufbauwortschatz",
        "B1": "B1 Mittelstufe",
        "B2": "B2 Oberstufe",
        "C1": "C1 Fortgeschritten",
        "C2": "C2 Experte"
    ]

    static let allInOneList: VocabularyList = VocabularyList(
        id: UUID(uuidString: "F1E1EEE1-A000-4000-A000-000000000000")!,
        name: "Komplettes Wörterbuch",
        items: vocabularyItems,
        isBuiltIn: true,
        collectionPreset: .standardLevel,
        isAggregateVocabulary: true
    )

    static let levelLists: [VocabularyList] = {
        var lists: [VocabularyList] = []
        let levelUUIDs: [String: UUID] = [
            "A1": UUID(uuidString: "F1E1EEE1-A100-4000-A000-000000000001")!,
            "A2": UUID(uuidString: "F1E1EEE1-A200-4000-A000-000000000002")!,
            "B1": UUID(uuidString: "F1E1EEE1-B100-4000-A000-000000000003")!,
            "B2": UUID(uuidString: "F1E1EEE1-B200-4000-A000-000000000004")!,
            "C1": UUID(uuidString: "F1E1EEE1-C100-4000-A000-000000000005")!,
            "C2": UUID(uuidString: "F1E1EEE1-C200-4000-A000-000000000006")!,
        ]
        for level in ["A1", "A2", "B1", "B2", "C1", "C2"] {
            let levelItems = items(for: level)
            guard !levelItems.isEmpty else { continue }
            lists.append(VocabularyList(
                id: levelUUIDs[level]!,
                name: levelNames[level] ?? level,
                items: levelItems,
                isBuiltIn: true,
                collectionPreset: .standardLevel
            ))
        }
        return lists
    }()

    static let topicLists: [VocabularyList] = {
        let minItems = 20
        var lists: [VocabularyList] = []
        let sortedTopics = allTopics
        for (index, topic) in sortedTopics.enumerated() {
            let topicItems = items(forTopic: topic)
            guard topicItems.count >= minItems else { continue }
            let idString = String(format: "AAAA0000-0000-4000-A000-%012d", index + 1)
            lists.append(VocabularyList(
                id: UUID(uuidString: idString) ?? UUID(),
                name: topic,
                items: topicItems,
                isBuiltIn: true,
                collectionPreset: .standardTopic
            ))
        }
        return lists.sorted { $0.items.count > $1.items.count }
    }()

    // MARK: - Private

    private static func loadEntries() -> [Entry] {
        guard let result = SupplementalFreeDictLexicon.withReadOnlyDatabase({ database -> [Entry] in
            let sql = """
                SELECT lemma_fr, lemma_de, word_class, gender_fr, level, is_phrase, frequency_rank, topic
                FROM entries
                ORDER BY frequency_rank ASC
                """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let stmt = statement else {
                return []
            }
            defer { sqlite3_finalize(stmt) }

            var entries: [Entry] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let lemmaFr = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let lemmaDe = sqlite3_column_text(stmt, 1).map { String(cString: $0) } ?? ""
                guard !lemmaFr.isEmpty, !lemmaDe.isEmpty else { continue }

                let wordClass = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let genderFr = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""
                let level = sqlite3_column_text(stmt, 4).map { String(cString: $0) } ?? ""
                let isPhrase = sqlite3_column_int(stmt, 5)
                let freqRank = sqlite3_column_int(stmt, 6)
                let topic = sqlite3_column_text(stmt, 7).map { String(cString: $0) } ?? "Allgemein"

                entries.append(Entry(
                    sourceDisplay: lemmaFr,
                    target: lemmaDe,
                    cardType: isPhrase == 1 ? .phrases : .words,
                    level: level,
                    wordClass: wordClass,
                    gender: genderFr,
                    topic: topic,
                    frequency: Double(freqRank)
                ))
            }
            return entries
        }) else {
            print("⚠️ FRDEMasterLexicon.sqlite not found or failed to open")
            return []
        }

        print("📚 StandardVocabulary loaded from SQLite: \(result.count) entries")
        return result
    }

    private static func vocabularyLevel(for level: String) -> VocabularyLevel? {
        switch level {
        case "A1", "A2": return .beginner
        case "B1": return .intermediate
        case "B2", "C1", "C2": return .advanced
        default: return nil
        }
    }
}
