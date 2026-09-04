import Foundation

// MARK: - Zielobjekt

/// Vollständige Beschreibung eines Eintrags aus Sicht des **Artikel-Modus**.
/// Trennt drei Aspekte, die bislang im Code vermischt waren:
///   • die sichtbare Rohtext-Darstellung (`texteSourceVisible`),
///   • den didaktischen Lernkern (`noyauLexical`) — das Wort, das der User
///     lernen soll,
///   • die erwartete Antwort für die Artikel-Frage (`reponseAttendueArticle`).
///
/// Die Felder sind bewusst an die französische Spec angelehnt (User-Brief),
/// damit der Mapping-Aufwand zwischen Produkt- und Code-Ebene Null ist.
///
/// **Nur für den Artikel-Modus.** Der normale Karteikartenmodus und alle
/// anderen Trainings-Modi sind von diesem Klassifizierer ausgeschlossen
/// (siehe `TrainingSessionController+DictionarySelection.swift`, `.articles`-
/// Case — dort ist der einzige Integrations-Punkt).
struct ArticleExerciseTarget: Equatable {

    enum CategoriePrincipale: String, Codable, Equatable {
        case nom
        case autre
    }

    enum Genre: String, Codable, Equatable {
        case masculin
        case feminin
        case pluriel
        case indetermine
    }

    /// Sichtbarer Rohtext, so wie er aus dem Lexikon kommt. Wird **nicht**
    /// als Prompt im Artikel-Modus angezeigt — dafür existiert
    /// `noyauLexical`. Wir behalten das Original für Debug/Log + den
    /// Fallback-Fall, dass ein Eintrag doch angezeigt wird.
    let texteSourceVisible: String

    /// Lexikalischer Kern — genau das, was der User ergänzen soll. Bei
    /// „mon ami" ist der Kern „ami"; bei „la fille" ist der Kern „fille".
    /// Ohne Begleiter (pures Nomen) ist Kern == sichtbarer Text.
    let noyauLexical: String

    /// Lemma-Form. Für das MVP identisch mit `noyauLexical` — wir
    /// lemmatisieren nicht aktiv (kein Morpho-Analyzer im Projekt). Plural
    /// wird erkannt, aber nicht zurück auf Singular-Stamm normalisiert.
    let lemme: String

    /// Hauptwortart. Der Classifier lässt **nur** Nomen zu; alles andere
    /// (Adjektiv, Adverb, Verb, Interjektion, „comment", „bonjour" …) ist
    /// für den Artikel-Modus ungültig (`estValidePourExerciceArticle = false`).
    let categoriePrincipale: CategoriePrincipale

    /// Genus (inkl. Plural als eigene Kategorie). `.indetermine` nur, wenn
    /// weder Lexikon noch Deutsch-Fallback eine Aussage erlauben — in dem
    /// Fall ist der Eintrag auch nicht für den Artikel-Modus geeignet.
    let genre: Genre

    /// Ja, wenn das Wort mit Vokal oder stillem h beginnt — relevant für
    /// die Elision `l'`. Wird explizit als Feld ausgegeben, weil die UI
    /// (Accessibility, spätere Erklärung) darauf zugreifen könnte.
    let commenceParVoyelleOuHMuet: Bool

    /// Der Artikel, den der User **im Artikel-Modus** antworten soll. Genau
    /// einer von `"le" | "la" | "l'" | "les"`. `nil` wenn der Eintrag
    /// ungültig ist.
    let reponseAttendueArticle: String?

    /// Gatekeeper: Nur Einträge mit `true` dürfen im Artikel-Modus gestellt
    /// werden. `false` deckt alle Ausschlussfälle ab (reine Artikel,
    /// Possessiv-Phrasen ohne erkennbaren Kern, Nicht-Nomen, fehlendes
    /// Genus).
    let estValidePourExerciceArticle: Bool

    /// Debug-Begründung — warum der Eintrag valid/invalid ist. Hilft beim
    /// Analysieren, warum von N erkannten Nomen nur M im Artikel-Modus
    /// landen. In Release-Builds informativ, nicht UI-kritisch.
    let rejectionReason: RejectionReason

    enum RejectionReason: String, Codable, Equatable {
        case acceptedViaExistingNounCategory  = "accepté via catégorie nom existante"
        case acceptedViaExtractedCore          = "accepté via noyau extrait"
        case acceptedViaLeadingMarker          = "accepté via marqueur (article/possessif/démonstratif)"
        case rejectedPureArticle               = "rejeté car article pur"
        case rejectedPhraseCardType            = "rejeté car type 'phrases'"
        case rejectedEmpty                     = "rejeté car entrée vide"
        case rejectedNoNominalCore             = "rejeté car pas de noyau nominal"
        case rejectedNotNoun                   = "rejeté car pas un nom"
        case rejectedIndeterminateGender       = "rejeté car genre indéterminé"
    }
}

// MARK: - Classifier

