import Foundation
import SQLite3

// MARK: - Data Model

enum VerbformsPerson: Int, CaseIterable, Identifiable {
    case je = 0, tu, il, nous, vous, ils

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .je: return "je"
        case .tu: return "tu"
        case .il: return "il/elle/on"
        case .nous: return "nous"
        case .vous: return "vous"
        case .ils: return "ils/elles"
        }
    }

    var promptLabel: String {
        switch self {
        case .je: return "1. Person Singular"
        case .tu: return "2. Person Singular"
        case .il: return "3. Person Singular"
        case .nous: return "1. Person Plural"
        case .vous: return "2. Person Plural"
        case .ils: return "3. Person Plural"
        }
    }
}

enum VerbformsMode: String, CaseIterable, Identifiable {
    case multipleChoice = "Auswählen"
    case typing = "Text eingeben"

    var id: String { rawValue }
}

enum VerbformsTense: String, CaseIterable, Identifiable {
    case present = "Präsens"
    case imparfait = "Imparfait"
    case futurSimple = "Futur"
    case passeCompose = "Passé composé"

    var id: String { rawValue }

    var hasData: Bool {
        true // wird dynamisch geprüft
    }

    /// Nur Präsens ist aktuell spielbar. Andere Zeitformen werden in der UI
    /// angezeigt, aber gedimmt („demnächst"), bis sie didaktisch sauber
    /// integriert sind.
    var isAvailable: Bool {
        self == .present
    }
}

struct VerbformsQuestion: Identifiable {
    let id = UUID()
    let infinitive: String
    let translation: String
    let tense: VerbformsTense
    let person: VerbformsPerson
    let correctAnswer: String
    let distractors: [String]

    var allOptions: [String] {
        ([correctAnswer] + distractors).shuffled()
    }
}

/// Eine Runde im Drag-and-Drop-Modus: ein Verb, ein Tempus, alle 6 Person-Form-Paare
/// werden gleichzeitig gezeigt. Der Lerner zieht die Pronomen-Karten auf die passenden
/// Form-Karten; jedes Paar wird individuell grün/orange bewertet, nach 6 richtigen
/// Paaren ist die Runde abgeschlossen.
struct VerbformsMatchingRound: Identifiable {
    let id = UUID()
    let infinitive: String
    let translation: String
    let tense: VerbformsTense
    /// Jede Person mit ihrer gestrippten Form (z.B. .je → "vais", .nous → "nous appelons")
    let forms: [VerbformsPerson: String]
}

// MARK: - Engine

enum VerbformsEngine {

    /// Key for tense+person forms
    typealias TensePersonKey = (tense: VerbformsTense, person: VerbformsPerson)

    /// Parsed inflection set for one verb, grouped by tense
    struct VerbInflections {
        let entryID: Int
        let infinitive: String
        let translation: String
        let tenseForms: [VerbformsTense: [VerbformsPerson: String]]
        // e.g. [.present: [.je: "je vais", .tu: "tu vas", ...], .imparfait: [.je: "j'allais", ...]]
    }

    /// Load ALL verb inflections, grouped by detected tense
    /// (Fallback für "kein Listen-Kontext"; wird aktuell NICHT mehr in der UI gerufen,
    /// weil Verbformen ausschließlich aus den Nutzerlisten rekrutiert.)
    static func loadAllInflections(limit: Int = 500) -> [VerbInflections] {
        return SupplementalFreeDictLexicon.withReadOnlyDatabase { database -> [VerbInflections] in
            let sql = """
                SELECT f.form, f.entry_id, e.lemma_fr, e.lemma_de
                FROM forms f
                JOIN entries e ON f.entry_id = e.entry_id
                WHERE f.form_type = 'inflection' AND e.word_class = 'verb'
                ORDER BY e.frequency_rank ASC, f.entry_id, f.rowid
                """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let stmt = statement else { return [] }
            defer { sqlite3_finalize(stmt) }

            var grouped: [Int: (infinitive: String, translation: String, forms: [String])] = [:]
            var seenEntries = 0
            var lastEntryID = -1

            while sqlite3_step(stmt) == SQLITE_ROW {
                let form = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let entryID = Int(sqlite3_column_int(stmt, 1))
                let lemmaFr = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let lemmaDe = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""

                if entryID != lastEntryID {
                    seenEntries += 1
                    lastEntryID = entryID
                    if seenEntries > limit { break }
                }

                if grouped[entryID] == nil {
                    grouped[entryID] = (infinitive: lemmaFr, translation: lemmaDe, forms: [])
                }
                grouped[entryID]?.forms.append(form)
            }

            return grouped.compactMap { entryID, data in
                let tenseForms = groupFormsByTense(data.forms)

                let hasCompleteTense = tenseForms.values.contains { $0.count >= 6 }
                guard hasCompleteTense else { return nil }

                return VerbInflections(
                    entryID: entryID,
                    infinitive: data.infinitive,
                    translation: data.translation,
                    tenseForms: tenseForms
                )
            }
        } ?? []
    }

