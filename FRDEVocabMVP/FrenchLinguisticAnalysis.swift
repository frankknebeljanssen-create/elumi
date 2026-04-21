import Foundation
import SwiftUI

// MARK: - ZENTRALE FRANZÖSISCHE LINGUISTISCHE ANALYSE
//
// Single Source of Truth für:
//   • Wortart-Erkennung (Nomen/Verb/Adjektiv/Adverb)
//   • Lemma-Ermittlung (Infinitiv, Singular, masc. Singular)
//   • Display-Typ (Einzelwort / Phrase / Satz)
//   • Listen-Statistik (eindeutige Lemmata pro Wortart)
//
// Architektur-Schichten:
//   1) `FrenchTextNormalizer`              — Text-Säuberung (OCR, Apostrophe, Whitespace)
//   2) `FrenchEntryAnalyzer`               — Pro Eintrag: Display-Typ, POS, Lemmata, Confidence
//   3) `FrenchListStatisticsAggregator`    — Über Listen: eindeutige Lemmata pro POS
//   4) `FrenchLemmaFormatter`              — UI-Hinweise („savoir", „être" etc.)
//
// Views lesen nur das Ergebnis — keine Analyse-Logik in Views.
//
// Daten-Herkunft:
//   • `StandardVocabularyLoader.wordClassMap`           — Volltext-Lookup
//   • `StandardVocabularyLoader.inflectionWordClassMap` — Flexionen → Wortart
//   • `StandardVocabularyLoader.inflectionInfinitiveMap`— Verb-Flexion → Infinitiv
//   • SQLite-`forms`-Tabelle (indirekt via StandardVocabularyLoader)
//   • Harte Spezialfälle in dieser Datei (c'est, ce sont, il est, …)

// MARK: - Models

/// Wie der Eintrag optisch angezeigt wird — unabhängig von den extrahierten Wortarten.
enum EntryDisplayType: String {
    case singleWord
    case phrase
    case sentence
    case unknown
}

/// Primäre Wortart für Anzeige/Filter — bei Phrasen immer `.phrase`, auch wenn intern Verb+Nomen erkannt wurden.
enum EntryPrimaryPOS: String {
    case noun
    case verb
    case adjective
    case adverb
    case phrase
    case sentence
    case unknown
}

/// Wortarten, die das System aktiv extrahiert.
enum DetectedPOS: String, Hashable, CaseIterable {
    case noun
    case verb
    case adjective
    case adverb
}

/// Sicherheit der Analyse. Nur `medium` und `high` gehen in die Listen-Statistik.
enum AnalysisConfidence: Int, Comparable {
    case low = 0
    case medium = 1
    case high = 2