/// Single-Source-of-Truth für die Artikel-Modus-Eignung + den Lernkern-
/// Extraktions-Schritt. Jeder Flow im Artikel-Modus (Item-Filter, Prompt,
/// erwartete Antwort) läuft über `classify(_:)` — damit gibt es keine
/// Divergenz zwischen „was wird gezeigt" und „was wird erwartet".
enum ArticleModeClassifier {

    // MARK: Stop-Listen

    /// Reine Artikel als Einzel-Token. Werden sie als `sourceDisplay`
    /// geliefert, ist der Eintrag nicht abfragbar — „welcher Artikel
    /// gehört zu 'le'?" ist nonsense. Deckt die bisherigen
    /// `isPureFrenchArticle`-Fälle plus einige Ergänzungen ab (`au`,
    /// `aux`, Präposition+Artikel-Kombos).
    private static let pureArticleTokens: Set<String> = [
        "le", "la", "l'", "les",
        "un", "une", "des", "du",
        "au", "aux",
        "de la", "de l'",
        "à la", "à l'",
    ]

    /// Possessivbegleiter (erstes Token). „mon ami" → Kern ist „ami".
    /// Wenn der Eintrag NUR aus einem Possessiv besteht, ist er
    /// automatisch ungültig.
    private static let possessivePronouns: Set<String> = [
        "mon", "ma", "mes",
        "ton", "ta", "tes",
        "son", "sa", "ses",
        "notre", "nos",
        "votre", "vos",
        "leur", "leurs",
    ]

    /// Demonstrativbegleiter — analog zu Possessiven: „ce chien" → „chien".
    private static let demonstrativePronouns: Set<String> = [
        "ce", "cet", "cette", "ces",
    ]

    /// Bestimmte + unbestimmte Singular-Artikel als 1. Token. Werden vom
    /// Lernkern abgetrennt; das Ergebnis ist der Kern. `les` wird separat
    /// behandelt (Plural-Signal).
    private static let singularLeadingArticles: Set<String> = [
        "le", "la", "l'", "un", "une", "du",
    ]

    /// Vokale (inkl. akzentuierter Varianten) UND `h` (geht als
    /// „potenziell stummes h" durch — die Elision greift bei allen
    /// h-Anfängen, die Unterscheidung h aspiré vs. h muet ist im MVP
    /// nicht modelliert). Das ist dieselbe Regel, die bisher in
    /// `determineFrenchArticle.needsElision` genutzt wurde.
    private static let vowelOrHMuetStarters: Set<Character> = [
        "a", "e", "i", "o", "u", "y",
        "â", "ê", "î", "ô", "û",
        "é", "è", "ë", "ï", "ü",
        "à", "ù",
        "h",
    ]

    // MARK: Public API

