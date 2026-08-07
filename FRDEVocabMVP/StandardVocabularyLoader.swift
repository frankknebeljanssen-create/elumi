import Foundation
import SQLite3

/// Loads all vocabulary from FRDEMasterLexicon.sqlite (unified source).
/// Single source of truth for all vocabulary in the app.
enum StandardVocabularyLoader {
    struct Entry {
        let sourceDisplay: String
        let target: String
        let cardType: CardType
        /// Rohes Niveau-Tag aus dem ursprünglichen Import (A1…C2).
        ///
        /// **Nicht für Lernlisten benutzen** — dafür gibt es
        /// `learnLevel`. Diese Spalte speist die Schwierigkeits-Logik
        /// (`MCDistractorFilter`, `vocabularyLevel(for:)`) und die
        /// Wörterbuch-Gruppierung; sie stammt aber aus dem Bulk-Import
        /// und ist als Lernstufe unbrauchbar (Befund 2026-08-06).
        let level: String          // A1, A2, B1, B2, C1, C2

        /// **Kuratiertes Lern-Niveau** (A1/A2/B1/B2) oder leer.
        ///
        /// Vergeben von `tools/assign_learn_levels.py` aus vier
        /// Kriterien: kuratiertes A1 als Anker, Korpusfrequenz
        /// (Lexique 3), Wortart-Abgleich gegen Homographen, und für
        /// Wendungen das Niveau ihres schwersten Bestandteils plus eine
        /// Stufe. Leer heißt „gehört in kein Lernpaket" — der Eintrag
        /// bleibt über Wörterbuch und Themenlisten erreichbar.
        ///
        /// 4.866 von 56.367 Einträgen tragen ein Lern-Niveau. Das
        /// entspricht den fachlichen Zielgrößen (Beacco/RLD kumuliert
        /// 5.518; Klett Schulwortschatz A1–B2 „ca. 5000 Wörter und
        /// Wendungen") — der große Rest ist Wörterbuch, kein Lernstoff.
        let learnLevel: String
        let wordClass: String      // noun, verb, adjective, adverb, etc.
        let gender: String         // m, f, or empty
        let topic: String          // Essen & Trinken, Familie & Freunde, etc.
        let frequency: Double
        /// Quelle des Genus-Werts — für Transparenz in der UI und
        /// spätere Review-Tools. Leer/default = aus DB direkt.
        /// Wird durch den `FrenchGenderResolver`-Pass gefüllt, wenn die
        /// DB selbst kein Genus hatte.
        let genderSource: FrenchGenderSource
        let genderConfidence: Double

        // ─── Stufe 1 (2026-04-28) — Lernjahr-Tags ───
        // Werden NUR für A1-Einträge befüllt (im DB-Schema NULL für
        // alle anderen Levels). nil = nicht getaggt; "" für TEXT-Felder
        // signalisiert „in DB war NULL" (defensive Default).

        /// Lernjahr 1-5, NUR für A1-Einträge. Sonst nil.
        let lernjahr: Int?
        /// Confidence-Tag der AI-Klassifizierung: "high"/"med"/"low"/"".
        let confidence: String
        /// Schulrelevanz-Tag: "high"/"med"/"low"/"".
        let schulrelevanz: String

        init(
            sourceDisplay: String,
            target: String,
            cardType: CardType,
            level: String,
            learnLevel: String = "",
            wordClass: String,
            gender: String,
            topic: String,
            frequency: Double,
            genderSource: FrenchGenderSource = .explicitArticle,
            genderConfidence: Double = 1.0,
            lernjahr: Int? = nil,
            confidence: String = "",
            schulrelevanz: String = ""
        ) {
            self.sourceDisplay = sourceDisplay
            self.target = target
            self.cardType = cardType
            self.level = level
            self.learnLevel = learnLevel
            self.wordClass = wordClass
            self.gender = gender
            self.topic = topic
            self.frequency = frequency
            self.genderSource = genderSource
            self.genderConfidence = genderConfidence
            self.lernjahr = lernjahr
            self.confidence = confidence
            self.schulrelevanz = schulrelevanz
        }
    }