    static func < (lhs: AnalysisConfidence, rhs: AnalysisConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Sonderkategorien für Wörter, die NICHT zu den vier Ziel-Wortarten
/// (noun/verb/adjective/adverb) gehören, aber im Französischen sehr häufig sind
/// und eigene Behandlung brauchen.
///
/// Wichtig: `SpecialCategory`-Einträge fliessen NIE in `ListPOSStatistics`
/// (uniqueVerbCount / uniqueNounCount / …) ein.
enum SpecialCategory: String, Equatable {
    case interjection       // oui, non, merci, bonjour, bravo, oh, ah
    case presentationWord   // voilà, voici  (Präsentativ)
    case particle           // eh bien, ben, bah
    case formulaic          // au revoir, d'accord, à bientôt, s'il vous plaît
    case other
}

/// Gesammelte Lemmata je Wortart für EINEN Eintrag.
struct EntryLemmas: Equatable {
    var verbs: [String] = []
    var nouns: [String] = []
    var adjectives: [String] = []
    var adverbs: [String] = []

    var isEmpty: Bool {
        verbs.isEmpty && nouns.isEmpty && adjectives.isEmpty && adverbs.isEmpty
    }
}

/// Ergebnis einer Einzeleintrag-Analyse. Das ist, was ViewModels/Views konsumieren.
struct EntryAnalysisResult: Equatable {
    let originalText: String
    let normalizedText: String
    let displayType: EntryDisplayType
    let primaryPos: EntryPrimaryPOS
    let detectedPos: [DetectedPOS]
    let lemmas: EntryLemmas
    let analysisConfidence: AnalysisConfidence
    let showLemmaHint: Bool
    let lemmaHintText: String?
    /// Rohe DB-Wortart (z.\u{00A0}B. „pronoun", „preposition", „conjunction", „interjection",
    /// „phrase"), falls der Volltext direkt gematcht wurde. Wird benutzt, wenn primaryPos
    /// = .unknown ist, um Labels wie „Pronomen", „Präposition" statt „Wort" anzuzeigen.
    let directWordClass: String?
    /// Separate Sonderkategorie-Achse (voilà, merci, bonjour …). Fliesst NICHT in
    /// `ListPOSStatistics` ein. Wird nur für die Anzeige verwendet.
    let specialCategory: SpecialCategory?

    /// Zählt dieser Eintrag in die Haupt-POS-Statistik
    /// (uniqueVerbCount / uniqueNounCount / uniqueAdjCount / uniqueAdvCount)?
    /// Special-Category-Einträge sind ausgeschlossen.
    var countsInMainPOSStats: Bool {
        specialCategory == nil
    }
}

/// Analyse-Modus. `balanced` ist die Standard-Pipeline.
enum AnalysisMode {
    case strict        // nur Volltext-Treffer, keine Phrase-Extraktion
    case balanced      // Standard: Phrase-Scan + Reflexiv/Plural-Heuristik
    case aggressive    // reserviert für spätere Erweiterungen
}

/// Aggregierte Statistik über alle Einträge einer Liste.
struct ListPOSStatistics: Equatable {
    let entryCount: Int
    let uniqueVerbCount: Int
    let uniqueNounCount: Int
    let uniqueAdjectiveCount: Int
    let uniqueAdverbCount: Int
    /// Interjektionen + Präsentativ + Partikel + Wendung als gemeinsamer Bucket.
    /// Wird zusätzlich zur Haupt-POS-Statistik geführt.
    let uniqueInterjectionCount: Int
    let verbLemmas: [String]
    let nounLemmas: [String]
    let adjectiveLemmas: [String]
    let adverbLemmas: [String]
    let interjectionLemmas: [String]

    static let empty = ListPOSStatistics(
        entryCount: 0,
        uniqueVerbCount: 0,
        uniqueNounCount: 0,
        uniqueAdjectiveCount: 0,
        uniqueAdverbCount: 0,
        uniqueInterjectionCount: 0,
        verbLemmas: [],
        nounLemmas: [],
        adjectiveLemmas: [],
        adverbLemmas: [],
        interjectionLemmas: []
    )
}

// MARK: - Service A: Text-Normalisierung

enum FrenchTextNormalizer {

    /// Normalisiert Text für die Analyse (Lookup-Form, nicht Anzeige).
    /// Originaltext bleibt erhalten; Normalisierung ist nur Analyse-Ebene.
    static func normalize(_ text: String) -> String {
        var s = text

        // 1) Apostroph-Varianten vereinheitlichen
        s = s.replacingOccurrences(of: "\u{2019}", with: "'") // right single quote
        s = s.replacingOccurrences(of: "\u{02BC}", with: "'") // modifier apostrophe
        s = s.replacingOccurrences(of: "\u{2018}", with: "'") // left single quote
        s = s.replacingOccurrences(of: "\u{0060}", with: "'") // grave

        // 2) Kleinbuchstaben für Lookup
        s = s.lowercased()

        // 3) OCR-Whitespace um Apostrophe: „c' est" → „c'est", „j ' ai" → „j'ai"
        s = s.replacingOccurrences(
            of: #"\s*'\s*"#,
            with: "'",
            options: .regularExpression
        )

        // 4) Mehrfach-Leerzeichen zu einem
        s = s.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )

        // 5) Leerzeichen vor Satzzeichen reduzieren
        s = s.replacingOccurrences(
            of: #"\s+([.,;:!?])"#,
            with: "$1",
            options: .regularExpression
        )

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Service B: Eintrag-Analyse

enum FrenchEntryAnalyzer {

    /// Hilfsverb-Infinitive. Bei reiner Hilfsverb-Extraktion bleibt Confidence = low.
    static let auxiliaryVerbInfinitives: Set<String> = ["\u{00EA}tre", "etre", "avoir"]

    /// Zentrale Tabelle für häufige französische Ausdruckswörter, die NICHT zu den
    /// vier Ziel-Wortarten gehören. Alle Keys sind bereits normalisiert
    /// (lowercase, einheitlicher Apostroph). Werden VOR der normalen Analyse geprüft.
    ///
    /// Diese Einträge:
    ///   • setzen `specialCategory`
    ///   • lassen `lemmas`, `detectedPos`, `lemmaHint` leer
    ///   • primaryPos bleibt `.unknown`
    ///   • fliessen NIE in `ListPOSStatistics` ein
    static let specialCategoryMap: [String: SpecialCategory] = [
        "voil\u{00E0}":  .presentationWord,    // voilà
        "voila":         .presentationWord,
        "voici":         .presentationWord,
        "oui":           .interjection,
        "non":           .interjection,
        "merci":         .interjection,
        "bonjour":       .interjection,
        "salut":         .interjection,
        "bonsoir":       .interjection,
        "bonne nuit":    .interjection,
        "bravo":         .interjection,
        "oh":            .interjection,
        "ah":            .interjection,
        "eh":            .interjection,
        "h\u{00E9}":     .interjection,        // hé
        "h\u{00E9}las": .interjection,         // hélas
        "ouf":           .interjection,
        "ouille":        .interjection,
        "mince":         .interjection,
        "zut":           .interjection,
        "eh bien":       .particle,
        "ben":           .particle,
        "bah":           .particle,
        "quoi":          .particle,
        "au revoir":     .formulaic,
        "\u{00E0} bient\u{00F4}t":   .formulaic,  // à bientôt
        "\u{00E0} plus":             .formulaic,  // à plus
        "\u{00E0} demain":           .formulaic,  // à demain
        "\u{00E0} tout \u{00E0} l'heure": .formulaic,
        "bienvenue":     .interjection,
        "d'accord":      .formulaic,
        "s'il vous pla\u{00EE}t": .formulaic,
        "s'il te pla\u{00EE}t":   .formulaic,
        "pardon":        .interjection,
        "d\u{00E9}sol\u{00E9}":   .interjection, // désolé
        "d\u{00E9}sol\u{00E9}e":  .interjection
    ]

    /// Harte Spezialfälle für verschmolzene Formen, die das DB-Inflektions-Mapping nicht trifft.
    /// Alle Keys sind bereits normalisiert (lowercase, einheitlicher Apostroph).
    static let contractedVerbLemmas: [String: String] = [
        "c'est":      "\u{00EA}tre",
        "c'\u{00E9}tait":    "\u{00EA}tre",
        "c'\u{00E9}taient":  "\u{00EA}tre",
        "c'\u{00E9}tais":    "\u{00EA}tre",
        "ce sont":    "\u{00EA}tre",
        "il est":     "\u{00EA}tre",
        "elle est":   "\u{00EA}tre",
        "on est":     "\u{00EA}tre",
        "nous sommes":"\u{00EA}tre",
        "vous \u{00EA}tes": "\u{00EA}tre",
        "ils sont":   "\u{00EA}tre",
        "elles sont": "\u{00EA}tre",
        "je suis":    "\u{00EA}tre",
        "tu es":      "\u{00EA}tre",
        "j'ai":       "avoir",
        "tu as":      "avoir",
        "il a":       "avoir",
        "elle a":     "avoir",
        "nous avons": "avoir",
        "vous avez":  "avoir",
        "ils ont":    "avoir",
        "elles ont":  "avoir"
    ]

    /// Eindeutig reflexive Pronomen: wenn vor einem Verb stehen, MUSS es reflexiv sein.
    /// „nous"/„vous" sind NICHT drin, weil sie auch Subjektpronomen sind
    /// („nous allons" = wir gehen, nicht „s'aller").
    static let strictReflexiveClitics: Set<String> = [
        "me", "m", "te", "t", "se", "s"
    ]

    /// Legacy-Alias (Split-Logik). Enthält auch nous/vous zum Token-Splitten,
    /// wird aber NICHT automatisch für Reflexiv-Umschreibung benutzt.
    static let reflexiveClitics: Set<String> = [
        "me", "m", "te", "t", "se", "s", "nous", "vous"
    ]

    /// Funktionswörter, die im Phrase-Scan als „Füllung" gelten und übersprungen werden.
    static let frenchFunctionWordTokens: Set<String> = [
        "je", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles",
        "me", "m", "te", "t", "se", "s", "le", "la", "les", "l",
        "un", "une", "des", "du", "de", "d", "au", "aux",
        "ce", "ça", "ca", "cet", "cette", "ces",
        "mon", "ton", "son", "ma", "ta", "sa",
        "mes", "tes", "ses", "notre", "votre", "leur", "leurs", "nos", "vos",
        "ne", "pas", "plus", "que", "qu", "quoi", "qui",
        "et", "ou", "mais", "donc", "or", "car",
        "à", "a", "en", "par", "pour", "sur", "sous", "dans",
        "si", "y"
    ]

    /// Hauptfunktion — analysiert einen Eintrag und liefert ein vollständiges Ergebnis.
    static func analyze(_ text: String, mode: AnalysisMode = .balanced) -> EntryAnalysisResult {
        let normalized = FrenchTextNormalizer.normalize(text)
        guard !normalized.isEmpty else {
            return EntryAnalysisResult(
                originalText: text,
                normalizedText: "",
                displayType: .unknown,
                primaryPos: .unknown,
                detectedPos: [],
                lemmas: EntryLemmas(),
                analysisConfidence: .low,
                showLemmaHint: false,
                lemmaHintText: nil,
                directWordClass: nil,
                specialCategory: nil
            )
        }

        // SONDERKATEGORIE-SHORTCUT:
        // voilà/merci/bonjour/… werden NIE als Noun/Verb/Adj/Adverb klassifiziert.
        // Leeres `lemmas` → keine Aufnahme in ListPOSStatistics.
        if let special = specialCategoryMap[normalized] {
            let dt: EntryDisplayType = normalized.contains(" ") ? .phrase : .singleWord
            return EntryAnalysisResult(
                originalText: text,
                normalizedText: normalized,
                displayType: dt,
                primaryPos: .unknown,
                detectedPos: [],
                lemmas: EntryLemmas(),
                analysisConfidence: .high,
                showLemmaHint: false,
                lemmaHintText: nil,
                directWordClass: StandardVocabularyLoader.wordClass(for: normalized),
                specialCategory: special
            )
        }

        let displayType = determineDisplayType(for: normalized)
        let (lemmas, confidence) = extractLemmas(from: normalized, displayType: displayType, mode: mode)

        let detectedPos: [DetectedPOS] = {
            var result: [DetectedPOS] = []
            if !lemmas.verbs.isEmpty      { result.append(.verb) }
            if !lemmas.nouns.isEmpty      { result.append(.noun) }
            if !lemmas.adjectives.isEmpty { result.append(.adjective) }
            if !lemmas.adverbs.isEmpty    { result.append(.adverb) }
            return result
        }()

        let primaryPos = resolvePrimaryPOS(displayType: displayType, detected: detectedPos, lemmas: lemmas)

        // Lemma-Hint: nur wenn genau 1 Verb-Lemma und Phrase/Einzelwort
        let showLemmaHint: Bool
        let lemmaHintText: String?
        if lemmas.verbs.count == 1, displayType != .unknown {
            showLemmaHint = true
            lemmaHintText = lemmas.verbs.first
        } else {
            showLemmaHint = false
            lemmaHintText = nil
        }

        // Direkter DB-Lookup für Funktionswörter (pronoun, preposition, conjunction,
        // interjection, phrase) — damit „comment", „merci", „de" nicht als „Wort" erscheinen.
        let punct = CharacterSet.punctuationCharacters.union(.whitespacesAndNewlines)
        let stripped = normalized.trimmingCharacters(in: punct)
        var directWordClass = StandardVocabularyLoader.wordClass(for: stripped)

        // Slash/Pipe-Varianten („le/la", „der/die") — wenn alle Segmente dieselbe
        // Wortart haben, übernehmen wir die als Gesamt-Wortart.
        if directWordClass == nil,
           normalized.contains("/") || normalized.contains("|") {
            let parts = normalized
                .split { $0 == "/" || $0 == "|" }
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            var classes = Set<String>()
            for part in parts {
                if let wc = StandardVocabularyLoader.wordClass(for: part) {
                    classes.insert(wc)
                }
            }
            if classes.count == 1 {
                directWordClass = classes.first
            }
        }

        return EntryAnalysisResult(
            originalText: text,
            normalizedText: normalized,
            displayType: displayType,
            primaryPos: primaryPos,
            detectedPos: detectedPos,
            lemmas: lemmas,
            analysisConfidence: confidence,
            showLemmaHint: showLemmaHint,
            lemmaHintText: lemmaHintText,
            directWordClass: directWordClass,
            specialCategory: nil
        )
    }

    // MARK: - DisplayType

    private static func determineDisplayType(for normalized: String) -> EntryDisplayType {
        // Slash/Pipe-Varianten wie „le/la", „der/die", „a/an" → kein Phrasen-Ausdruck,
        // sondern ein einzelner Begriff mit Alternativen. Als singleWord klassifizieren.
        if normalized.contains("/") || normalized.contains("|") {
            let slashParts = normalized
                .split { $0 == "/" || $0 == "|" }
                .map { String($0).trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            if slashParts.count >= 2 {
                // Alle Teile sind Einzelwörter? Dann gilt es als singleWord-Begriff.
                let allSingleWords = slashParts.allSatisfy { !$0.contains(" ") }
                if allSingleWords { return .singleWord }
            }
        }

        // Compound-Nomen / Mehrwort-Einträge, die als Ganzes ein Noun/Verb/Adj sind
        // („le jeu vidéo", „carte d'identité"): bei Volltext-Lookup auf Zielwortart
        // promovieren zu .singleWord (nicht als Phrase zählen).
        if let wc = StandardVocabularyLoader.wordClass(for: normalized),
           ["noun", "verb", "adjective", "adverb"].contains(wc) {
            return .singleWord
        }

        // Generelle Compound-Noun-Heuristik: Artikel + Nomen + Modifikator (ohne konjugiertes Verb)
        // → als singleWord-Nomen behandeln, auch wenn die DB es als „phrase" führt.
        // Beispiele: „le jeu vidéo", „la salle à manger", „le chemin de fer", „la carte d'identité"
        if looksLikeCompoundNoun(normalized) {
            return .singleWord
        }

        let tokens = splitIntoTokens(normalized)
        guard !tokens.isEmpty else { return .unknown }

        if tokens.count == 1 { return .singleWord }

        // „la fille" / „le chien" / „une maison" → optisch ein Nomen-Ausdruck
        if tokens.count == 2, StandardVocabularyLoader.wordClass(for: tokens[0]) == "pronoun"
            && isLikelyNoun(tokens[1]) {
            return .singleWord
        }
        if tokens.count == 2, isFrenchArticleToken(tokens[0]), isLikelyNoun(tokens[1]) {
            return .singleWord
        }
        // Artikel + beliebiges Wort → quasi immer ein Nomen-Ausdruck (auch wenn das
        // Wort nicht im Lexikon ist). Nur ausnehmen, wenn Token[1] bekanntlich KEIN
        // Nomen ist (z. B. seltener Fall substantiviertes Verb „le parler" — da würde
        // das Wort aber als „verb" im Lexikon stehen).
        if tokens.count == 2,
           isFrenchArticleToken(tokens[0]),
           !isKnownNonNounToken(tokens[1]) {
            return .singleWord
        }

        let endsWithSentencePunct = [".", "!", "?"].contains(where: { normalized.hasSuffix($0) })
        if endsWithSentencePunct && tokens.count >= 5 { return .sentence }

        return .phrase
    }

    /// Token ist im Lexikon als Verb/Adverb/Konjunktion/Präposition bekannt — also
    /// KEIN Nomen. Wird genutzt, um „Artikel + Wort"-Fallback nicht zu übersteuern,
    /// wenn das zweite Token klar funktional ist.
    private static func isKnownNonNounToken(_ token: String) -> Bool {
        guard let wc = StandardVocabularyLoader.wordClass(for: token) else { return false }
        return ["verb", "adverb", "conjunction", "preposition", "pronoun"].contains(wc)
    }

    // MARK: - Lemma-Extraktion

    private static func extractLemmas(
        from normalized: String,
        displayType: EntryDisplayType,
        mode: AnalysisMode
    ) -> (EntryLemmas, AnalysisConfidence) {
        // 1) Verschmelzungs-Spezialfälle: „c'est", „ce sont", „j'ai" …
        if let forced = contractedVerbLemmas[normalized] {
            var lemmas = EntryLemmas()
            lemmas.verbs.append(forced)
            return (lemmas, .high)
        }

        // 1b) Compound-Noun-Kurzweg: „le jeu vidéo", „la salle à manger" …
        // Kein Phrase-Scan, damit nicht fälschlich ein Verb-Token aufgenommen wird.
        // Lemma = artikel-gestrippte Gesamtbezeichnung (zentrale Anzeigeform).
        if looksLikeCompoundNoun(normalized) {
            var lemmas = EntryLemmas()
            let lemma = cleanLemma(normalized, wordClass: "noun")
            if !lemma.isEmpty {
                lemmas.nouns.append(lemma)
            }
            return (lemmas, .high)
        }

        var lemmas = EntryLemmas()

        // 2) Volltext-Analyse: Wenn die komplette Phrase auf ein Lemma mappt.
        if let (wc, lemma) = lookupLemma(for: normalized) {
            appendLemma(lemma, forWordClass: wc, into: &lemmas)
            let isAuxiliaryOnly = (wc == "verb") && auxiliaryVerbInfinitives.contains(lemma.lowercased())
            if displayType == .singleWord {
                return (lemmas, isAuxiliaryOnly ? .medium : .high)
            }
            // Bei Phrase als Volltreffer kann es ein Hilfsverb sein — Confidence = medium.
        }

        // 2b) singleWord + „Artikel + unbekanntes Wort" → Nomen-Lemma synthetisieren
        //     (z. B. „le garçon", wenn „garçon" noch nicht im Lexikon steht).
        //     Nur wenn weder Volltreffer noch später ein Token-Match geliefert hat.
        if displayType == .singleWord, lemmas.nouns.isEmpty, lemmas.verbs.isEmpty,
           lemmas.adjectives.isEmpty, lemmas.adverbs.isEmpty {
            let singleWordTokens = splitIntoTokens(normalized)
            if singleWordTokens.count == 2,
               isFrenchArticleToken(singleWordTokens[0]),
               !isKnownNonNounToken(singleWordTokens[1]),
               singleWordTokens[1].count >= 2 {
                lemmas.nouns.append(singleWordTokens[1])
                return (lemmas, .medium)
            }
        }

        guard mode != .strict else {
            return (lemmas, lemmas.isEmpty ? .low : .medium)
        }

        // 3) Phrase-Scan: Tokens einzeln prüfen
        let tokens = splitIntoTokens(normalized)
        var foundContentVerb = false

        for (index, token) in tokens.enumerated() {
            guard token.count >= 2 else { continue }
            if frenchFunctionWordTokens.contains(token) { continue }

            // REIHENFOLGE: Reflexiv-Kontext MUSS vor bare Infinitiv-Lookup geprüft werden,
            // sonst gewinnt „appelle" (→ appeler) gegen „m'appelle" (→ s'appeler).
            //
            // (1) Reflexiv-Clitic (me, m', te, t', se, s') unmittelbar davor →
            //     reflexive Form versuchen (DB-Direktlookup, dann Synthese).
            if index > 0 {
                let prev = tokens[index - 1]
                if strictReflexiveClitics.contains(prev) {
                    // (1a) DB-Direktlookup: rekonstruiere „PREV'TOKEN" / „PREV TOKEN"
                    let apostropheForm = "\(prev)'\(token)"
                    let spaceForm = "\(prev) \(token)"
                    if let inf = StandardVocabularyLoader.infinitive(for: apostropheForm) {
                        appendUnique(inf, into: &lemmas.verbs)
                        if !auxiliaryVerbInfinitives.contains(inf.lowercased()) {
                            foundContentVerb = true
                        }
                        continue
                    }
                    if let inf = StandardVocabularyLoader.infinitive(for: spaceForm) {
                        appendUnique(inf, into: &lemmas.verbs)
                        if !auxiliaryVerbInfinitives.contains(inf.lowercased()) {
                            foundContentVerb = true
                        }
                        continue
                    }
                    // (1b) Synthese-Fallback: Basisinfinitiv → s'/se prefixen
                    if let inf = StandardVocabularyLoader.infinitive(for: token) {
                        let reflexiveLemma = reflexiveInfinitiveForm(of: inf)
                        appendUnique(reflexiveLemma, into: &lemmas.verbs)
                        if !auxiliaryVerbInfinitives.contains(inf.lowercased()) {
                            foundContentVerb = true
                        }
                        continue
                    }
                }
            }

            // (2) Bare Infinitiv-Lookup: nicht-reflexiver Verb-Kontext.
            //     Erst NACH dem Reflexiv-Check, damit „je m'appelle" → s'appeler bleibt
            //     (nicht zu „appeler" wird).
            if let inf = StandardVocabularyLoader.infinitive(for: token) {
                appendUnique(inf, into: &lemmas.verbs)
                if !auxiliaryVerbInfinitives.contains(inf.lowercased()) {
                    foundContentVerb = true
                }
                continue
            }

            // Nomen/Adjektiv/Adverb: zentrale wordClass-Lookup-Funktion
            if let (wc, lemma) = lookupLemma(for: token) {
                appendLemma(lemma, forWordClass: wc, into: &lemmas)
            }
        }

        // Confidence festlegen
        let confidence: AnalysisConfidence
        if lemmas.isEmpty {
            confidence = .low
        } else if foundContentVerb || !lemmas.nouns.isEmpty || !lemmas.adjectives.isEmpty || !lemmas.adverbs.isEmpty {
            confidence = .high
        } else {
            // Nur Hilfsverben extrahiert (c'est/j'ai aus Phrase) → medium
            confidence = .medium
        }

        return (lemmas, confidence)
    }

    // MARK: - Helpers

    /// Split auf Whitespace, Apostroph UND Slash/Pipe, damit
    ///   „je m'appelle" → ["je", "m", "appelle"]
    ///   „le/la"        → ["le", "la"]
    ///   „la | le"      → ["la", "le"]
    private static func splitIntoTokens(_ text: String) -> [String] {
        text.split { ch in
            ch.isWhitespace
            || ch == "'" || ch == "\u{2019}"    // ' apostrophe + right single quote
            || ch == "/" || ch == "\u{FF0F}"    // / + fullwidth solidus (OCR)
            || ch == "|"
        }
        .map { String($0).trimmingCharacters(in: CharacterSet.punctuationCharacters) }
        .filter { !$0.isEmpty }
    }

    /// Liefert (word_class, lemma) für ein Token/Phrase oder nil.
    /// Arbeitet über die DB-basierten Maps aus `StandardVocabularyLoader`.
    private static func lookupLemma(for text: String) -> (String, String)? {
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        // Direkter Volltext-Treffer — liefert die Wortart und die Grundform als Lemma
        if let wc = StandardVocabularyLoader.wordClass(for: key) {
            let lemma = StandardVocabularyLoader.lemma(for: key) ?? cleanLemma(key, wordClass: wc)
            return (wc, lemma)
        }
        return nil
    }

    /// Artikel aus einem Lemma entfernen („la maison" → „maison", „l'ami" → „ami").
    private static func cleanLemma(_ raw: String, wordClass: String) -> String {
        let lower = raw.lowercased()
        let prefixes: [String] = ["le ", "la ", "les ", "un ", "une ", "des ", "l'", "du ", "de la ", "de l'"]
        for prefix in prefixes where lower.hasPrefix(prefix) {
            return String(lower.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        }
        return lower
    }

    private static func appendLemma(_ lemma: String, forWordClass wc: String, into lemmas: inout EntryLemmas) {
        let cleaned = cleanLemma(lemma, wordClass: wc)
        guard !cleaned.isEmpty else { return }
        switch wc {
        case "verb":      appendUnique(cleaned, into: &lemmas.verbs)
        case "noun":      appendUnique(cleaned, into: &lemmas.nouns)
        case "adjective": appendUnique(cleaned, into: &lemmas.adjectives)
        case "adverb":    appendUnique(cleaned, into: &lemmas.adverbs)
        default: break
        }
    }

    private static func appendUnique(_ value: String, into list: inout [String]) {
        if !list.contains(value) {
            list.append(value)
        }
    }

    /// Formt einen Infinitiv zur reflexiven Form:
    ///   Vokal/h am Anfang → `s'INFINITIV` („s'appeler", „s'habiller")
    ///   sonst → `se INFINITIV` („se présenter", „se laver")
    private static func reflexiveInfinitiveForm(of infinitive: String) -> String {
        let elisionStarters: Set<Character> = [
            "a", "e", "i", "o", "u", "h",
            "\u{00E0}", "\u{00E2}", "\u{00E4}",
            "\u{00E9}", "\u{00E8}", "\u{00EA}", "\u{00EB}",
            "\u{00EE}", "\u{00EF}",
            "\u{00F4}", "\u{00F6}",
            "\u{00F9}", "\u{00FB}", "\u{00FC}"
        ]
        guard let first = infinitive.lowercased().first else { return infinitive }
        if elisionStarters.contains(first) {
            return "s'\(infinitive)"
        }
        return "se \(infinitive)"
    }

    private static func isFrenchArticleToken(_ token: String) -> Bool {
        ["le", "la", "les", "un", "une", "des", "du", "l"].contains(token.lowercased())
    }

    private static func isLikelyNoun(_ token: String) -> Bool {
        guard let wc = StandardVocabularyLoader.wordClass(for: token) else { return false }
        return wc == "noun"
    }

    /// Generelle Heuristik zur Erkennung von Compound-Nomen:
    /// „Artikel + Nomen + Modifikator(en)" ohne konjugiertes Verb.
    /// Fängt Fälle ab, in denen die DB „phrase" fälschlich vergeben hat.
    ///
    /// Treffen: „le jeu vidéo", „la salle à manger", „le chemin de fer",
    /// „la carte d'identité", „la clé USB", „le tour de magie".
    /// Kein Treffer: „je ne sais pas" (kein Artikel-Start + konjugiertes Verb),
    /// „c'est fini" (ditto), „avec plaisir" (kein Artikel).
    static func looksLikeCompoundNoun(_ normalized: String) -> Bool {
        let articles = [
            "le ", "la ", "les ", "un ", "une ", "des ",
            "l'", "l\u{2019}"
        ]
        var body: String? = nil
        for art in articles where normalized.hasPrefix(art) {
            body = String(normalized.dropFirst(art.count))
                .trimmingCharacters(in: .whitespaces)
            break
        }
        guard let remaining = body, !remaining.isEmpty else { return false }
        // Satzzeichen am Ende → klarer Phrasen/Satz-Indikator
        if [".", "!", "?"].contains(where: { remaining.hasSuffix($0) }) { return false }

        let tokens = remaining
            .split { $0 == " " || $0 == "'" || $0 == "\u{2019}" }
            .map(String.init)
            .filter { !$0.isEmpty }
        guard tokens.count >= 1, tokens.count <= 5 else { return false }

        // Erstes Token nach Artikel muss als Nomen erkennbar sein (nounSet inkl. Plural)
        guard let first = tokens.first,
              StandardVocabularyLoader.isNoun(first) else { return false }

        // Kein konjugiertes Verb in den Tokens (Infinitive = nominalisierbar, OK)
        for token in tokens {
            if StandardVocabularyLoader.infinitive(for: token) != nil {
                return false
            }
        }
        return true
    }

    private static func resolvePrimaryPOS(
        displayType: EntryDisplayType,
        detected: [DetectedPOS],
        lemmas: EntryLemmas
    ) -> EntryPrimaryPOS {
        switch displayType {
        case .singleWord:
            if lemmas.verbs.count == 1      { return .verb }
            if lemmas.nouns.count == 1      { return .noun }
            if lemmas.adjectives.count == 1 { return .adjective }
            if lemmas.adverbs.count == 1    { return .adverb }
            return .unknown
        case .phrase:    return .phrase
        case .sentence:  return .sentence
        case .unknown:   return .unknown
        }
    }
}

// MARK: - Service C: Listen-Statistik

enum FrenchListStatisticsAggregator {

    /// Baut die Listen-Statistik aus vorberechneten Analyse-Ergebnissen.
    /// `low`-Confidence fliesst standardmässig NICHT mit ein.
    /// Wiederholte Lemmata werden nur einmal gezählt (Set-basierte Dedup).
    static func build(
        from results: [EntryAnalysisResult],
        minimumConfidence: AnalysisConfidence = .medium
    ) -> ListPOSStatistics {
        var verbSet = Set<String>()
        var nounSet = Set<String>()
        var adjSet = Set<String>()
        var advSet = Set<String>()
        var interjectionSet = Set<String>()

        for r in results where r.analysisConfidence >= minimumConfidence {
            verbSet.formUnion(r.lemmas.verbs)
            nounSet.formUnion(r.lemmas.nouns)
            adjSet.formUnion(r.lemmas.adjectives)
            advSet.formUnion(r.lemmas.adverbs)
            // SpecialCategory (interjection/presentationWord/particle/formulaic)
            // separat aggregieren — NICHT in Haupt-POS einrechnen.
            if r.specialCategory != nil, !r.normalizedText.isEmpty {
                interjectionSet.insert(r.normalizedText)
            }
        }

        return ListPOSStatistics(
            entryCount: results.count,
            uniqueVerbCount: verbSet.count,
            uniqueNounCount: nounSet.count,
            uniqueAdjectiveCount: adjSet.count,
            uniqueAdverbCount: advSet.count,
            uniqueInterjectionCount: interjectionSet.count,
            verbLemmas: verbSet.sorted(),
            nounLemmas: nounSet.sorted(),
            adjectiveLemmas: adjSet.sorted(),
            adverbLemmas: advSet.sorted(),
            interjectionLemmas: interjectionSet.sorted()
        )
    }

    // MARK: - Cached-Layer
    //
    // Analyse ist leichtgewichtig, wird aber pro Rendering häufig aufgerufen.
    // Diese Caches vermeiden Mehrfacharbeit bei identischen Inputs.
    //
    // Die `cacheVersion` ist Teil jedes Cache-Keys — JEDE inhaltliche Änderung
    // an der Analyse (neue Sonderfälle, Slash-Varianten, Overrides, Lemma-Regeln …)
    // MUSS diese Zahl hochzählen, damit alte In-Memory-Cache-Einträge nicht
    // falsche Ergebnisse liefern.
    private static let cacheVersion = "v12"

    private static let resultCacheLock = NSLock()
    private static var resultCache: [String: EntryAnalysisResult] = [:]
    private static var listCache: [Int: ListPOSStatistics] = [:]

    /// Analysiert einen Eintrag mit Cache.
    static func cachedAnalyze(_ text: String, mode: AnalysisMode = .balanced) -> EntryAnalysisResult {
        let key = "\(cacheVersion)|\(mode)|\(text)"
        resultCacheLock.lock()
        if let cached = resultCache[key] {
            resultCacheLock.unlock()
            return cached
        }
        resultCacheLock.unlock()

        let result = FrenchEntryAnalyzer.analyze(text, mode: mode)

        resultCacheLock.lock()
        if resultCache.count > 5000 { resultCache.removeAll(keepingCapacity: true) }
        resultCache[key] = result
        resultCacheLock.unlock()
        return result
    }

    /// Baut die Statistik für eine Liste mit Caching über alle Einträge.
    static func cachedStatistics(
        for items: [VocabularyItem],
        mode: AnalysisMode = .balanced,
        minimumConfidence: AnalysisConfidence = .medium
    ) -> ListPOSStatistics {
        guard !items.isEmpty else { return .empty }

        // Stabiler Key: item-IDs (ändern sich wenn Liste bearbeitet wird)
        var hasher = Hasher()
        for item in items {
            hasher.combine(item.id)
        }
        hasher.combine(mode)
        hasher.combine(minimumConfidence)
        let key = hasher.finalize()

        resultCacheLock.lock()
        if let cached = listCache[key] {
            resultCacheLock.unlock()
            return cached
        }
        resultCacheLock.unlock()

        let results = items.map { cachedAnalyze($0.french, mode: mode) }
        let stats = build(from: results, minimumConfidence: minimumConfidence)

        resultCacheLock.lock()
        if listCache.count > 200 { listCache.removeAll(keepingCapacity: true) }
        listCache[key] = stats
        resultCacheLock.unlock()
        return stats
    }

    /// Cache leeren — z. B. wenn Listen geändert werden oder DB neu geladen wird.
    static func invalidateCaches() {
        resultCacheLock.lock()
        resultCache.removeAll(keepingCapacity: true)
        listCache.removeAll(keepingCapacity: true)
        resultCacheLock.unlock()
    }
}

// MARK: - Service D: UI-Formatter

enum FrenchLemmaFormatter {

    /// Label-Text für die Anzeige — „Verb: savoir" wenn ein Verb-Lemma da ist.
    /// Kompaktes Format, damit rechts mehr Platz für den Wortart-Badge bleibt.
    /// Unterdrückt die Anzeige, wenn das Lemma identisch mit dem Eintrag selbst ist
    /// (z. B. „manger" → kein Hint).
    static func makeLemmaHint(from result: EntryAnalysisResult) -> String? {
        guard result.showLemmaHint, let hint = result.lemmaHintText, !hint.isEmpty else {
            return nil
        }
        if hint.lowercased() == result.normalizedText.lowercased() { return nil }
        return "Verb: \(hint)"
    }

    /// Zentrale deutsche Bezeichnung für die Wortart eines Items — nutzt
    /// die gesamte Analyzer-Pipeline inkl. Fallback auf DB-Wortart
    /// (Pronomen, Präposition, Konjunktion, Interjektion, Phrase, …).
    ///
    /// WICHTIG: Das Lemma wird hier NICHT angehängt (auch nicht bei Verben).
    /// Für den Infinitiv-Suffix bei Verben (grün, separat dargestellt):
    /// siehe `verbLemmaSuffix(for:)`.
    ///
    /// Rückgabe-Beispiele:
    ///   „Verb", „Nomen", „Adjektiv", „Adverb", „Phrase", „Satz",
    ///   „Pronomen", „Präposition", „Konjunktion", „Interjektion", „Artikel", „Zahl"
    static func wordClassLabel(for item: VocabularyItem) -> String {
        // User-Override gewinnt immer
        if let stored = item.wordClass, !stored.isEmpty {
            return germanWordClassName(stored)
        }

        let result = FrenchListStatisticsAggregator.cachedAnalyze(item.french)

        // Sonderkategorie (voilà, merci, bonjour …) schlägt primaryPos.
        if let special = result.specialCategory {
            return germanSpecialCategoryName(special)
        }

        switch result.primaryPos {
        case .verb:      return "Verb"
        case .noun:      return "Nomen"
        case .adjective: return "Adjektiv"
        case .adverb:    return "Adverb"
        case .phrase:    return "Phrase"
        case .sentence:  return "Phrase"  // „Satz" nie anzeigen — alles als Phrase
        case .unknown:
            if let direct = result.directWordClass, !direct.isEmpty {
                return germanWordClassName(direct)
            }
            return item.cardType == .phrases ? "Phrase" : "Wort"
        }
    }

    // MARK: - Display-Formatter (anzeigefertige Texte für Listen / Cards)

    /// Französisch display-ready aus Roh-Strings — gleiche Logik wie für VocabularyItem.
    /// Wird vom Lexikon-Display genutzt, damit Nomen immer einen Artikel haben.
    /// `gender` (m/f/pl) hilft beim Artikel-Wahl, sonst Heuristik.
    static func displayFrenchRaw(_ text: String, isNoun: Bool, gender: String? = nil) -> String {
        let base = TextNormalizationEngine.normalize(text, language: .french)
        guard isNoun, !base.isEmpty else { return base }
        let lower = base.lowercased()
        let existingArticles = ["le ", "la ", "les ", "l'", "l\u{2019}", "un ", "une ", "des ", "du ", "de la ", "de l'"]
        for prefix in existingArticles where lower.hasPrefix(prefix) {
            return base
        }
        let elisionVowels: Set<Character> = ["a", "e", "i", "o", "u", "h",
                                              "\u{00E0}", "\u{00E2}", "\u{00E4}",
                                              "\u{00E9}", "\u{00E8}", "\u{00EA}", "\u{00EB}",
                                              "\u{00EE}", "\u{00EF}",
                                              "\u{00F4}", "\u{00F6}",
                                              "\u{00F9}", "\u{00FB}", "\u{00FC}"]
        let article: String
        switch gender?.lowercased() {
        case "m": article = "le"
        case "f": article = "la"
        case "pl": article = "les"
        default:
            // Ohne Gender: heuristisch raten
            article = "le"
        }
        if (article == "le" || article == "la"),
           let first = base.first, elisionVowels.contains(Character(first.lowercased())) {
            return "l'\(base)"
        }
        return "\(article) \(base)"
    }

    /// Deutsch display-ready aus Roh-Strings — bei Nomen wird ersten Buchstaben groß.
    /// Wird vom Lexikon-Display genutzt, damit „auto" korrekt als „Auto" erscheint.
    static func displayGermanRaw(_ text: String, isNoun: Bool) -> String {
        let base = TextNormalizationEngine.normalize(text, language: .german)
        guard isNoun, !base.isEmpty else { return base }
        if let first = base.first, first.isUppercase { return base }
        return base.prefix(1).uppercased() + base.dropFirst()
    }

    /// Französischer Eintrag display-ready — ergänzt automatisch den passenden
    /// Artikel (le/la/l'/les) bei Einzelwort-Nomen, falls noch keiner da ist.
    /// Bei Phrasen/Verben etc. unverändert die regulären Casing-Regeln anwenden.
    static func displayFrench(for item: VocabularyItem) -> String {
        let base = TextCasingRules.applyFrench(item.french)

        // Nur bei Nomen und Einzelwort-Ausdrücken Artikel ergänzen
        let result = FrenchListStatisticsAggregator.cachedAnalyze(item.french)
        let storedIsNoun = (item.wordClass?.lowercased() == "noun")
        let resolvedIsNoun = (result.primaryPos == .noun)
        guard storedIsNoun || resolvedIsNoun else { return base }
        guard result.displayType == .singleWord else { return base }

        // Artikel bereits vorhanden?
        let lower = base.lowercased()
        let existingArticles = ["le ", "la ", "les ", "l'", "l\u{2019}", "un ", "une ", "des ", "du ", "de la ", "de l'"]
        for prefix in existingArticles where lower.hasPrefix(prefix) {
            return base
        }

        // Gender ermitteln (DB-Gender zuerst, sonst Heuristik via Lexikon-Utilities)
        guard let article = frenchArticle(forNoun: base, item: item) else { return base }

        // Vokal / stummes h → „l'"
        let firstChar = base.unicodeScalars.first ?? UnicodeScalar(0)
        let elisionVowels: Set<Character> = ["a", "e", "i", "o", "u", "h",
                                              "\u{00E0}", "\u{00E2}", "\u{00E4}",
                                              "\u{00E9}", "\u{00E8}", "\u{00EA}", "\u{00EB}",
                                              "\u{00EE}", "\u{00EF}",
                                              "\u{00F4}", "\u{00F6}",
                                              "\u{00F9}", "\u{00FB}", "\u{00FC}"]
        _ = firstChar
        if (article == "le" || article == "la"),
           let first = base.first, elisionVowels.contains(Character(first.lowercased())) {
            return "l'\(base)"
        }
        return "\(article) \(base)"
    }

    /// Deutscher Eintrag display-ready — bei Nomen wird der erste Buchstabe
    /// großgeschrieben, falls noch nicht. Nutzt TextCasingRules als Basis
    /// und wendet für Nomen-Einträge einen zusätzlichen Capitalize-Step an.
    static func displayGerman(for item: VocabularyItem) -> String {
        let base = TextCasingRules.applyGerman(item.german, sourceHint: item.french)
        guard !base.isEmpty else { return base }

        // Erste Zeichen schon gross? → fertig
        if let first = base.first, first.isUppercase { return base }

        // Nomen? → ersten Buchstaben großschreiben
        let result = FrenchListStatisticsAggregator.cachedAnalyze(item.french)
        let storedIsNoun = (item.wordClass?.lowercased() == "noun")
        let resolvedIsNoun = (result.primaryPos == .noun)
        guard storedIsNoun || resolvedIsNoun else { return base }

        return base.prefix(1).uppercased() + base.dropFirst()
    }

    /// Französischer Eintrag display-ready **mit Genus-Annotation**.
    ///
    /// Unterschied zu `displayFrench(for:)`:
    ///   • Bei Nomen wird hinter dem Eintrag das Genus in Klammern
    ///     gesetzt — „le muesli (m)", „la maison (f)", „das Haus (n)".
    ///   • Wenn der Eintrag als Plural gespeichert ist und wir eine
    ///     eindeutige Singularform rekonstruieren können (über
    ///     Suffix-Regeln + DB-Verifikation), zeigen wir statt
    ///     „les grains (pl)" die Singularform „le grain (m)" — das
    ///     ist didaktisch wertvoller beim Vokabeln lernen.
    ///
    /// Für Nicht-Nomen (Verben, Adjektive, Phrasen) identisch mit
    /// `displayFrench(for:)`.
    static func displayFrenchWithGender(for item: VocabularyItem) -> String {
        let result = FrenchListStatisticsAggregator.cachedAnalyze(item.french)
        let storedIsNoun = (item.wordClass?.lowercased() == "noun")
        let resolvedIsNoun = (result.primaryPos == .noun)
        guard storedIsNoun || resolvedIsNoun else { return displayFrench(for: item) }

        // Singleword + kurze Noun-Phrases (Determiner + Nomen) sind
        // beide gültige Targets für Artikel-/Genus-Anreicherung.
        // Vorher galt strikt `displayType == .singleWord` — das hat
        // „mon ami", „une voiture", „le chat" etc. ausgeschlossen,
        // weil das technisch 2-3 Wörter sind.
        let allowedForAnnotation: Bool = {
            if result.displayType == .singleWord { return true }
            // Kurze Phrasen (2-3 Wörter), die wie ein Nomen behandelt
            // werden. Trennwort muss typisch ein Determiner sein.
            let words = item.french.split(separator: " ")
            if words.count <= 3,
               storedIsNoun || resolvedIsNoun {
                return true
            }
            return false
        }()
        guard allowedForAnnotation else { return displayFrench(for: item) }

        // Rohe Basis ohne Artikel.
        let raw = TextCasingRules.applyFrench(item.french)
        let stripped = strippingLeadingFrenchArticle(from: raw)
        guard !stripped.isEmpty else { return displayFrench(for: item) }

        // Singular-Rekonstruktion: nur wenn
        //   1. der Eintrag mit „les " beginnt ODER
        //   2. Suffix-Regel erkennt Plural UND DB kennt eine
        //      plausible Singularform.
        let (displayBase, genderLetter) = resolveSingularFormAndGender(
            rawWithArticle: raw,
            bare: stripped,
            item: item
        )

        // Artikel bestimmen (auf dem potenziell singularisierten Base).
        let article: String = {
            switch genderLetter {
            case "m": return "le"
            case "f": return "la"
            case "pl": return "les"
            default:  return "le" // Fallback — sollte selten greifen
            }
        }()

        // Elision („l'école", „l'hôtel").
        let elisionVowels: Set<Character> = ["a", "e", "i", "o", "u", "h",
                                              "\u{00E0}", "\u{00E2}", "\u{00E4}",
                                              "\u{00E9}", "\u{00E8}", "\u{00EA}", "\u{00EB}",
                                              "\u{00EE}", "\u{00EF}",
                                              "\u{00F4}", "\u{00F6}",
                                              "\u{00F9}", "\u{00FB}", "\u{00FC}"]
        let withArticle: String = {
            if (article == "le" || article == "la"),
               let first = displayBase.first,
               elisionVowels.contains(Character(first.lowercased())) {
                return "l'\(displayBase)"
            }
            return "\(article) \(displayBase)"
        }()

        // Annotation: (m) / (f) / (n) / (pl). Leeres Gender → keine
        // Annotation, statt eines leeren Klammer-Paars.
        if let g = genderLetter, !g.isEmpty {
            return "\(withArticle) (\(g))"
        }
        return withArticle
    }

    /// Versuch, eine Singularform zu rekonstruieren — und dabei
    /// gleichzeitig das Genus zu ermitteln.
    ///
    /// Rückgabe: (Display-Base, Gender-Letter). Display-Base ist
    /// entweder die singularisierte Form (wenn DB-verifiziert) oder
    /// die ursprüngliche Base.
    private static func resolveSingularFormAndGender(
        rawWithArticle: String,
        bare: String,
        item: VocabularyItem
    ) -> (display: String, gender: String?) {
        let lower = rawWithArticle.lowercased()
        let explicitlyPlural = lower.hasPrefix("les ") || lower.hasPrefix("des ")

        // 1) Direkter DB-Lookup auf Original — wenn Gender nicht „pl"
        //    ist, ist das Ding schon Singular. Kein Singularisieren
        //    nötig.
        if let directGender = SupplementalFreeDictLexicon.sourceOnlyGender(for: item.french),
           directGender != "pl" {
            return (bare, directGender)
        }

        // 2) Wenn der Eintrag offensichtlich Plural ist oder die
        //    DB „pl" sagt, versuchen wir zu singularisieren.
        let dbSaysPlural = (SupplementalFreeDictLexicon.sourceOnlyGender(for: item.french) == "pl")
        if explicitlyPlural || dbSaysPlural,
           let candidate = naiveSingularizeFrenchNoun(bare) {
            // Verifizieren: existiert die Singularform in der DB?
            if let verifiedGender = SupplementalFreeDictLexicon.sourceOnlyGender(for: candidate),
               verifiedGender != "pl" {
                return (candidate, verifiedGender)
            }
            // DB kennt den Kandidaten nicht → Heuristik-Gender
            if let info = frenchGenderInfo(for: candidate, cardType: .words) {
                switch info.gender {
                case .masculine: return (candidate, "m")
                case .feminine:  return (candidate, "f")
                case .neuter:    return (candidate, "n")
                case .plural:    break
                }
            }
            // Keine Bestätigung — Singularform trotzdem anzeigen, aber
            // ohne zuverlässiges Gender.
            return (candidate, nil)
        }

        // 3) Fallback: Original behalten. Gender via Heuristik.
        if let info = frenchGenderInfo(for: bare, cardType: .words) {
            switch info.gender {
            case .masculine: return (bare, "m")
            case .feminine:  return (bare, "f")
            case .neuter:    return (bare, "n")
            case .plural:    return (bare, "pl")
            }
        }
        // Kein Gender-Hinweis verfügbar.
        return (bare, nil)
    }

    /// Suffix-Regeln für französische Pluralform → Singular.
    ///
    /// Reihenfolge ist wichtig (längste/spezifischste Endung zuerst):
    ///   • „eaux" → „eau"   (bateaux → bateau, gâteaux → gâteau)
    ///   • „aux"  → „al"    (journaux → journal, chevaux → cheval)
    ///   • „eux"  → „eu"    (neveux → neveu, cheveux → cheveu)
    ///   • „x"    → „"      (bijoux → bijou, cailloux → caillou)
    ///   • „s"    → „"      (grains → grain, tables → table)
    ///
    /// Kein „intelligenter" Fallback — wenn keine Regel greift,
    /// nil zurück. Der Caller verifiziert das Ergebnis mit der DB.
    static func naiveSingularizeFrenchNoun(_ plural: String) -> String? {
        guard plural.count >= 3 else { return nil }
        let lower = plural.lowercased()

        if lower.hasSuffix("eaux") {
            return String(plural.dropLast()) // „x" weg → „…eau"
        }
        if lower.hasSuffix("aux") {
            return String(plural.dropLast(3)) + "al"
        }
        if lower.hasSuffix("eux") {
            return String(plural.dropLast()) // „x" weg → „…eu"
        }
        if lower.hasSuffix("x") {
            return String(plural.dropLast())
        }
        if lower.hasSuffix("s") {
            return String(plural.dropLast())
        }
        return nil
    }

    /// Französischer Artikel für ein Nomen ermitteln — DB-Gender zuerst,
    /// dann Heuristiken (Suffix-Regeln, German-Artikel-Rückschluss).
    private static func frenchArticle(forNoun base: String, item: VocabularyItem) -> String? {
        // 1) DB-Gender (für lemma_fr)
        if let genderStr = SupplementalFreeDictLexicon.sourceOnlyGender(for: item.french) {
            switch genderStr {
            case "m": return "le"
            case "f": return "la"
            case "pl": return "les"
            default: break
            }
        }
        // 2) Heuristik: frenchGenderInfo liefert Gender-Info über Suffix-Regeln
        if let info = frenchGenderInfo(for: base, cardType: .words) {
            switch info.gender {
            case .masculine: return "le"
            case .feminine:  return "la"
            case .plural:    return "les"
            case .neuter:    return nil
            }
        }
        // 3) Fallback via deutsche Übersetzung (der/die/das → le/la/le)
        let germanLower = item.german.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if germanLower.hasPrefix("der ") { return "le" }
        if germanLower.hasPrefix("die ") { return "la" }
        if germanLower.hasPrefix("das ") { return "le" }
        return nil
    }

    // MARK: - Zentrale Label-Funktionen für ALLE Item-Typen
    //
    // Single Source of Truth — derselbe Pfad für:
    //   • VocabularyItem (App-Listen)
    //   • LexiconEntry (Wörterbuch)
    //   • Rohe Text-Eingaben (Scan-Import)
    //
    // Alle gehen durch FrenchEntryAnalyzer + diese zentralen Helpers.

    /// Wortart-Label für einen LexiconEntry — bevorzugt den DB-`word_class`-Wert
    /// und delegiert sonst an den Analyzer.
    static func wordClassLabel(forLexiconEntry entry: LexiconEntry) -> String {
        // 1) DB-wordClass hat Vorrang (Master ist Ground Truth)
        if let stored = entry.wordClass, !stored.isEmpty {
            return germanWordClassName(stored)
        }
        // 2) Analyzer auf French-Side
        return wordClassLabel(forFrenchText: entry.sourceTerm, isNounHint: entry.isGermanNoun)
    }

    /// Wortart-Label für rohen französischen Text (Scan-Import, ImportPreviewPair etc.).
    /// Optional `isNounHint`: wenn der Aufrufer schon weiss, dass es ein Nomen ist
    /// (z.B. via vorhandenem Artikel im DE-Original), schneller bestätigen.
    static func wordClassLabel(forFrenchText text: String, isNounHint: Bool = false) -> String {
        let result = FrenchListStatisticsAggregator.cachedAnalyze(text)

        if let special = result.specialCategory {
            return germanSpecialCategoryName(special)
        }
        switch result.primaryPos {
        case .verb:      return "Verb"
        case .noun:      return "Nomen"
        case .adjective: return "Adjektiv"
        case .adverb:    return "Adverb"
        case .phrase:    return "Phrase"
        case .sentence:  return "Phrase"
        case .unknown:
            if let direct = result.directWordClass, !direct.isEmpty {
                return germanWordClassName(direct)
            }
            if isNounHint { return "Nomen" }
            // Mehrwortig → wahrscheinlich Phrase
            if text.split(separator: " ").count > 1 { return "Phrase" }
            return "Wort"
        }
    }

    /// Roh-Wortart-String für einen LexiconEntry — bevorzugt DB-Wert, sonst Analyzer.
    /// Liefert "noun"/"verb"/"adjective"/"adverb"/"phrase"/... oder nil.
    static func rawWordClass(forLexiconEntry entry: LexiconEntry) -> String? {
        if let stored = entry.wordClass, !stored.isEmpty { return stored }
        let result = FrenchListStatisticsAggregator.cachedAnalyze(entry.sourceTerm)
        switch result.primaryPos {
        case .verb:      return "verb"
        case .noun:      return "noun"
        case .adjective: return "adjective"
        case .adverb:    return "adverb"
        case .phrase:    return "phrase"
        case .sentence:  return "phrase"
        case .unknown:   return result.directWordClass
        }
    }

    /// Französische Übersetzung eines deutschen Wortart-Labels (für FR-Anzeige im Lexikon).
    static func frenchLabel(forGermanLabel label: String) -> String {
        switch label {
        case "Nomen":         return "Nom"
        case "Verb":          return "Verbe"
        case "Adjektiv":      return "Adjectif"
        case "Adverb":        return "Adverbe"
        case "Pronomen":      return "Pronom"
        case "Pr\u{00E4}position": return "Pr\u{00E9}position"
        case "Konjunktion":   return "Conjonction"
        case "Interjektion":  return "Interjection"
        case "Pr\u{00E4}sentativ": return "Pr\u{00E9}sentatif"
        case "Partikel":      return "Particule"
        case "Wendung":       return "Expression"
        case "Phrase":        return "Expression"
        case "Artikel":       return "Article"
        case "Zahl":          return "Nombre"
        case "Wort":          return "Mot"
        default:              return label
        }
    }

    /// Deutsche Bezeichnung für eine Sonderkategorie.
    static func germanSpecialCategoryName(_ category: SpecialCategory) -> String {
        switch category {
        case .interjection:     return "Interjektion"
        case .presentationWord: return "Pr\u{00E4}sentativ"
        case .particle:         return "Partikel"
        case .formulaic:        return "Wendung"
        case .other:            return "Sonstiges"
        }
    }

    /// Infinitiv-Suffix NUR für Verben (nicht für Nomen, Adjektive etc.).
    /// Rückgabe: der Infinitiv ohne Klammern — z.\u{00A0}B. „savoir", „être".
    /// Wird in der UI separat dargestellt (anderer Farbton, etwas grössere Schrift).
    /// Unterdrückt bei Phrasen, weil der Lemma-Hint dort bereits hinter dem FR-Text steht.
    static func verbLemmaSuffix(for item: VocabularyItem) -> String? {
        if let stored = item.wordClass, !stored.isEmpty {
            // Nur wenn Nutzer explizit „verb" gesetzt hat und wir einen Infinitiv raten können
            guard stored.lowercased() == "verb" else { return nil }
        }
        let result = FrenchListStatisticsAggregator.cachedAnalyze(item.french)
        // Sonderkategorien haben kein Verb-Lemma.
        if result.specialCategory != nil { return nil }
        // Nur für Einzelwort-Verben — bei Phrasen steht das Lemma schon im Lemma-Hint.
        guard result.primaryPos == .verb else { return nil }
        guard let lemma = result.lemmas.verbs.first, !lemma.isEmpty else { return nil }
        // Wenn Eintrag selbst der Infinitiv ist, keinen doppelten Text anzeigen
        if lemma == result.normalizedText { return nil }
        return lemma
    }

    /// Deutsche Bezeichnung einer DB-Wortart.
    static func germanWordClassName(_ wc: String) -> String {
        switch wc {
        case "noun":         return "Nomen"
        case "verb":         return "Verb"
        case "adjective":    return "Adjektiv"
        case "adverb":       return "Adverb"
        case "preposition":  return "Pr\u{00E4}position"
        case "conjunction":  return "Konjunktion"
        case "pronoun":      return "Pronomen"
        case "interjection": return "Interjektion"
        case "article":      return "Artikel"
        case "number":       return "Zahl"
        case "numeral":      return "Zahl"
        case "phrase":       return "Phrase"
        case "determiner":   return "Determinator"
        case "":             return "Wort"
        default:
            // Unbekannte Wortart → Rohform mit großem Anfangsbuchstaben
            return wc.prefix(1).uppercased() + wc.dropFirst()
        }
    }

    /// Zentrale Verb-Akzentfarbe — gleich in Listen-Detailansicht UND Summary.
    static let verbAccentColor: Color = Color(hex: "#C4B5FD")

    /// Kompakte Breakdown-Zeile für Listenkarte: „3 Nomen · 2 Verben · 1 Adj. · 2 Interj."
    /// Zahl und Wort werden durch Non-Breaking-Space verbunden, damit Zeilenumbrüche
    /// nicht zwischen „3" und „Nomen" kommen.
    static func compactBreakdownLine(from stats: ListPOSStatistics) -> String {
        let nbsp = "\u{00A0}"
        var parts: [String] = []
        if stats.uniqueNounCount > 0         { parts.append("\(stats.uniqueNounCount)\(nbsp)Nomen") }
        if stats.uniqueVerbCount > 0         { parts.append("\(stats.uniqueVerbCount)\(nbsp)Verben") }
        if stats.uniqueAdjectiveCount > 0    { parts.append("\(stats.uniqueAdjectiveCount)\(nbsp)Adj.") }
        if stats.uniqueAdverbCount > 0       { parts.append("\(stats.uniqueAdverbCount)\(nbsp)Adverbien") }
        if stats.uniqueInterjectionCount > 0 { parts.append("\(stats.uniqueInterjectionCount)\(nbsp)Interj.") }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// Kompakte Breakdown-Zeile als AttributedString — „Verben"-Teil bekommt
    /// die zentrale Verb-Akzentfarbe (gleiches Lila wie in der Listen-Detailzeile).
    static func compactBreakdownAttributed(from stats: ListPOSStatistics) -> AttributedString {
        var out = AttributedString("")
        let dot = AttributedString(" \u{00B7} ")

        func append(_ text: String, color: Color? = nil) {
            if !out.characters.isEmpty { out += dot }
            var part = AttributedString(text)
            if let color { part.foregroundColor = color }
            out += part
        }

        if stats.uniqueNounCount > 0 {
            append("\(stats.uniqueNounCount) Nomen")
        }
        if stats.uniqueVerbCount > 0 {
            append("\(stats.uniqueVerbCount) Verben", color: verbAccentColor)
        }
        if stats.uniqueAdjectiveCount > 0 {
            append("\(stats.uniqueAdjectiveCount) Adj.")
        }
        if stats.uniqueAdverbCount > 0 {
            append("\(stats.uniqueAdverbCount) Adverbien")
        }
        if stats.uniqueInterjectionCount > 0 {
            append("\(stats.uniqueInterjectionCount) Interj.")
        }
        return out
    }

    /// Zwei-Zeilen-Variante für die Detail-Card. Interjektionen kommen auf Zeile 2.
    static func twoLineBreakdown(from stats: ListPOSStatistics) -> (line1: String, line2: String) {
        var l1: [String] = []
        if stats.uniqueNounCount > 0 { l1.append("\(stats.uniqueNounCount) Nomen") }
        if stats.uniqueVerbCount > 0 { l1.append("\(stats.uniqueVerbCount) Verben") }
        var l2: [String] = []
        if stats.uniqueAdjectiveCount > 0    { l2.append("\(stats.uniqueAdjectiveCount) Adjektive") }
        if stats.uniqueAdverbCount > 0       { l2.append("\(stats.uniqueAdverbCount) Adverbien") }
        if stats.uniqueInterjectionCount > 0 { l2.append("\(stats.uniqueInterjectionCount) Interjektionen") }
        return (
            l1.joined(separator: " \u{00B7} "),
            l2.joined(separator: " \u{00B7} ")
        )
    }

    /// AttributedString-Versionen der 2-Zeilen-Variante — „Verben" in Lila.
    static func twoLineBreakdownAttributed(from stats: ListPOSStatistics)
        -> (line1: AttributedString, line2: AttributedString) {
        var l1 = AttributedString("")
        var l2 = AttributedString("")
        let dot = AttributedString(" \u{00B7} ")

        func append(_ text: String, into target: inout AttributedString, color: Color? = nil) {
            if !target.characters.isEmpty { target += dot }
            var part = AttributedString(text)
            if let color { part.foregroundColor = color }
            target += part
        }

        if stats.uniqueNounCount > 0 {
            append("\(stats.uniqueNounCount) Nomen", into: &l1)
        }
        if stats.uniqueVerbCount > 0 {
            append("\(stats.uniqueVerbCount) Verben", into: &l1, color: verbAccentColor)
        }
        if stats.uniqueAdjectiveCount > 0 {
            append("\(stats.uniqueAdjectiveCount) Adjektive", into: &l2)
        }
        if stats.uniqueAdverbCount > 0 {
            append("\(stats.uniqueAdverbCount) Adverbien", into: &l2)
        }
        if stats.uniqueInterjectionCount > 0 {
            append("\(stats.uniqueInterjectionCount) Interjektionen", into: &l2)
        }
        return (l1, l2)
    }
}

// MARK: - Selbst-Tests (DEBUG)

#if DEBUG
enum FrenchLinguisticAnalysisSelfTest {
    static let didRun: Bool = {
        runTests()
        return true
    }()

    private struct Case {
        let input: String
        let expectedDisplayType: EntryDisplayType?
        let expectedVerbLemma: String?
        let expectedNounLemma: String?
        let expectedAdjLemma: String?
        let expectedAdvLemma: String?
        init(_ input: String,
             displayType: EntryDisplayType? = nil,
             verb: String? = nil,
             noun: String? = nil,
             adjective: String? = nil,
             adverb: String? = nil) {
            self.input = input
            self.expectedDisplayType = displayType
            self.expectedVerbLemma = verb
            self.expectedNounLemma = noun
            self.expectedAdjLemma = adjective
            self.expectedAdvLemma = adverb
        }
    }

    private static func runTests() {
        let cases: [Case] = [
            Case("la fille",            displayType: .singleWord, noun: "fille"),
            Case("des enfants",         displayType: .singleWord, noun: "enfant"),
            Case("je ne sais pas",      displayType: .phrase,     verb: "savoir"),
            Case("c\u{2019}est",        displayType: .phrase,     verb: "\u{00EA}tre"),
            Case("c'est",               displayType: .phrase,     verb: "\u{00EA}tre"),
            Case("ce sont",             displayType: .phrase,     verb: "\u{00EA}tre"),
            Case("je m\u{2019}appelle", displayType: .phrase,     verb: "appeler"),
            Case("je m'appelle",        displayType: .phrase,     verb: "appeler"),
            Case("tu t'appelles comment", displayType: .phrase,   verb: "appeler"),
            Case("petites",             displayType: .singleWord, adjective: "petit"),
            Case("vite",                displayType: .singleWord, adverb: "vite"),
            Case("ce sont mes amis",    displayType: .phrase,     verb: "\u{00EA}tre", noun: "ami"),
            // Reflexiv-Test: MUSS s'appeler / se présenter zurückgeben, NICHT die nicht-reflexiven Basis-Infinitive.
            Case("je m'appelle",          displayType: .phrase,    verb: "s'appeler"),
            Case("tu t'appelles",         displayType: .phrase,    verb: "s'appeler"),
            Case("il s'appelle marie",    displayType: .phrase,    verb: "s'appeler"),
            Case("je me pr\u{00E9}sente", displayType: .phrase,    verb: "se pr\u{00E9}senter")
        ]

        var failures: [String] = []
        for c in cases {
            let r = FrenchEntryAnalyzer.analyze(c.input)
            if let expected = c.expectedDisplayType, r.displayType != expected {
                failures.append("'\(c.input)': displayType=\(r.displayType.rawValue) expected=\(expected.rawValue)")
            }
            if let expected = c.expectedVerbLemma, !r.lemmas.verbs.contains(expected) {
                failures.append("'\(c.input)': verbs=\(r.lemmas.verbs) missing '\(expected)'")
            }
            if let expected = c.expectedNounLemma, !r.lemmas.nouns.contains(expected) {
                failures.append("'\(c.input)': nouns=\(r.lemmas.nouns) missing '\(expected)'")
            }
            if let expected = c.expectedAdjLemma, !r.lemmas.adjectives.contains(expected) {
                failures.append("'\(c.input)': adjectives=\(r.lemmas.adjectives) missing '\(expected)'")
            }
            if let expected = c.expectedAdvLemma, !r.lemmas.adverbs.contains(expected) {
                failures.append("'\(c.input)': adverbs=\(r.lemmas.adverbs) missing '\(expected)'")
            }
        }

        // Aggregation-Test
        let inputs = [
            "c'est", "ce sont", "je suis", "nous sommes",
            "je ne sais pas", "tu sais",
            "je m'appelle", "tu t'appelles comment"
        ]
        let results = inputs.map { FrenchEntryAnalyzer.analyze($0) }
        let stats = FrenchListStatisticsAggregator.build(from: results)
        if stats.uniqueVerbCount != 3 {
            failures.append("Aggregation uniqueVerbCount=\(stats.uniqueVerbCount) expected=3 lemmas=\(stats.verbLemmas)")
        }
        let expectedSet: Set<String> = ["\u{00EA}tre", "savoir", "appeler"]
        if Set(stats.verbLemmas) != expectedSet {
            failures.append("Aggregation verbLemmas=\(stats.verbLemmas) expected=\u{00EA}tre/savoir/appeler")
        }

        // Slash-Varianten: „le/la" → singleWord, Wortart = pronoun (via directWordClass)
        let leLa = FrenchEntryAnalyzer.analyze("le/la")
        if leLa.displayType != .singleWord {
            failures.append("'le/la': displayType=\(leLa.displayType.rawValue) expected=singleWord")
        }
        if leLa.directWordClass != "pronoun" {
            failures.append("'le/la': directWordClass=\(leLa.directWordClass ?? "nil") expected=pronoun")
        }
        let derDie = FrenchEntryAnalyzer.analyze("der/die")
        if derDie.displayType != .singleWord {
            failures.append("'der/die': displayType=\(derDie.displayType.rawValue) expected=singleWord")
        }

        // SpecialCategory-Tests: dürfen NICHT in ListPOSStatistics landen.
        let specials = ["voil\u{00E0}", "voici", "oui", "non", "merci", "bonjour", "bravo"]
        for s in specials {
            let r = FrenchEntryAnalyzer.analyze(s)
            if r.specialCategory == nil {
                failures.append("Special '\(s)': specialCategory=nil (erwartet gesetzt)")
            }
            if r.countsInMainPOSStats {
                failures.append("Special '\(s)': countsInMainPOSStats=true (darf nicht)")
            }
            if !r.lemmas.isEmpty {
                failures.append("Special '\(s)': lemmas=\(r.lemmas) (erwartet leer)")
            }
            if r.primaryPos != .unknown {
                failures.append("Special '\(s)': primaryPos=\(r.primaryPos.rawValue) (erwartet unknown)")
            }
        }
        // Aggregation darf Sonderwörter nicht mitzählen.
        let specialResults = specials.map { FrenchEntryAnalyzer.analyze($0) }
        let specialStats = FrenchListStatisticsAggregator.build(from: specialResults)
        if specialStats.uniqueVerbCount != 0 || specialStats.uniqueNounCount != 0
            || specialStats.uniqueAdjectiveCount != 0 || specialStats.uniqueAdverbCount != 0 {
            failures.append("Special-Aggregation hat Haupt-POS gezählt: \(specialStats)")
        }

        // CROSS-AREA-KONSISTENZ: Dieselben Eingaben müssen in allen drei Bereichen
        // (App-Listen, Wörterbuch, Scan-Import) dieselbe deutsche Wortart-Bezeichnung erhalten.
        // Ground Truth: FrenchLemmaFormatter.wordClassLabel(forFrenchText:).
        struct Expect { let input: String; let label: String }
        let crossArea: [Expect] = [
            Expect(input: "la fille",       label: "Nomen"),
            Expect(input: "des enfants",    label: "Nomen"),
            Expect(input: "vite",           label: "Adverb"),
            Expect(input: "petites",        label: "Adjektiv"),
            Expect(input: "voil\u{00E0}",   label: "Pr\u{00E4}sentativ"),
            Expect(input: "merci",          label: "Interjektion"),
            Expect(input: "je ne sais pas", label: "Phrase"),
            Expect(input: "je m'appelle",   label: "Phrase"),
            Expect(input: "c'est",          label: "Phrase")
        ]
        for c in crossArea {
            let label = FrenchLemmaFormatter.wordClassLabel(forFrenchText: c.input)
            if label != c.label {
                failures.append("Cross-Area '\(c.input)': label='\(label)' expected='\(c.label)'")
            }
        }

        if failures.isEmpty {
            print("\u{2705} [FrenchAnalysis] \(cases.count) Eintragstests + Aggregation bestanden")
        } else {
            print("\u{274C} [FrenchAnalysis] \(failures.count) Fehler:")
            for f in failures { print("    \(f)") }
        }
    }
}
#endif