    /// Einziger offizieller Einstiegspunkt. Gibt das vollständige Zielobjekt
    /// zurück — Call-Sites dürfen niemals den Raw-Text selbst interpretieren,
    /// sondern lesen `noyauLexical` (für den Prompt) bzw.
    /// `reponseAttendueArticle` (für die erwartete Antwort).
    static func classify(_ item: VocabularyItem) -> ArticleExerciseTarget {
        let raw = item.french.trimmingCharacters(in: .whitespacesAndNewlines)

        // Ausschluss 0: leere / whitespace-Einträge
        guard !raw.isEmpty else {
            return invalidTarget(raw: raw, core: raw, reason: .rejectedEmpty)
        }

        // Ausschluss 1: Phrasen — der Artikel-Modus trainiert Nomen, keine
        // zusammenhängenden Mehrwort-Aussagen („Bonjour !", „Comment ça va?").
        if item.cardType == .phrases {
            return invalidTarget(raw: raw, core: raw, reason: .rejectedPhraseCardType)
        }

        // Ausschluss 2: reine Artikel / Artikelpaare („le", „la / le" …).
        if isPureArticleOrPair(raw) {
            return invalidTarget(raw: raw, core: raw, reason: .rejectedPureArticle)
        }

        // 3. Lernkern extrahieren — eventuell vorhandene Begleiter (Artikel,
        //    Possessivpronomen, Demonstrativpronomen) abtrennen. Der
        //    Begleiter liefert ggf. direkt ein Genus-Signal (`impliedGender`).
        let coreExtraction = extractCore(from: raw)
        let core = coreExtraction.core

        guard !core.isEmpty else {
            return invalidTarget(raw: raw, core: raw, reason: .rejectedNoNominalCore)
        }

        // Ausschluss 4: Kern ist selbst nur ein Artikel/Pronomen.
        if isPureArticleOrPair(core) || possessivePronouns.contains(core.lowercased()) {
            return invalidTarget(raw: raw, core: core, reason: .rejectedNoNominalCore)
        }

        // 5. Nominalitäts-Check — **gelockert** gegenüber der ersten
        //    Version. Drei Wege, einen Eintrag als nominal zu akzeptieren:
        //
        //    (a) Die **Liste selbst** hat das Item als „noun" markiert
        //        (`item.wordClass` oder `resolvedWordClass(forItem:)`).
        //        User-Regel: „Wenn ein Eintrag in der Liste bereits
        //        korrekt als Nomen erkannt wurde, darf er im Artikel-
        //        Modus nicht verloren gehen." Stärkste Quelle.
        //    (b) Der **Kern** steht im Master-Lexikon als „noun"
        //        (`wordClass(for: core)`). Rettet Einträge wie
        //        „l'école" oder „mon ami", wenn das Item selbst keine
        //        Wortart-Info hat, der Kern aber im Lexikon gelistet ist.
        //    (c) Ein **eindeutiger Begleiter-Marker** (Artikel / Possessiv /
        //        Demonstrativ) steht vor dem Kern **und** der Kern ist
        //        typographisch plausibel (keine Funktionswörter, keine
        //        reinen Artikel). Französisch: „mon/ma/mes/le/la/les/l'
        //        + X" impliziert sehr stark, dass X ein nominales
        //        Zielwort ist. Das ist die entscheidende Lockerung gegen
        //        „zu streng" — ohne diesen Pfad fielen Einträge ohne
        //        Lexikon-Hit bisher raus.
        //
        //    Ausschlussfälle sind in `isCoreLikelyNonNominal` gebündelt.
        let itemBaseWordClass = StandardVocabularyLoader.resolvedWordClass(forItem: item)
        let coreWordClass = StandardVocabularyLoader.wordClass(for: core)

        // Harter Veto (2026-08-06, Bug-Fix): Wenn der Kern selbst im
        // Master-Lexikon eindeutig als Nicht-Nomen geführt wird (allen
        // voran Adjektive), sticht das JEDE andere Nomen-Quelle — auch
        // ein `item.wordClass == "noun"`, das aus fehlerhaften
        // Scan-Import-/List-Daten stammen kann. User-Screenshot: „vide"
        // (Adjektiv, DB-bestätigt) erschien im Artikel-Modus mit
        // le/la/l'/les zur Auswahl — sinnlos, weil ein Adjektiv keinen
        // Artikel hat. Ohne diesen Veto gewann `listMarkedAsNoun` allein
        // durch ein falsch gesetztes Item-Flag.
        let knownNonNounCoreClasses: Set<String> = [
            "adjective", "adverb", "verb", "interjection",
            "pronoun", "preposition", "conjunction", "determiner", "numeral"
        ]
        if let coreClass = coreWordClass, knownNonNounCoreClasses.contains(coreClass) {
            return ArticleExerciseTarget(
                texteSourceVisible: raw,
                noyauLexical: core,
                lemme: core,
                categoriePrincipale: .autre,
                genre: .indetermine,
                commenceParVoyelleOuHMuet: false,
                reponseAttendueArticle: nil,
                estValidePourExerciceArticle: false,
                rejectionReason: .rejectedNotNoun
            )
        }

        let listMarkedAsNoun = itemBaseWordClass == "noun"
        let coreMarkedAsNoun = coreWordClass == "noun"
        let acceptedViaLeadingMarker = coreExtraction.leading != .none
            && !isCoreLikelyNonNominal(core: core, itemWordClass: itemBaseWordClass, coreWordClass: coreWordClass)

        let acceptReason: ArticleExerciseTarget.RejectionReason?
        if listMarkedAsNoun {
            acceptReason = .acceptedViaExistingNounCategory
        } else if coreMarkedAsNoun {
            acceptReason = .acceptedViaExtractedCore
        } else if acceptedViaLeadingMarker {
            acceptReason = .acceptedViaLeadingMarker
        } else {
            acceptReason = nil
        }

        guard let acceptReason else {
            // Kein Nomen-Signal aus keiner der drei Quellen → wirklich
            // kein Artikel-Modus-Kandidat (z. B. „comment" als Adverb).
            return ArticleExerciseTarget(
                texteSourceVisible: raw,
                noyauLexical: core,
                lemme: core,
                categoriePrincipale: .autre,
                genre: .indetermine,
                commenceParVoyelleOuHMuet: false,
                reponseAttendueArticle: nil,
                estValidePourExerciceArticle: false,
                rejectionReason: .rejectedNotNoun
            )
        }

        // 6. Genus auflösen. **Neu**: Priorität 0 ist der direkte
        //    Begleiter-Hinweis aus `extractCore` — „mon X" → masc., „ma X"
        //    → fem., „mes/les/des X" → pluriel. Damit sind viele Einträge
        //    schon vor dem ersten Lexikon-Lookup sicher klassifiziert.
        let genre = resolveGender(
            item: item,
            core: core,
            leadingSignal: coreExtraction.leading,
            impliedGender: coreExtraction.impliedGender
        )

        // 7. Vokal/h-muet-Flag bestimmen — basiert auf dem KERN, nicht dem
        //    Rohtext. „le ami" ist egal; relevant ist „ami" → Elision.
        let startsWithVowelOrH = startsWithVowelOrHMuet(core)

        // 8. Erwartete Antwort berechnen. Wenn Vokal/h-Anfang klar ist,
        //    können wir selbst bei unbestimmtem Genus die Elision „l'"
        //    zurückgeben (weil l' die Geschlechts-Ambiguität selbst
        //    auflöst). Das rettet Einträge wie „l'école" auch dann, wenn
        //    das Lexikon kein Genus zu „école" kennt.
        let reponse = expectedArticle(
            genre: genre,
            startsWithVowelOrH: startsWithVowelOrH,
            leadingSignal: coreExtraction.leading
        )

        // Wenn keine saubere Antwort berechnet werden kann → invalid.
        guard let reponse else {
            return ArticleExerciseTarget(
                texteSourceVisible: raw,
                noyauLexical: core,
                lemme: core,
                categoriePrincipale: .nom,
                genre: .indetermine,
                commenceParVoyelleOuHMuet: startsWithVowelOrH,
                reponseAttendueArticle: nil,
                estValidePourExerciceArticle: false,
                rejectionReason: .rejectedIndeterminateGender
            )
        }

        return ArticleExerciseTarget(
            texteSourceVisible: raw,
            noyauLexical: core,
            lemme: core,
            categoriePrincipale: .nom,
            genre: genre,
            commenceParVoyelleOuHMuet: startsWithVowelOrH,
            reponseAttendueArticle: reponse,
            estValidePourExerciceArticle: true,
            rejectionReason: acceptReason
        )
    }