    /// **Master-Entry-Liste.** Wird einmal pro App-Start berechnet:
    ///   1. `loadEntries()`  — rohes SQLite-Ergebnis
    ///   2. `postProcessResolveGenders(_:)` — Genus-Pipeline für Nomen
    ///      ohne `gender_fr`: Artikel-Parse → Plural-Lookup → Heuristik.
    ///      KI-Overrides werden später (Phase 2) aus einer Bundle-
    ///      Ressource geladen und hier priorisiert; Platzhalter unten.
    static let allEntries: [Entry] = {
        let raw = loadEntries()
        return postProcessResolveGenders(raw)
    }()

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

    /// Lookup-Set aller **deutschen Nomen** (lowercased). Wird vom
    /// zentralen `TextNormalizationEngine` genutzt, um in
    /// zusammengesetzten Phrasen wie „den Regenschutz für den
    /// Kinderwagen vorbereiten" jedes Wort, das ein Nomen ist,
    /// korrekt großzuschreiben — auch wenn es NICHT das letzte
    /// Token der Phrase ist (der bisherige Default „nach Artikel nur
    /// letztes Token groß" hat diese Fälle fälschlich kleingeschrieben).
    ///
    /// Aufbaustrategie: Wir iterieren alle `nounEntries` und
    /// sammeln aus jedem `target` alle Tokens, die mit einem
    /// Großbuchstaben beginnen (inklusive Kompositum-Nomen wie
    /// „der Regenschirm für den Schulranzen" → „Regenschirm" UND
    /// „Schulranzen" landen im Set). Artikel/Präpositionen/Adjektive
    /// bleiben klein in der DB und landen deshalb nicht im Set.
    static let germanNounSet: Set<String> = {
        var set: Set<String> = []
        for entry in nounEntries {
            let germanTrim = entry.target.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !germanTrim.isEmpty else { continue }
            let tokens = germanTrim.split(separator: " ").map(String.init)
            for token in tokens {
                guard let first = token.first, first.isUppercase else { continue }
                let cleaned = token
                    .lowercased()
                    .trimmingCharacters(in: CharacterSet.punctuationCharacters)
                guard !cleaned.isEmpty else { continue }
                set.insert(cleaned)
            }
        }
        return set
    }()

    /// Grundformen deutscher Adjektive (Einzelwort-Lemmata aus Einträgen mit
    /// `word_class == "adjective"`), lowercased. Genutzt als Gegen-Check zu
    /// `germanNounSet` — manche Adjektive (v. a. Farben: „grün", „blau" …)
    /// sind im Deutschen **substantivierbar** („die Auszeit im Grünen") und
    /// tauchen deshalb auch als großgeschriebenes Token in einem echten
    /// Nomen-Eintrag auf, was sie in `germanNounSet` landen lässt. Ohne
    /// diesen Gegen-Check kapitalisiert `TextNormalizationEngine` dann auch
    /// die viel häufigere attributive Verwendung fälschlich groß —
    /// **Bug-Fix 2026-08-06** (User-Screenshot: „Ich nehme einen Grünen
    /// Salat." statt „einen grünen Salat.").
    static let germanAdjectiveStems: Set<String> = {
        var set: Set<String> = []
        for entry in allEntries where entry.wordClass == "adjective" {
            let trimmed = entry.target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !trimmed.isEmpty, !trimmed.contains(" ") else { continue }
            set.insert(trimmed)
        }
        return set
    }()