    /// Load inflections GEFILTERT nach einer Lemma-Liste aus der Listen-Analyse.
    ///
    /// Input: Lemmata wie sie vom `FrenchListStatisticsAggregator` geliefert werden
    /// (kann reflexive Form enthalten, z.B. "s'appeler", "se lever").
    ///
    /// Strategie:
    /// 1. Primärversuch: `lemma_fr = '<original>'` (falls DB „s'appeler" direkt kennt)
    /// 2. Fallback: `lemma_fr = '<bare>'` (z.B. „appeler"), Formen werden reflexiv synthetisiert:
    ///    "j'appelle" → "je m'appelle", "nous appelons" → "nous nous appelons" usw.
    ///
    /// So funktioniert das Modul konsistent mit dem analysierten Verb aus der Liste —
    /// egal ob in der Quelle nur „je m'appelle" stand oder direkt „s'appeler".
    static func loadInflections(forLemmas lemmas: [String]) -> [VerbInflections] {
        guard !lemmas.isEmpty else { return [] }

        // Normalisiere und bestimme Fallback-Varianten pro Lemma
        struct LemmaRequest {
            let display: String       // „s'appeler" (Anzeige-Lemma)
            let primaryKey: String    // „s'appeler" (Exakt-Match in DB)
            let fallbackKey: String?  // „appeler" (falls reflexiv, für Synthese)
            let isReflexive: Bool
        }

        var requests: [LemmaRequest] = []
        var queryTerms = Set<String>()

        for raw in lemmas {
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty else { continue }
            let bare = Self.bareLemmaIfReflexive(normalized)
            requests.append(LemmaRequest(
                display: normalized,
                primaryKey: normalized,
                fallbackKey: bare,
                isReflexive: bare != nil
            ))
            queryTerms.insert(normalized)
            if let bare { queryTerms.insert(bare) }
        }

        let terms = Array(queryTerms)
        guard !terms.isEmpty else { return [] }

        // Lade alle Matches auf einmal, gruppiert nach lemma_fr
        struct DBEntry {
            let entryID: Int
            let translation: String
            var forms: [String]
        }
        var lemmaToEntry: [String: DBEntry] = [:]

        SupplementalFreeDictLexicon.withReadOnlyDatabase { database -> Void in
            let placeholders = Array(repeating: "?", count: terms.count).joined(separator: ",")
            let sql = """
                SELECT f.form, f.entry_id, LOWER(e.lemma_fr), e.lemma_de
                FROM forms f
                JOIN entries e ON f.entry_id = e.entry_id
                WHERE f.form_type = 'inflection'
                  AND e.word_class = 'verb'
                  AND LOWER(e.lemma_fr) IN (\(placeholders))
                ORDER BY e.lemma_fr, f.rowid
                """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
                  let stmt = statement else { return }
            defer { sqlite3_finalize(stmt) }

            for (idx, term) in terms.enumerated() {
                sqlite3_bind_text(stmt, Int32(idx + 1), term, -1, SupplementalFreeDictLexicon.sqliteTransient)
            }

            while sqlite3_step(stmt) == SQLITE_ROW {
                let form = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                let entryID = Int(sqlite3_column_int(stmt, 1))
                let lemmaFr = sqlite3_column_text(stmt, 2).map { String(cString: $0) } ?? ""
                let lemmaDe = sqlite3_column_text(stmt, 3).map { String(cString: $0) } ?? ""

                if lemmaToEntry[lemmaFr] == nil {
                    lemmaToEntry[lemmaFr] = DBEntry(entryID: entryID, translation: lemmaDe, forms: [])
                }
                lemmaToEntry[lemmaFr]?.forms.append(form)
            }
        }

        // Baue VerbInflections pro Request
        var results: [VerbInflections] = []
        var seenKeys = Set<String>()

        for request in requests {
            // Idempotent: gleiches Lemma nicht doppelt verarbeiten
            guard !seenKeys.contains(request.display) else { continue }
            seenKeys.insert(request.display)

            // 1. Primärversuch (exakter Match, auch bei reflexivem Lemma)
            if let dbEntry = lemmaToEntry[request.primaryKey] {
                let tenseForms = groupFormsByTense(dbEntry.forms)
                if tenseForms.values.contains(where: { $0.count >= 6 }) {
                    results.append(VerbInflections(
                        entryID: dbEntry.entryID,
                        infinitive: request.display,
                        translation: dbEntry.translation,
                        tenseForms: tenseForms
                    ))
                    continue
                }
            }

            // 2. Fallback (bare Form + Reflexiv-Synthese)
            if request.isReflexive, let fallbackKey = request.fallbackKey,
               let dbEntry = lemmaToEntry[fallbackKey] {
                var tenseForms = groupFormsByTense(dbEntry.forms)
                tenseForms = Self.applyReflexiveCliticSynthesis(tenseForms)
                if tenseForms.values.contains(where: { $0.count >= 6 }) {
                    results.append(VerbInflections(
                        entryID: dbEntry.entryID,
                        infinitive: request.display,
                        translation: dbEntry.translation,
                        tenseForms: tenseForms
                    ))
                }
            }
        }

        return results
    }