    /// Conservative Negativ-Liste: Kerne, die wahrscheinlich **keine**
    /// Nomen sind — selbst wenn ein Begleiter davorsteht. Verhindert,
    /// dass „mon comment" oder „le très" durchrutscht, nur weil ein
    /// Begleiter davor steht. Wenn `itemWordClass` oder `coreWordClass`
    /// bereits einen Nicht-Noun-Wert nennen (Verb, Adverb, Interjektion,
    /// Pronoun, Präposition, Konjunktion), zählt das als harter Stop.
    private static func isCoreLikelyNonNominal(
        core: String,
        itemWordClass: String?,
        coreWordClass: String?
    ) -> Bool {
        let knownNonNoun: Set<String> = [
            "adverb", "verb", "interjection",
            "pronoun", "preposition", "conjunction",
            "determiner", "numeral",
        ]
        if let item = itemWordClass, knownNonNoun.contains(item) { return true }
        if let coreClass = coreWordClass, knownNonNoun.contains(coreClass) { return true }

        // Sehr kurze Kerne ohne Lexikon-Hit sind wahrscheinlich
        // Fragmente oder Tippfehler → conservativ aussortieren. (Ein
        // gültiges Nomen unter 2 Zeichen ist in der App nicht realistisch.)
        if core.count < 2 { return true }

        return false
    }

    // MARK: - Private Helpers

    /// Genau dann `true`, wenn `raw` **ausschließlich** aus Artikeln besteht —
    /// sowohl Einzel-Tokens („le", „la") als auch Slash-/Pipe-Kombinationen
    /// („le / la", „un|une"). Das deckt die Testfälle 1–3 aus dem User-Brief
    /// ab.
    private static func isPureArticleOrPair(_ raw: String) -> Bool {
        let lower = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty else { return false }

        if pureArticleTokens.contains(lower) { return true }

        // Mehrteilige Tokens mit „/" oder „|" als Trenner.
        let separators = CharacterSet(charactersIn: "/|,")
        let parts = lower
            .components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { pureArticleTokens.contains($0) }
    }

    /// Ergebnis der Lernkern-Extraktion: der nominale Kern plus ggf.
    /// ein implizites Genus-Signal, das aus dem Begleiter abgeleitet
    /// werden kann. `mon` ist maskulin-Singular, `ma` feminin-Singular,
    /// `mes` Plural — solche Begleiter sind extrem zuverlässige Genus-
    /// Hinweise und dürfen direkt in die Pipeline fließen.
    private struct CoreExtraction {
        let core: String
        let leading: LeadingSignal
        /// Genus, das der Begleiter impliziert (falls eindeutig).
        /// `nil` bei:
        ///   • Elision `l'` (masc. oder fem. — nicht unterscheidbar),
        ///   • geschlechts-invariante Possessive (`notre`, `votre`,
        ///     `leur`), wo Singular m./f. offen ist.
        /// In diesen Fällen muss das Genus über die Lexikon-Pipeline
        /// aufgelöst werden.
        let impliedGender: ArticleExerciseTarget.Genre?
    }

