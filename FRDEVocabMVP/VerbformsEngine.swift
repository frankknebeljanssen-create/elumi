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
        case .il: return "il/elle"
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

    var isAvailable: Bool {
        true
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
                // Parse all forms: detect person + tense
                var tenseForms: [VerbformsTense: [VerbformsPerson: String]] = [:]

                for form in data.forms {
                    guard let person = parsePerson(form) else { continue }
                    let tense = detectTense(form, person: person)
                    tenseForms[tense, default: [:]][person] = form
                }

                // Need at least one tense with 6 persons
                let hasCompleteTense = tenseForms.values.contains { $0.count >= 5 }
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

    /// Generate questions filtered by selected tenses
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
                (verb.tenseForms[tense]?.count ?? 0) >= 5
            }
            guard let tense = availableTenses.randomElement() else { continue }
            guard let tenseForms = verb.tenseForms[tense] else { continue }

            let person = persons.randomElement()!
            guard let correctForm = tenseForms[person] else { continue }

            // Distractors: other persons of the SAME verb in the SAME tense
            let distractors = persons
                .filter { $0 != person }
                .compactMap { tenseForms[$0] }
                .shuffled()

            guard distractors.count >= 3 else { continue }

            questions.append(VerbformsQuestion(
                infinitive: verb.infinitive,
                translation: verb.translation,
                tense: tense,
                person: person,
                correctAnswer: correctForm,
                distractors: Array(distractors)
            ))
        }

        return questions
    }

    /// Check which tenses have data in the loaded inflections
    static func availableTenses(in inflections: [VerbInflections]) -> Set<VerbformsTense> {
        var result = Set<VerbformsTense>()
        for verb in inflections {
            for (tense, forms) in verb.tenseForms where forms.count >= 5 {
                result.insert(tense)
            }
        }
        return result
    }

    // MARK: - Tense Detection

    /// Detect tense from a conjugated form based on endings
    static func detectTense(_ form: String, person: VerbformsPerson) -> VerbformsTense {
        let verbPart = stripPronoun(form).lowercased()

        // Imparfait endings: -ais, -ais, -ait, -ions, -iez, -aient
        switch person {
        case .je, .tu:
            if verbPart.hasSuffix("ais") { return .imparfait }
        case .il:
            if verbPart.hasSuffix("ait") { return .imparfait }
        case .nous:
            if verbPart.hasSuffix("ions") { return .imparfait }
        case .vous:
            if verbPart.hasSuffix("iez") { return .imparfait }
        case .ils:
            if verbPart.hasSuffix("aient") { return .imparfait }
        }

        // Futur simple endings: -ai, -as, -a, -ons, -ez, -ont (on infinitive stem)
        // Heuristic: futur has -rai, -ras, -ra, -rons, -rez, -ront
        switch person {
        case .je:
            if verbPart.hasSuffix("rai") { return .futurSimple }
        case .tu:
            if verbPart.hasSuffix("ras") { return .futurSimple }
        case .il:
            if verbPart.hasSuffix("ra") && !verbPart.hasSuffix("ira") { return .futurSimple }
            if verbPart.hasSuffix("ira") { return .futurSimple } // finira
        case .nous:
            if verbPart.hasSuffix("rons") { return .futurSimple }
        case .vous:
            if verbPart.hasSuffix("rez") { return .futurSimple }
        case .ils:
            if verbPart.hasSuffix("ront") { return .futurSimple }
        }

        // Default: Präsens
        return .present
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