    /// Erkennt ein reflexives Lemma und liefert die bare Form zurück (sonst nil).
    /// "s'appeler" → "appeler", "se lever" → "lever", "aller" → nil
    static func bareLemmaIfReflexive(_ lemma: String) -> String? {
        let lower = lemma.lowercased()
        if lower.hasPrefix("s'") || lower.hasPrefix("s\u{2019}") {
            return String(lemma.dropFirst(2))
        }
        if lower.hasPrefix("se ") {
            return String(lemma.dropFirst(3))
        }
        return nil
    }

    /// Synthetisiert aus bare-Formen (z.B. „j'appelle", „tu appelles", „nous appelons")
    /// die reflexiven Formen („je m'appelle", „tu t'appelles", „nous nous appelons").
    private static func applyReflexiveCliticSynthesis(
        _ tenseForms: [VerbformsTense: [VerbformsPerson: String]]
    ) -> [VerbformsTense: [VerbformsPerson: String]] {
        var result: [VerbformsTense: [VerbformsPerson: String]] = [:]
        for (tense, forms) in tenseForms {
            var newForms: [VerbformsPerson: String] = [:]
            for (person, form) in forms {
                newForms[person] = synthesizeReflexiveForm(person: person, bareForm: form)
            }
            result[tense] = newForms
        }
        return result
    }

    /// Bildet aus einer bare-Form + Person die reflexive Form.
    /// Beispiele:
    /// - (.je, "j'appelle")   → "je m'appelle"
    /// - (.nous, "nous lavons") → "nous nous lavons"
    /// - (.il, "il lave")     → "il se lave"
    static func synthesizeReflexiveForm(person: VerbformsPerson, bareForm: String) -> String {
        let stripped = stripPronoun(bareForm)
        let needsElision = Self.startsWithVowelOrMuteH(stripped)

        switch person {
        case .je:
            return needsElision ? "je m'\(stripped)" : "je me \(stripped)"
        case .tu:
            return needsElision ? "tu t'\(stripped)" : "tu te \(stripped)"
        case .il:
            return needsElision ? "il s'\(stripped)" : "il se \(stripped)"
        case .nous:
            return "nous nous \(stripped)"
        case .vous:
            return "vous vous \(stripped)"
        case .ils:
            return needsElision ? "ils s'\(stripped)" : "ils se \(stripped)"
        }
    }

    private static func startsWithVowelOrMuteH(_ text: String) -> Bool {
        let first = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().first
        guard let ch = first else { return false }
        return "aeiouâêîôûéèëïüàùh".contains(ch)
    }