    /// Strippt einen führenden Begleiter (Artikel, Possessiv oder
    /// Demonstrativ) und liefert den Kern + das erkannte Signal.
    /// Wichtig: der **Begleiter selbst** ist bereits ein Genus-Signal
    /// (mon → masc, ma → fem, mes → plur, le → masc, la → fem, les → plur
    /// usw.) — dieses Signal wird im `impliedGender` mitgeliefert und
    /// rettet Einträge, deren Kern nicht explizit im Lexikon steht.
    private static func extractCore(from raw: String) -> CoreExtraction {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        // Elision-Fall: „l'ami" → „ami" (ohne Leerzeichen). Genus
        // unklar (masc ODER fem), aber Elision-Flag ist sicher. Wir
        // lassen `impliedGender = nil`; der Elision-Pfad sorgt dafür,
        // dass die Antwort „l'" lautet, auch ohne bekanntes Genus.
        if lower.hasPrefix("l'") {
            let core = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines)
            return CoreExtraction(core: core, leading: .articleSingular, impliedGender: nil)
        }

        // Standard-Fall: erstes Wort ist Begleiter, Rest ist Kern.
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard tokens.count >= 2 else {
            return CoreExtraction(core: trimmed, leading: .none, impliedGender: nil)
        }

        let first = tokens[0].lowercased()
        let remainder = tokens.dropFirst().joined(separator: " ")

        if first == "les" || first == "des" {
            return CoreExtraction(core: remainder, leading: .articlePlural, impliedGender: .pluriel)
        }
        if let impliedArticleGender = articleImpliedGender[first],
           singularLeadingArticles.contains(first) {
            return CoreExtraction(core: remainder, leading: .articleSingular, impliedGender: impliedArticleGender)
        }
        if singularLeadingArticles.contains(first) {
            // Artikel-Form ohne eindeutiges Genus (z. B. „du" kann
            // masculine-partitive sein, aber im Modus-Artikel wird das
            // kaum abgefragt). Wir lassen `impliedGender = nil`.
            return CoreExtraction(core: remainder, leading: .articleSingular, impliedGender: nil)
        }
        if possessivePronouns.contains(first) {
            return CoreExtraction(
                core: remainder,
                leading: .possessive,
                impliedGender: possessiveImpliedGender[first]
            )
        }
        if demonstrativePronouns.contains(first) {
            return CoreExtraction(
                core: remainder,
                leading: .demonstrative,
                impliedGender: demonstrativeImpliedGender[first]
            )
        }