    /// Ja, wenn `token` (Grundform ODER eine gängige adjektivische
    /// Flexionsform davon) als deutsches Adjektiv bekannt ist. Deckt die
    /// schwache/starke Deklinationsendungen ab (-e/-en/-em/-er/-es), z. B.
    /// „grünen" → Stamm „grün".
    static func isKnownGermanAdjectiveForm(_ token: String) -> Bool {
        let lower = token.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lower.isEmpty else { return false }
        if germanAdjectiveStems.contains(lower) { return true }
        for suffix in ["en", "em", "er", "es", "e"] where lower.hasSuffix(suffix) && lower.count > suffix.count + 1 {
            let stem = String(lower.dropLast(suffix.count))
            if germanAdjectiveStems.contains(stem) { return true }
        }
        return false
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

            // **2026-04-25 Nomen-Kapitalisierung (Standard-Wortschatz)**:
            // Die SQLite-Quelle enthält teilweise kleingeschriebene
            // deutsche Nomen. Für `wordClass == "noun"` normalisieren
            // wir hier an der zentralen Loader-Stelle — einmalig beim
            // App-Start, danach sehen alle Konsumenten (Flashcards,
            // Quiz, Lexikon, Training, …) die korrekt kapitalisierte
            // Form. Nicht-Nomen bleiben unangetastet.
            let normalizedGerman = normalizeGermanNounTarget(
                entry.target,
                wordClass: entry.wordClass
            )

            return VocabularyItem(
                rawFrench: entry.sourceDisplay,
                rawGerman: normalizedGerman,
                cardType: cardType,
                level: vocabularyLevel(for: entry.level),
                sourceLanguage: .french,
                wordClass: entry.wordClass.isEmpty ? nil : entry.wordClass
            )
        }
    }()

    // MARK: - Nomen-Kapitalisierung (2026-04-25)
    //
    // Delegation an die zentrale Utility `GermanNounCapitalization`.
    // Bewusst als Wrapper erhalten, damit der Loader-Call-Site
    // (`vocabularyItems`-Konstruktor) lesbar bleibt.

    /// POS-gated Nomen-Kapitalisierung. Siehe
    /// `GermanNounCapitalization.normalizeGermanNounTarget`.
    static func normalizeGermanNounTarget(_ target: String, wordClass: String) -> String {
        GermanNounCapitalization.normalizeGermanNounTarget(target, wordClass: wordClass)
    }

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

    /// Items für ein oder mehrere **Lern-Niveaus** (`learnLevel`).
    ///
    /// Bewusst getrennt von `items(forLevels:)`: Das ist die Grundlage
    /// der Lernlisten, während `level` weiter die Schwierigkeits- und
    /// Wörterbuch-Logik speist. Einträge ohne Lern-Niveau (leerer
    /// String) tauchen hier nie auf — siehe `Entry.learnLevel`.
    static func items(forLearnLevels levels: Set<String>) -> [VocabularyItem] {
        vocabularyItems.enumerated().compactMap { index, item in
            let learnLevel = allEntries[index].learnLevel
            guard !learnLevel.isEmpty else { return nil }
            return levels.contains(learnLevel) ? item : nil
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

    /// Alle Niveau-Tags, die in der DB **vorkommen** — inklusive C1/C2.
    ///
    /// Nicht zu verwechseln mit `learnableLevels`: Das sind die Stufen,
    /// die als Lernliste angeboten werden (A1–B2, siehe Begründung
    /// dort). C-Einträge existieren weiterhin im Lexikon, sie bekommen
    /// nur keine eigene Lernliste mehr. Wer über Niveaus **filtert**,
    /// braucht diese vollständige Liste; wer Lernlisten **baut**,
    /// braucht `learnableLevels`.
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

    /// **Block C (2026-05-03)** — User-Spec: Verben-Modi ziehen
    /// nur Single-Verb-Lemmas, keine Phrasen. Defensive Filter
    /// für `.verbs` (Synthesis) und `.verbforms` (Pool-Filter), weil
    /// die DB vereinzelt Multi-Word-Einträge als `wordClass == "verb"`
    /// taggt (z.B. „aller voir un film") — Code-Filter schützt
    /// gegen diese Daten-Drift.
    ///
    /// Akzeptiert:
    ///   * **Single-Token** ohne Space (inkludiert Apostroph-geglue
    ///     wie `s'amuser`, `n'entendre` — französische Apostroph-
    ///     Verschmelzung zählt nicht als Token-Trenner).
    ///   * **2 Tokens** wenn erste = `se` (reflexives Verb mit
    ///     Space, z.B. `se laver`, `se promener`).
    ///
    /// Ablehnt: alles andere (Mehrwort-Phrasen, „aller voir",
    /// „être en train de", …).
    nonisolated static func isSingleVerbLemma(_ french: String) -> Bool {
        let trimmed = french.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return false }
        let tokens = trimmed.split(separator: " ").map(String.init)
        if tokens.count == 1 { return true }
        if tokens.count == 2, tokens[0] == "se" { return true }
        return false
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

    /// Nachschlagetabelle Französisch-Term → **Lern-Niveau**.
    ///
    /// Aufgebaut wie `wordClassMap` (voller Schlüssel, artikel-befreit,
    /// akzentfrei), damit ein Lexikon-Eintrag unabhängig von seiner
    /// Schreibweise gefunden wird — „la maison", „maison" und „maison"
    /// ohne Akzente treffen denselben Eintrag.
    ///
    /// Speist den Niveau-Filter im Wörterbuch (`LexiconView`). Nur
    /// Einträge MIT Lern-Niveau landen hier; wer nicht drinsteht,
    /// gehört in kein Lernpaket (siehe `Entry.learnLevel`).
    static let learnLevelMap: [String: String] = {
        var map: [String: String] = [:]
        for entry in allEntries where !entry.learnLevel.isEmpty {
            let key = entry.sourceDisplay.lowercased()
            map[key] = entry.learnLevel
            let stripped = strippedArticle(key)
            if stripped != key {
                map[stripped] = entry.learnLevel
                let accentStripped = stripDiacritics(stripped)
                if accentStripped != stripped { map[accentStripped] = entry.learnLevel }
            }
            let accentStripped = stripDiacritics(key)
            if accentStripped != key { map[accentStripped] = entry.learnLevel }
        }
        return map
    }()

    /// Lern-Niveau eines französischen Begriffs, oder `nil` wenn er in
    /// keinem Lernpaket steht.
    static func learnLevel(for frenchText: String) -> String? {
        let key = frenchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if let level = learnLevelMap[key] { return level }
        let stripped = strippedArticle(key)
        if stripped != key, let level = learnLevelMap[stripped] { return level }
        let accentStripped = stripDiacritics(key)
        if accentStripped != key, let level = learnLevelMap[accentStripped] { return level }
        return nil
    }

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

    /// **2026-08-06** — Namen an die kumulative Logik angepasst: Die
    /// Stufen bauen aufeinander auf („bis A2" enthält A1), deshalb ist
    /// „bis" ehrlicher als die alten Stufen-Etiketten „Mittelstufe"/
    /// „Oberstufe", die einen isolierten Block suggerierten. Der
    /// GER-Buchstabe bleibt vorn, weil Schüler ihn aus dem Unterricht
    /// und von DELF kennen. C1/C2 stehen nicht mehr drin — siehe
    /// `learnableLevels`.
    private static let levelNames: [String: String] = [
        "A1": "A1 Grundwortschatz",
        "A2": "A2 Aufbauwortschatz (mit A1)",
        "B1": "B1 Mittelstufe (mit A1–A2)",
        "B2": "B2 Oberstufe (mit A1–B1)",
        // Kein GER-Buchstabe — siehe Begründung an `learnableLevels`.
        "XP": "Über den Schulstoff hinaus (mit A1–B2)"
    ]

    static let allInOneList: VocabularyList = VocabularyList(
        id: UUID(uuidString: "F1E1EEE1-A000-4000-A000-000000000000")!,
        name: "Komplettes Wörterbuch",
        items: vocabularyItems,
        isBuiltIn: true,
        collectionPreset: .standardLevel,
        isAggregateVocabulary: true
    )

    // ─── Stufe 1 (2026-04-28) — Lernjahr-Children für die A1-Liste ───
    //
    // 5 atomare per-Year-Buckets. Jedes Child enthält NUR die Items
    // des jeweiligen Lernjahrs (kein Overlap). Cumulative-Slicing
    // passiert im `VocabularyListSelectionResolver` zur Auswahlzeit.
    //
    // Y4/Y5 sind aktuell leer (alle 932 A1-Tags liegen in Y1-Y3) —
    // werden trotzdem gerendert (UI: 5er-Grid-Konsistenz). Bei
    // späterem Tagging-Run werden sie automatisch befüllt.
    private static let lernjahrChildLists: [VocabularyList] = {
        // Stable Hex-UUIDs (kein L/J — wären kein gültiges Hex).
        let uuids: [Int: UUID] = [
            1: UUID(uuidString: "F1E1EEE1-A001-4000-A000-000000000001")!,
            2: UUID(uuidString: "F1E1EEE1-A002-4000-A000-000000000002")!,
            3: UUID(uuidString: "F1E1EEE1-A003-4000-A000-000000000003")!,
            4: UUID(uuidString: "F1E1EEE1-A004-4000-A000-000000000004")!,
            5: UUID(uuidString: "F1E1EEE1-A005-4000-A000-000000000005")!,
        ]
        var lists: [VocabularyList] = []
        for year in 1...5 {
            let yearItems = vocabularyItems.enumerated().compactMap { idx, item -> VocabularyItem? in
                allEntries[idx].lernjahr == year ? item : nil
            }
            lists.append(VocabularyList(
                id: uuids[year]!,
                name: "\(year). Lernjahr",
                items: yearItems,
                isBuiltIn: true,
                collectionPreset: .standardLevel
            ))
        }
        return lists
    }()

    /// Die Niveaustufen, die als **Lernlisten** angeboten werden.
    ///
    /// **2026-08-06, Neuzuschnitt (User-Spec + Recherche)**. Zwei Gründe
    /// dafür, hier hart bei B2 (dem GER-Etikett) zu stoppen:
    ///
    ///   • **Schulziel**: Die KMK-Bildungsstandards setzen B1 zum
    ///     mittleren Abschluss und B2 zum Abitur an (Beschlüsse
    ///     04.12.2003 bzw. 18.10.2012). Oberhalb B2 gibt es für unsere
    ///     Zielgruppe kein GER-Lernziel mehr.
    ///   • **Es gibt gar kein C-Wortinventar**: Die offiziellen
    ///     Europarat-Referenzbände für Französisch („Niveau A1/A2/B1/B2
    ///     pour le français", Beacco et al.) führen für C1/C2 keine
    ///     Wortlisten mehr, nur noch konzeptuelle Beschreibungen. Ein
    ///     Frequenzband als „C1"/„C2" zu labeln wäre eine unbelegte
    ///     Setzung mit amtlich klingendem Namen.
    ///
    /// **2026-08-07** — für Wortschatz JENSEITS von B2 gibt es trotzdem
    /// eine fünfte Stufe: `XP` „Über den Schulstoff hinaus" (User-Wunsch:
    /// „sieht dünn aus, können wir noch was drauflegen"). Bewusst KEIN
    /// GER-Etikett — sagt ehrlich, was es ist, statt einen Anspruch
    /// („C1") vorzutäuschen, den wir nicht einlösen können.
    ///
    /// Was früher als C1/C2 getaggt war, war faktisch der Schwanz der
    /// Import-Reihenfolge (`frequency_rank` ist KEINE Korpusfrequenz,
    /// sondern die Reihenfolge des Bulk-Imports — siehe Doku an der
    /// SQL-Abfrage in `loadEntries()`). Deshalb standen dort Wörter wie
    /// „kalfatern", „bevatern" und „Albert-Paradiesvogel" — nichts davon
    /// ist in `XP`, das über echte Korpusfrequenz (Lexique 3) + Wortart-
    /// Abgleich zugeordnet wird (`tools/assign_learn_levels.py`). Der
    /// alte C1/C2-Bestand bleibt über Lexikon und `allInOneList`
    /// nachschlagbar, nur eben nicht mehr als eigene Lernliste.
    private static let learnableLevels = ["A1", "A2", "B1", "B2", "XP"]

    static let levelLists: [VocabularyList] = {
        var lists: [VocabularyList] = []
        let levelUUIDs: [String: UUID] = [
            "A1": UUID(uuidString: "F1E1EEE1-A100-4000-A000-000000000001")!,
            "A2": UUID(uuidString: "F1E1EEE1-A200-4000-A000-000000000002")!,
            "B1": UUID(uuidString: "F1E1EEE1-B100-4000-A000-000000000003")!,
            "B2": UUID(uuidString: "F1E1EEE1-B200-4000-A000-000000000004")!,
            // Kein L/J/X/P — wäre kein gültiges Hex (siehe Kommentar an
            // `lernjahrChildLists`).
            "XP": UUID(uuidString: "F1E1EEE1-9900-4000-A000-000000000005")!,
        ]
        for (index, level) in learnableLevels.enumerated() {
            // **Kumulativ (2026-08-06, User-Spec)** — „A2 muss A1
            // enthalten, B1 muss A1+A2 enthalten". Das ist auch die
            // fachliche Konvention: Gespeichert wird pro Wort GENAU EIN
            // Niveau (die Stufe, auf der es eingeführt wird — so machen
            // es Beacco/RLD, CEFRLex und Duolingo), angezeigt wird
            // kumulativ (so machen es die Goethe-Wortlisten und die
            // Schulwortschätze von Klett/PONS). Die B1-Wortliste des
            // Goethe-Instituts etwa enthält A1 und A2 vollständig.
            //
            // Vorher war jede Stufe ein isolierter Block — wer B1 wählte,
            // übte den A1-Grundwortschatz nicht mit, obwohl er selbst-
            // verständlich dazugehört.
            let includedLevels = Set(learnableLevels.prefix(index + 1))
            // **2026-08-06** — `learnLevel` statt `level`: Die alte
            // Spalte stammt aus dem Bulk-Import und war als Lernstufe
            // unbrauchbar (B1 enthielt 31.615 Einträge, darunter
            // maschinell erzeugte Konstrukte). Die neue Zuordnung
            // stammt aus `tools/assign_learn_levels.py`.
            let levelItems = items(forLearnLevels: includedLevels)
            guard !levelItems.isEmpty else { continue }
            // A1-Liste bekommt zusätzlich Lernjahr-Children
            // (Stufe 1, 2026-04-28); Cumulative-Slicing dieser Children
            // passiert im `VocabularyListSelectionResolver`.
            let isA1 = (level == "A1")
            lists.append(VocabularyList(
                id: levelUUIDs[level]!,
                name: levelNames[level] ?? level,
                items: levelItems,
                isBuiltIn: true,
                collectionPreset: .standardLevel,
                children: isA1 ? lernjahrChildLists : nil,
                cumulativeChildren: isA1
            ))
        }
        return lists
    }()

    static let topicLists: [VocabularyList] = {
        // **2026-04-28 A1-Cleanup**: Schwelle 20 → 15 gesenkt, damit
        // die neue kuratierte A1-Liste „Im Straßenverkehr" (17
        // Einträge) als Themen-Liste sichtbar wird. Side-Effect-Check
        // gegen die DB ergab: kein einziges weiteres Topic liegt im
        // Range 15-19 (kleinster bestehender Topic = „Wissenschaft"
        // mit 1114 Einträgen). Senkung ist daher risikofrei, keine
        // Müll-Topics werden dadurch neu sichtbar.
        let minItems = 15
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

    // MARK: - Post-Processing: Genus-Pipeline

    /// Zentrale Schnittstelle für den `FrenchGenderResolver`. Läuft
    /// **einmal** beim App-Start:
    ///
    /// Für jeden Nomen-Eintrag:
    ///   • Wenn `gender_fr` bereits aus DB gefüllt → unverändert lassen,
    ///     `genderSource = .explicitArticle` (DB hat meist aus Artikel
    ///     abgeleitet)
    ///   • Wenn `gender_fr` leer → `FrenchGenderResolver.resolve`
    ///     aufrufen mit Plural-Singular-Lookup und optionalen KI-
    ///     Overrides
    ///   • Ergebnis: Entry mit gefülltem `gender`, normalisiertem
    ///     `sourceDisplay` (inkl. Artikel), `genderSource` und
    ///     `genderConfidence`
    private static func postProcessResolveGenders(_ raw: [Entry]) -> [Entry] {
        #if DEBUG
        // Self-Tests für die Plural-Artikel-Regeln. Crash-früh bei
        // Regression, damit wir Pipeline-Bugs sofort im Console-Log
        // sehen.
        FrenchGenderResolverSelfTest.runIfNeeded()
        #endif

        // Lookup-Tabelle für Plural-Schritt 2a aufbauen:
        // aus allen Einträgen mit eindeutigem Artikel (le/la) eine
        // Map Core → Genus ableiten, damit wir bei „les X" nachschlagen
        // können.
        let singularGenderMap = buildSingularGenderMap(raw)
        let aiOverrides = loadAIGenderOverrides()

        var resolved: [Entry] = []
        resolved.reserveCapacity(raw.count)
        var counts = (explicitArticle: 0, dbLookup: 0, heuristic: 0, aiOverride: 0, unknown: 0, alreadyFilled: 0)

        for entry in raw {
            guard entry.wordClass == "noun" else {
                resolved.append(entry)
                continue
            }

            // DB hat bereits ein Genus? → nicht anfassen.
            if !entry.gender.isEmpty {
                counts.alreadyFilled += 1
                resolved.append(entry)
                continue
            }

            let resolution = FrenchGenderResolver.resolve(
                rawLemma: entry.sourceDisplay,
                pluralLookup: { core in
                    singularGenderMap[core.lowercased()]
                },
                aiOverrides: aiOverrides
            )

            switch resolution.source {
            case .explicitArticle: counts.explicitArticle += 1
            case .dbLookup:        counts.dbLookup += 1
            case .heuristic:       counts.heuristic += 1
            case .aiOverride:      counts.aiOverride += 1
            case .unknown:         counts.unknown += 1
            }

            let newGender = resolution.gender?.rawValue ?? ""
            resolved.append(
                Entry(
                    sourceDisplay: resolution.normalizedLemma,
                    target: entry.target,
                    cardType: entry.cardType,
                    level: entry.level,
                    wordClass: entry.wordClass,
                    gender: newGender,
                    topic: entry.topic,
                    frequency: entry.frequency,
                    genderSource: resolution.source,
                    genderConfidence: resolution.confidence,
                    // **Bug-Fix 2026-04-28**: V1a-Lernjahr-Felder MÜSSEN
                    // hier durchgereicht werden — sonst verlieren alle
                    // Nomen-Phrasen mit explizitem Artikel (la/le/l'…)
                    // ihren lernjahr-Tag, weil dieser Resolver-Pass sie
                    // als neue Entries rekonstruiert. Symptom: A1-
                    // Children-Counts 390/436/49 statt 420/458/54.
                    lernjahr: entry.lernjahr,
                    confidence: entry.confidence,
                    schulrelevanz: entry.schulrelevanz
                )
            )
        }

        #if DEBUG
        appDebugLog("""
        🔤 [GenderResolver] Master-Pass abgeschlossen:
           DB-vorhanden:  \(counts.alreadyFilled)
           explicit art:  \(counts.explicitArticle)
           DB-Lookup:     \(counts.dbLookup)
           heuristic:     \(counts.heuristic)
           ai-override:   \(counts.aiOverride)
           unknown:       \(counts.unknown)
        """)
        #endif
        return resolved
    }

    /// Baut aus allen Einträgen mit eindeutigem Genus (aus DB oder
    /// Artikel) eine Map Core → Genus. Wird vom Resolver-Plural-
    /// Lookup konsumiert: „les amis" → core „amis" → singular „ami"
    /// via morphologische Pluralrückführung → Map-Treffer → m.
    private static func buildSingularGenderMap(_ entries: [Entry]) -> [String: FrenchGenderHeuristicRules.Gender] {
        var map: [String: FrenchGenderHeuristicRules.Gender] = [:]
        for entry in entries where entry.wordClass == "noun" && !entry.gender.isEmpty {
            let gender: FrenchGenderHeuristicRules.Gender? = {
                switch entry.gender.lowercased() {
                case "m": return .masculine
                case "f": return .feminine
                default:  return nil
                }
            }()
            guard let g = gender else { continue }
            // Core extrahieren
            let (_, core, _) = FrenchGenderResolver.splitArticleAndCore(entry.sourceDisplay)
            let key = core.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty else { continue }
            // Direkter Key (z. B. „ami")
            if map[key] == nil { map[key] = g }
            // Pluralrückführung: „amis" → „ami", „écoles" → „école"
            // Simpler Regel: -s/-x am Ende entfernen
            if key.hasSuffix("s") || key.hasSuffix("x") {
                let stem = String(key.dropLast())
                if !stem.isEmpty, map[stem] == nil { map[stem] = g }
            }
        }
        return map
    }

    /// Lädt optionale KI-Genus-Overrides aus einer Bundle-Ressource
    /// (`gender_ai_overrides.json`). Format:
    ///
    /// ```json
    /// {
    ///   "eau":   { "gender": "f", "confidence": 0.99 },
    ///   "homme": { "gender": "m", "confidence": 0.99 }
    /// }
    /// ```
    ///
    /// Wird von Phase 2 (Python-Pipeline `tools/gender_ai_resolver.py`)
    /// generiert. Wenn die Datei nicht im Bundle liegt, läuft die
    /// Pipeline ohne KI-Anteil — Heuristik + Plural-Lookup bleiben aktiv.
    private static func loadAIGenderOverrides() -> [String: (gender: FrenchGenderHeuristicRules.Gender, confidence: Double)]? {
        guard let url = Bundle.main.url(forResource: "gender_ai_overrides", withExtension: "json") else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            struct RawOverride: Decodable {
                let gender: String
                let confidence: Double
            }
            let raw = try JSONDecoder().decode([String: RawOverride].self, from: data)
            var parsed: [String: (gender: FrenchGenderHeuristicRules.Gender, confidence: Double)] = [:]
            for (key, value) in raw {
                let gender: FrenchGenderHeuristicRules.Gender? = {
                    switch value.gender.lowercased() {
                    case "m", "masculine": return .masculine
                    case "f", "feminine":  return .feminine
                    default: return nil
                    }
                }()
                guard let g = gender else { continue }
                parsed[key.lowercased()] = (g, value.confidence)
            }
            #if DEBUG
            appDebugLog("🔤 [GenderResolver] \(parsed.count) KI-Overrides geladen aus Bundle.")
            #endif
            return parsed.isEmpty ? nil : parsed
        } catch {
            #if DEBUG
            appDebugLog("🔤 [GenderResolver] Fehler beim Laden von gender_ai_overrides.json: \(error)")
            #endif
            return nil
        }
    }

    private static func loadEntries() -> [Entry] {
        guard let result = SupplementalFreeDictLexicon.withReadOnlyDatabase({ database -> [Entry] in
            // **Stufe 1 (2026-04-28)**: SQL liest 11 Spalten statt 8.
            // Drei neue Spalten (lernjahr/confidence/schulrelevanz) sind
            // nur für A1-Einträge befüllt (DB-Migration vom 2026-04-28).
            // Bei NULL-Werten (alle non-A1) → lernjahr=nil, conf=""=rel.
            //
            // ⚠️ **`frequency_rank` ist KEINE Korpusfrequenz** (Befund
            // 2026-08-06). Die Spalte enthält die **Reihenfolge des
            // Bulk-Imports**: Rang 1–25 sind lückenlos Verben, ab 146
            // beginnen die Adjektive, ab 194 die Adverbien, und ab 2268
            // stehen thematisch gruppierte Nomen (Familie, Wohnen …).
            // Ein Wort mit hohem Rang ist also nicht selten, sondern nur
            // spät importiert — gemessen an echter Korpusfrequenz
            // (Lexique 3) sind C1/C2 sogar minimal HÄUFIGER als B2.
            //
            // Das `ORDER BY` unten ist daher eine **stabile, aber
            // inhaltlich bedeutungslose** Sortierung. Sie bleibt drin,
            // weil `items(for:)` & Co. über den Index auf `allEntries`
            // zugreifen und die Reihenfolge deshalb deterministisch sein
            // muss — nicht, weil sie „die häufigsten zuerst" liefert.
            // Wer echte Frequenz braucht, muss sie erst beschaffen
            // (z. B. Lexique 3) und als eigene Spalte einziehen.
            let sql = """
                SELECT lemma_fr, lemma_de, word_class, gender_fr, level, is_phrase, frequency_rank, topic,
                       lernjahr, confidence, schulrelevanz, learn_level
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

                // Lernjahr: SQLite liefert 0 für NULL-INTEGER. Wir
                // nutzen den expliziten NULL-Check via column_type.
                let lernjahr: Int? = {
                    guard sqlite3_column_type(stmt, 8) != SQLITE_NULL else { return nil }
                    return Int(sqlite3_column_int(stmt, 8))
                }()
                let confidence = sqlite3_column_text(stmt, 9).map { String(cString: $0) } ?? ""
                let schulrelevanz = sqlite3_column_text(stmt, 10).map { String(cString: $0) } ?? ""
                // NULL (= kein Lernpaket) kommt hier als "" an.
                let learnLevel = sqlite3_column_text(stmt, 11).map { String(cString: $0) } ?? ""

                entries.append(Entry(
                    sourceDisplay: lemmaFr,
                    target: lemmaDe,
                    cardType: isPhrase == 1 ? .phrases : .words,
                    level: level,
                    learnLevel: learnLevel,
                    wordClass: wordClass,
                    gender: genderFr,
                    topic: topic,
                    frequency: Double(freqRank),
                    lernjahr: lernjahr,
                    confidence: confidence,
                    schulrelevanz: schulrelevanz
                ))
            }
            return entries
        }) else {
            appDebugLog("⚠️ FRDEMasterLexicon.sqlite not found or failed to open")
            return []
        }

        appDebugLog("📚 StandardVocabulary loaded from SQLite: \(result.count) entries")
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