    /// Generate questions filtered by selected tenses
    /// Erzeugt Fragen, bei denen die Optionen NUR die flektierte Form enthalten
    /// (ohne Subjekt-Pronomen). Reflexive Klitiken (m'/t'/s'/nous/vous/s')
    /// bleiben erhalten — didaktisch korrekt: „m'appelle", „nous appelons".
    static func generateQuestions(
        from inflections: [VerbInflections],
        tenses: Set<VerbformsTense>,
        count: Int = 20
    ) -> [VerbformsQuestion] {
        guard !inflections.isEmpty, !tenses.isEmpty else { return [] }

        var questions: [VerbformsQuestion] = []
        let persons = VerbformsPerson.allCases

        for _ in 0..<(count * 3) { // try more to reach count
            guard questions.count < count else { break }
            guard let verb = inflections.randomElement() else { continue }

            // Pick a random tense from the selected ones that this verb actually has
            let availableTenses = tenses.filter { tense in
                (verb.tenseForms[tense]?.count ?? 0) >= 6
            }
            guard let tense = availableTenses.randomElement() else { continue }
            guard let tenseForms = verb.tenseForms[tense] else { continue }

            let person = persons.randomElement()!
            guard let correctFormFull = tenseForms[person] else { continue }
            let correctFormShort = Self.strippedAnswer(correctFormFull)
            guard !correctFormShort.isEmpty else { continue }

            // Distractors: andere Personen desselben Verbs in derselben Zeitform.
            // Gestrippt wie die korrekte Antwort (nur Verb-Form, kein Subjekt-Pronomen).
            // Dedup-Check gegen correctFormShort case-insensitive, damit keine
            // Person dieselbe Form trägt wie die richtige Lösung.
            var distractorSet: [String] = []
            var seenLower = Set<String>([correctFormShort.lowercased()])
            for p in persons.shuffled() where p != person {
                guard let full = tenseForms[p] else { continue }
                let short = Self.strippedAnswer(full)
                let key = short.lowercased()
                if short.isEmpty || seenLower.contains(key) { continue }
                seenLower.insert(key)
                distractorSet.append(short)
            }

            guard distractorSet.count >= 3 else { continue }

            questions.append(VerbformsQuestion(
                infinitive: verb.infinitive,
                translation: verb.translation,
                tense: tense,
                person: person,
                correctAnswer: correctFormShort,
                distractors: distractorSet
            ))
        }

        return questions
    }