        // Kein erkennbarer Begleiter → Rohtext bleibt Kern.
        return CoreExtraction(core: trimmed, leading: .none, impliedGender: nil)
    }

    private enum LeadingSignal {
        case none
        case articleSingular   // le, la, l', un, une, du
        case articlePlural     // les, des
        case possessive        // mon, ma, mes, …
        case demonstrative     // ce, cet, cette, ces
    }

    /// Direkte Genus-Ableitung aus bestimmten/unbestimmten Artikeln.
    /// `l'` fehlt bewusst — Elision-Artikel sind genus-ambig.
    private static let articleImpliedGender: [String: ArticleExerciseTarget.Genre] = [
        "le":  .masculin,
        "un":  .masculin,
        "la":  .feminin,
        "une": .feminin,
        // `du`, `au`, `aux` sind Präposition+Artikel-Kombinationen —
        // aus dem Singular-Fall reicht bei `du` der Maskulin-Hinweis,
        // bei `au`/`aux` selten als führender Marker. Conservative:
        // nur klar eindeutige Formen hier.
        "du":  .masculin,
    ]

    /// Possessiv-Pronomen → Genus. Die ge-gender-ten Formen (mon/ma,
    /// ton/ta, son/sa) sind eindeutig; notre/votre/leur sind Singular,
    /// aber genus-invariant → kein `impliedGender`. Die Plural-Formen
    /// (mes/tes/ses/nos/vos/leurs) sind alle Plural.
    private static let possessiveImpliedGender: [String: ArticleExerciseTarget.Genre] = [
        "mon": .masculin,
        "ton": .masculin,
        "son": .masculin,
        "ma":  .feminin,
        "ta":  .feminin,
        "sa":  .feminin,
        "mes":  .pluriel,
        "tes":  .pluriel,
        "ses":  .pluriel,
        "nos":  .pluriel,
        "vos":  .pluriel,
        "leurs": .pluriel,
        // notre / votre / leur → Singular aber genus-invariant → nicht hier.
    ]

    /// Demonstrativ-Pronomen → Genus.
    private static let demonstrativeImpliedGender: [String: ArticleExerciseTarget.Genre] = [
        "ce":     .masculin,
        "cet":    .masculin,   // Elision-Form vor Vokal/h
        "cette":  .feminin,
        "ces":    .pluriel,
    ]

    /// Prüft ob `core` mit einem Vokal oder `h` beginnt. Alles in einer
    /// Funktion, damit die Elision-Regel an genau einer Stelle lebt.
    ///
    /// **Mehrwort-Kerne**: Elision ist eine Nachbarschafts-Regel — sie
    /// hängt am Wort, das dem Artikel unmittelbar folgt, nicht am
    /// Kopf-Nomen der Phrase. Bei „le meilleur ami" (Artikel „le" bereits
    /// gestrippt, `core` = „meilleur ami") entscheidet „meilleur" (kein
    /// Vokal-Anlaut) — die richtige Antwort bleibt „le", nicht „l'". Wir
    /// nehmen daher das **erste** Token, wenn der Kern aus mehreren
    /// Wörtern besteht. Für Einwort-Kerne ändert sich nichts.
    ///
    /// **Codeaudit 2026-09-03, Stufe 1** — vorher stand hier `tokens.last`
    /// mit der gegenteiligen Begründung „das Kernwort, nicht das
    /// eingeschobene Adjektiv". Das ist keine Elisionsregel des
    /// Französischen: „le meilleur ami" bleibt unelidiert, obwohl „ami"
    /// mit Vokal beginnt — genau wie „l'meilleur ami" falsch wäre. Betraf
    /// 41 Nomen-Einträge, u. a. „la meilleure amie" (fälschlich „l'"),
    /// „la connexion internet" (fälschlich „l'" wegen „internet"),
    /// „le menu enfant" (fälschlich „l'" wegen „enfant").
    private static func startsWithVowelOrHMuet(_ core: String) -> Bool {
        let trimmed = core.trimmingCharacters(in: .whitespacesAndNewlines)
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })
        let relevant = (tokens.first.map(String.init) ?? trimmed).lowercased()
        guard let first = relevant.first else { return false }
        return vowelOrHMuetStarters.contains(first)
    }

    /// Berechnet die erwartete Antwort aus Genus + Vokal/h-Anfang +
    /// ggf. LeadingSignal (für Elision-Sonderfall).
    ///
    /// Regeln:
    ///   • Plural → `"les"` (auch bei Vokal-Anfang; Französisch hat
    ///     keine Elision im Plural).
    ///   • Vokal/h-muet-Anfang → `"l'"` (Elision schlägt Genus).
    ///   • Sonst maskulin → `"le"`, feminin → `"la"`.
    ///   • Bei unbestimmtem Genus **aber klarem Elision-Signal**
    ///     (`leadingSignal == .articleSingular` für „l'…" ODER
    ///     Kern beginnt mit Vokal/h) → trotzdem `"l'"` als Antwort.
    ///     Das rettet Einträge wie „l'école" / „l'histoire", wenn kein
    ///     Genus ableitbar ist.
    private static func expectedArticle(
        genre: ArticleExerciseTarget.Genre,
        startsWithVowelOrH: Bool,
        leadingSignal: LeadingSignal
    ) -> String? {
        if genre == .pluriel { return "les" }
        if startsWithVowelOrH { return "l'" }
        switch genre {
        case .masculin:    return "le"
        case .feminin:     return "la"
        case .pluriel:     return "les"
        case .indetermine:
            // Fallback für den Rest-Elision-Fall: der Rohtext begann
            // explizit mit `l'…`, aber der Kern startet nicht mit einem
            // Vokal (unwahrscheinlich im echten Französisch, aber hier
            // defensiv). Antwort trotzdem `"l'"`.
            if leadingSignal == .articleSingular && startsWithVowelOrH {
                return "l'"
            }
            return nil
        }
    }

    /// Genus-Auflösung — gestaffelt, stärkste Quellen zuerst. Liefert
    /// nur bei wirklich unbestimmbarem Genus `.indetermine`; der
    /// Gatekeeper verwirft den Eintrag dann. Die **Lockerung** gegenüber
    /// der ersten Version: der aus dem Begleiter abgeleitete `impliedGender`
    /// sitzt als Priorität 0 ganz oben — „mon X" → masc. direkt, ohne
    /// Lexikon-Lookup.
    private static func resolveGender(
        item: VocabularyItem,
        core: String,
        leadingSignal: LeadingSignal,
        impliedGender: ArticleExerciseTarget.Genre?
    ) -> ArticleExerciseTarget.Genre {
        // ─── Priorität 0: Begleiter-impliziertes Genus ──────────────
        // Französisch-grammatikalisch eindeutige Marker (mon/ma/mes,
        // le/la/les/un/une/des, ce/cet/cette/ces) verraten das Genus
        // unmittelbar. Stärkste Signal-Quelle — sitzt direkt im Rohtext.
        if let implied = impliedGender {
            return implied
        }

        // ─── Priorität 1: Rohtext-Signal „les …" ────────────────────
        // Sichtbarer Plural-Artikel ist die stärkste Aussage (redundant
        // zu Priorität 0 in den meisten Fällen, bleibt als Safety-Net).
        if leadingSignal == .articlePlural { return .pluriel }

        // ─── Priorität 1.5: Flexions-basierte Plural-Erkennung ──────
        // MUSS vor der `frenchGender`-Abfrage laufen: wenn das Lexikon
        // „amis" sowohl als eigenen Eintrag (mit maskulinem Genus-
        // Marker) ALS AUCH als Flexion von „ami" kennt, würde der
        // Volltext-Pfad „masculin Singular" melden — korrekt ist
        // aber „pluriel". `inflectionLemma(for:)` umgeht den Volltext-
        // Vorrang und gibt uns den Flexions-Hinweis direkt.
        if let pluriel = detectPluralViaInflection(core: core) {
            return pluriel
        }

        // ─── Priorität 1.7: Suffix-Heuristik Plural ─────────────────
        // Läuft ebenfalls VOR `frenchGender`, weil der DB-Genus-Marker
        // Singular und Plural im Maskulinum nicht unterscheidet —
        // „hommes" und „homme" tragen beide „m". Erkennung über
        // Endung + DB-verifizierten Singular-Stamm; bekannte Ausnahmen
        // (z.\u{00A0}B. „fils", „temps") sind hardcoded ausgeschlossen.
        if leadingSignal != .articleSingular,
           let heurPlural = detectPluralByHeuristic(core: core) {
            return heurPlural
        }

        // ─── Priorität 2: Master-Lexikon (StandardVocabularyLoader) ──
        // Direkter Treffer aus `frenchGenderMap` (Cache, O(1)). Dieses
        // Signal kommt aus der kuratierten SQLite-DB — deshalb vor
        // allen heuristischen Quellen.
        if let gender = StandardVocabularyLoader.frenchGender(for: core) {
            switch gender.lowercased() {
            case "m", "masculine":  return .masculin
            case "f", "feminine":   return .feminin
            case "p", "plural":     return .pluriel
            default: break
            }
        }

        // ─── Priorität 4: Supplemental-Lexikon (source-only) ─────────
        if let suppl = SupplementalFreeDictLexicon.sourceOnlyGender(for: core) {
            switch suppl.lowercased() {
            case "masculine": return .masculin
            case "feminine":  return .feminin
            case "plural":    return .pluriel
            default: break
            }
        }

        // ─── Priorität 5: Supplemental-Lexikon (exact pair) ──────────
        if let pair = SupplementalFreeDictLexicon.exactGenderInfo(
            sourceTerm: core, targetTerm: item.german
        ), let fr = pair.french {
            switch fr.gender {
            case .masculine: return .masculin
            case .feminine:  return .feminin
            case .plural:    return .pluriel
            case .neuter:    break  // Französisch kennt kein Neutrum
            }
        }

        // ─── Priorität 6: `frenchGenderInfo` nur wenn NICHT-heuristisch ─
        // `frenchGenderInfo` liefert sowohl sichere Treffer (führender
        // Artikel im Rohtext → `isHeuristic == false`) als auch
        // Suffix-Ratings (-tion, -sion, -ment → `isHeuristic == true`).
        // User-Vorgabe: konservativ, also akzeptieren wir **nur** die
        // nicht-heuristischen Treffer. Die Suffix-Rate landet im
        // `.indetermine`-Fallback → Eintrag wird Gatekeeper-verworfen.
        if let info = frenchGenderInfo(for: core, cardType: .words), info.isHeuristic == false {
            switch info.gender {
            case .masculine: return .masculin
            case .feminine:  return .feminin
            case .plural:    return .pluriel
            case .neuter:    break
            }
        }

        // ─── Priorität 7: Deutsch-Fallback (späte Notlösung) ─────────
        // User-Vorgabe: „wirklich nur als späte Notlösung verwenden".
        // Greift nur, wenn weder Master-Lexikon noch Supplemental-
        // Lexikon noch nicht-heuristische Suffix-Info etwas wissen.
        // Kontrolliert mit abgesicherter „die"-Ambiguität (Plural vs.
        // Sing. fem.) — siehe Kommentar unten.
        let german = item.german.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if german.hasPrefix("der ") { return .masculin }
        if german.hasPrefix("das ") { return .masculin }
        if german.hasPrefix("die ") {
            // „die" ist im Deutschen mehrdeutig: Singular-Feminin ODER
            // Plural. Wenn **unsere** Plural-Heuristik auf dem Kern nicht
            // gegriffen hat (keine Endung s/x + Sing. im Lexikon), gehen
            // wir von Sing.-Feminin aus — der häufigere Fall. Plural-
            // Einträge sollten ohnehin eher über Priorität 1–3 landen.
            return .feminin
        }

        return .indetermine
    }

    /// Flexions-basierte Plural-Erkennung. Liefert `.pluriel` genau dann,
    /// wenn `core` in der Flexions-Map auf ein anderes Lemma verweist UND
    /// typographisch nach Plural aussieht (endet auf `s` oder `x`, länger
    /// als 2 Zeichen). Das unterscheidet:
    ///   • „amis" → Flexion von „ami" → Plural ✓
    ///   • „fils"  → Flexion von „fils" (identisches Lemma) → kein Plural ✗
    ///   • „école" → keine Flexion → weiter zur Heuristik ✗
    private static func detectPluralViaInflection(core: String) -> ArticleExerciseTarget.Genre? {
        let lower = core.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard lower.count > 2 else { return nil }
        guard let last = lower.last, last == "s" || last == "x" else { return nil }
        guard let inflLemma = StandardVocabularyLoader.inflectionLemma(for: lower),
              inflLemma.lowercased() != lower else { return nil }
        // Nur Flexionen von Nomen zählen (Verb-Flexionen wären ohnehin kein
        // Artikel-Modus-Kandidat, aber absichern schadet nicht).
        if let lemmaClass = StandardVocabularyLoader.wordClass(for: inflLemma),
           lemmaClass != "noun" {
            return nil
        }
        return .pluriel
    }

    /// Nomen, die im **Singular** auf `-s`/`-x`/`-z` enden — ohne diese
    /// Liste würde die Plural-Heuristik sie fälschlich als Plural
    /// klassifizieren („fils" = Sohn, „temps" = Zeit). Bewusst klein
    /// gehalten; für Grenzfälle jenseits dieser Liste setzt die Heuristik
    /// weiterhin auf die DB-Singular-Verifikation.
    private static let singularNounsEndingInSXZ: Set<String> = [
        "fils", "temps", "pays", "repas", "dos", "corps", "bois", "mois",
        "poids", "bras", "cas", "cours", "concours", "discours", "univers",
        "processus", "virus", "os", "sens", "puits", "printemps",
        "prix", "choix", "croix", "voix", "noix", "paix", "faix",
        "nez", "riz", "gaz", "rez"
    ]

    /// Suffix-basierte Plural-Erkennung — liefert `.pluriel` wenn der
    /// Kern auf `-s`/`-x` endet UND der Singular-Stamm (Kern ohne
    /// letztes Zeichen bzw. über `naiveSingularizeFrenchNoun`) im
    /// Master-Lexikon als Nomen steht. Ausnahmen in `singularNounsEndingInSXZ`.
    ///
    /// Unterschied zur älteren Version: wir **verlassen uns nicht** mehr
    /// auf einen nil-selfGender-Check. Ist auch dann korrekt, wenn die
    /// DB den Plural-Form-Eintrag ebenfalls mit einem Gender-Marker
    /// führt („hommes" mit Marker „m").
    private static func detectPluralByHeuristic(core: String) -> ArticleExerciseTarget.Genre? {
        let lower = core.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard lower.count > 2 else { return nil }
        guard let last = lower.last, last == "s" || last == "x" else { return nil }

        // Hardcoded Ausnahmen.
        if singularNounsEndingInSXZ.contains(lower) { return nil }

        // Direkter Singular-Stamm (ein Zeichen weg).
        let directSingular = String(lower.dropLast())
        if StandardVocabularyLoader.isNoun(directSingular) {
            return .pluriel
        }

        // Spezielle Plural-Muster (eaux → eau, aux → al, eux → eu).
        if let naive = FrenchLemmaFormatter.naiveSingularizeFrenchNoun(lower),
           naive != lower,
           StandardVocabularyLoader.isNoun(naive) {
            return .pluriel
        }

        return nil
    }

    /// Factory für den Ungültig-Case — vermeidet Boilerplate-Wiederholung.
    /// Nimmt jetzt explizit einen `RejectionReason`, damit Debug-Logs
    /// zeigen können, **warum** ein Eintrag aussortiert wurde.
    private static func invalidTarget(
        raw: String,
        core: String,
        reason: ArticleExerciseTarget.RejectionReason
    ) -> ArticleExerciseTarget {
        ArticleExerciseTarget(
            texteSourceVisible: raw,
            noyauLexical: core,
            lemme: core,
            categoriePrincipale: .autre,
            genre: .indetermine,
            commenceParVoyelleOuHMuet: false,
            reponseAttendueArticle: nil,
            estValidePourExerciceArticle: false,
            rejectionReason: reason
        )
    }
}

// MARK: - Testfälle (Spec-Dokumentation)
//
// Die User-Spec nennt 10 konkrete Testfälle. Sie sind hier als Kommentar
// fixiert, damit die Erwartungen an `ArticleModeClassifier.classify(_:)`
// auch ohne Test-Target im Projekt nachprüfbar bleiben. Bei jedem Fix
// oder Refactor an der Klassifizierer-Logik diese Liste durchgehen:
//
//  1. "le"        → estValide = false
//  2. "la"        → estValide = false
//  3. "le / la"   → estValide = false
//  4. "mon ami"   → noyau = "ami",    reponse = "l'"
//  5. "mon amie"  → noyau = "amie",   reponse = "l'"
//  6. "mon copain"→ noyau = "copain", reponse = "le"
//  7. "ma copine" → noyau = "copine", reponse = "la"
//  8. "la fille"  → noyau = "fille",  reponse = "la"
//  9. "homme"     →                   reponse = "l'"
// 10. "comment"   → estValide = false  (Adverb, kein Nomen — wordClass-Gate)