    /// Entfernt nur das SUBJEKT-Pronomen (je/tu/il/elle/nous/vous/ils/elles)
    /// — Reflexiv-Klitiken bleiben erhalten.
    ///   "je vais"            → "vais"
    ///   "j'appelle"          → "appelle"
    ///   "je m'appelle"       → "m'appelle"
    ///   "nous nous appelons" → "nous appelons"
    /// Originalschreibweise wird beibehalten (kein lowercased).
    static func strippedAnswer(_ fullForm: String) -> String {
        let trimmed = fullForm.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let prefixes = ["je ", "j'", "j\u{2019}", "tu ", "il ", "elle ", "nous ", "vous ", "ils ", "elles "]
        for p in prefixes {
            if lower.hasPrefix(p) {
                return String(trimmed.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return trimmed
    }

    /// Baut aus Person + gestrippter Form die volle Konjugation (mit Elision
    /// für „je" → „j'" vor Vokal / stummem h). Wird für Feedback-Texte
    /// genutzt, wo dem Lerner die komplette Form gezeigt werden soll:
    ///   (.je, "vais")      → "je vais"
    ///   (.je, "appelle")   → "j'appelle"
    ///   (.je, "m'appelle") → "je m'appelle"
    ///   (.nous, "nous appelons") → "nous nous appelons"
    static func fullConjugation(person: VerbformsPerson, form: String) -> String {
        let f = form.trimmingCharacters(in: .whitespacesAndNewlines)
        switch person {
        case .je:
            return Self.startsWithVowelOrMuteH(f) ? "j'\(f)" : "je \(f)"
        case .tu:    return "tu \(f)"
        case .il:    return "il \(f)"
        case .nous:  return "nous \(f)"
        case .vous:  return "vous \(f)"
        case .ils:   return "ils \(f)"
        }
    }

    /// Erzeugt Matching-Runden: pro Runde EIN Verb in EINER Zeitform,
    /// alle 6 Personen-Form-Paare werden gleichzeitig angeboten.
    static func generateMatchingRounds(
        from inflections: [VerbInflections],
        tenses: Set<VerbformsTense>,
        count: Int = 8
    ) -> [VerbformsMatchingRound] {
        guard !inflections.isEmpty, !tenses.isEmpty else { return [] }

        var rounds: [VerbformsMatchingRound] = []
        let shuffledVerbs = inflections.shuffled()

        for verb in shuffledVerbs where rounds.count < count {
            // Zeitformen des Verbs, die mindestens 6 Personen komplett haben
            let eligibleTenses = tenses.filter { tense in
                (verb.tenseForms[tense]?.count ?? 0) >= 6
            }.shuffled()

            for tense in eligibleTenses {
                guard let full = verb.tenseForms[tense] else { continue }

                // Gestrippte Form pro Person (nur Verb-Form, ohne Subjekt-Pronomen)
                var stripped: [VerbformsPerson: String] = [:]
                for person in VerbformsPerson.allCases {
                    guard let fullForm = full[person] else { continue }
                    let short = Self.strippedAnswer(fullForm)
                    guard !short.isEmpty else { continue }
                    stripped[person] = short
                }

                guard stripped.count == 6 else { continue }

                // KEIN Eindeutigkeits-Filter — bei -er-Verben in Präsens haben
                // je/il/elles dieselbe Form („parle"). Das wird in der UI durch
                // N-zu-1-Mapping gelöst: pro eindeutiger Form nur eine Karte unten,
                // freie Slots werden mit Platzhaltern aufgefüllt. So bleiben alle
                // Listen-Verben spielbar; Pronomen erscheinen nie in den Form-Karten.
                rounds.append(VerbformsMatchingRound(
                    infinitive: verb.infinitive,
                    translation: verb.translation,
                    tense: tense,
                    forms: stripped
                ))
                break // pro Verb nur eine Runde, danach nächstes Verb
            }
        }

        return rounds
    }

    /// Check which tenses have data in the loaded inflections.
    /// Filtert zusätzlich auf `tense.isAvailable` — aktuell ist nur Präsens freigegeben,
    /// die anderen Zeitformen werden in der UI angezeigt aber gedimmt.
    static func availableTenses(in inflections: [VerbInflections]) -> Set<VerbformsTense> {
        var result = Set<VerbformsTense>()
        for verb in inflections {
            for (tense, forms) in verb.tenseForms where forms.count >= 6 && tense.isAvailable {
                result.insert(tense)
            }
        }
        return result
    }

    // MARK: - Tense Detection (Group-based)

    /// Group a verb's raw forms into tense buckets by collecting 6-person sets
    /// und klassifizieren jedes Set über nous/ils-Form-Suffixe.
    /// WICHTIG: Nicht eindeutig klassifizierbare Sets (z.B. Passé simple oder
    /// Conditionnel, die in der DB oft zusätzlich vorhanden sind) werden
    /// VERWORFEN — nicht als Präsens durchgelassen. Damit erscheinen Formen
    /// wie „tu habitas" (passé simple, literarisch) NICHT mehr als Optionen.
    static func groupFormsByTense(_ rawForms: [String]) -> [VerbformsTense: [VerbformsPerson: String]] {
        // 1. Parse all forms with pronouns into (person, form) pairs
        var parsedForms: [(person: VerbformsPerson, form: String)] = []
        for form in rawForms {
            if let person = parsePerson(form) {
                parsedForms.append((person, form))
            }
        }

        // 2. Collect consecutive 6-person sets
        var tenseForms: [VerbformsTense: [VerbformsPerson: String]] = [:]
        var currentSet: [VerbformsPerson: String] = [:]

        let finalize: ([VerbformsPerson: String]) -> Void = { set in
            // no-op helper — die Zuweisung passiert im inneren Loop unten via Closure-Capture
            _ = set
        }
        _ = finalize

        func finalizeSet(_ set: [VerbformsPerson: String]) {
            guard set.count >= 6, let tense = detectTenseFromSet(set) else { return }
            // Primärer „present"-Treffer darf nicht überschrieben werden — falls
            // die DB Präsens + weitere Sets liefert, nehmen wir das erste.
            if tenseForms[tense] == nil {
                tenseForms[tense] = set
            }
        }

        for (person, form) in parsedForms {
            if currentSet[person] != nil {
                finalizeSet(currentSet)
                currentSet = [:]
            }
            currentSet[person] = form
        }
        finalizeSet(currentSet)

        return tenseForms
    }

    /// Strenge Tempus-Erkennung per Suffix-Heuristik auf nous/ils-Form.
    /// Liefert nur dann ein Tempus zurück, wenn das Set EINDEUTIG einem der
    /// unterstützten Tempora entspricht. Sonst `nil` → das Set wird in
    /// `groupFormsByTense` verworfen (verhindert Passé-simple-Leakage als
    /// Präsens, die zu „tu habitas" etc. geführt hat).
    private static func detectTenseFromSet(_ set: [VerbformsPerson: String]) -> VerbformsTense? {
        // 1. Passé composé: die je-Form enthält Auxiliar + Partizip („j'ai parlé")
        if let jeForm = set[.je] {
            let verbPart = stripPronoun(jeForm).trimmingCharacters(in: .whitespaces)
            if verbPart.contains(" ") {
                return .passeCompose
            }
        }

        // 2. nous-Form als primärer Discriminator (nichts-kompositorische Tempora)
        if let nousForm = set[.nous] {
            let nv = stripPronoun(nousForm).lowercased()

            // Reflexive Form hat Klitik-Prefix „nous " → strip nochmal, um das Stammsuffix zu prüfen
            let stripped: String = {
                if nv.hasPrefix("nous ") {
                    return String(nv.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                }
                return nv
            }()

            // Rejection zuerst: literarische/komplexe Zeiten, die wir nicht anbieten
            if stripped.hasSuffix("âmes") || stripped.hasSuffix("îmes") || stripped.hasSuffix("ûmes") {
                return nil // passé simple
            }
            if stripped.hasSuffix("rions") {
                return nil // conditionnel
            }
            if stripped.hasSuffix("assions") || stripped.hasSuffix("issions") || stripped.hasSuffix("ussions") {
                return nil // subjonctif imparfait / plus-que-parfait subj
            }

            if stripped.hasSuffix("ions") { return .imparfait }
            if stripped.hasSuffix("rons") { return .futurSimple }
            // Präsens: -ons, aber NICHT -rons oder -ions (oben bereits abgehandelt)
            if stripped.hasSuffix("ons") { return .present }
        }

        // 3. ils-Form als Zweit-Discriminator, falls nous nicht greift
        if let ilsForm = set[.ils] {
            let iv = stripPronoun(ilsForm).lowercased()
            let stripped: String = {
                if iv.hasPrefix("s'") || iv.hasPrefix("s\u{2019}") {
                    return String(iv.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                }
                if iv.hasPrefix("se ") {
                    return String(iv.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                }
                return iv
            }()

            // Rejection literarischer Tempora
            if stripped.hasSuffix("èrent") || stripped.hasSuffix("irent") || stripped.hasSuffix("urent") {
                return nil // passé simple
            }
            if stripped.hasSuffix("raient") { return nil } // conditionnel
            if stripped.hasSuffix("assent") || stripped.hasSuffix("issent") || stripped.hasSuffix("ussent") {
                return nil // subjonctif imparfait
            }

            if stripped.hasSuffix("aient") { return .imparfait }
            if stripped.hasSuffix("ront") { return .futurSimple }
            // Präsens-Endungen ils: -ent (parlent), -ont (sont, ont, vont), -nt allgemein
            if stripped.hasSuffix("ent") || stripped.hasSuffix("ont") {
                return .present
            }
        }

        // Set passt zu keinem bekannten Tempus → verwerfen
        return nil
    }

    // MARK: - Helpers

    /// Parse person from conjugated form prefix (e.g. "je suis" → .je)
    static func parsePerson(_ form: String) -> VerbformsPerson? {
        let lower = form.lowercased().trimmingCharacters(in: .whitespaces)

        if lower.hasPrefix("je ") || lower.hasPrefix("j'") || lower.hasPrefix("j\u{2019}") {
            return .je
        }
        if lower.hasPrefix("tu ") { return .tu }
        if lower.hasPrefix("il ") || lower.hasPrefix("elle ") { return .il }
        if lower.hasPrefix("nous ") { return .nous }
        if lower.hasPrefix("vous ") { return .vous }
        if lower.hasPrefix("ils ") || lower.hasPrefix("elles ") { return .ils }

        return nil
    }

    /// Strip pronoun prefix from form
    private static func stripPronoun(_ text: String) -> String {
        let prefixes = ["je ", "j'", "j\u{2019}", "tu ", "il ", "elle ", "nous ", "vous ", "ils ", "elles "]
        let lower = text.lowercased()
        for p in prefixes {
            if lower.hasPrefix(p) {
                return String(lower.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return lower
    }
}
