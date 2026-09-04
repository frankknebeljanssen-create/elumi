import Foundation

/// **Französisch-Genus-Pipeline** (User-Spec 2026-04-22 Abend II)
///
/// Eine Funktion orchestriert die komplette Pipeline pro Nomen-Eintrag:
///
/// ```
/// Input: rohes lemma_fr (evtl. mit Artikel, evtl. ohne)
///    │
///    ▼
/// ┌─────────────────────────────────────┐
/// │ Schritt 1: Artikel-Extraktion       │──> trifft sofort, confidence 1.0
/// │  le/la/les/un/une → Genus klar      │
/// │  l' / kein Artikel → weiter         │
/// └─────────────────────────────────────┘
///    │
///    ▼
/// ┌─────────────────────────────────────┐
/// │ Schritt 2a: DB-interne Lookups      │──> zuverlässig wenn Plural-Form
/// │  Plural (les X) → Singular-Lookup   │    eine Singular-Version in DB hat
/// │  Hauptnomen-Lookup für Phrasen      │
/// └─────────────────────────────────────┘
///    │
///    ▼
/// ┌─────────────────────────────────────┐
/// │ Schritt 2b: Morphologie-Heuristik   │──> Endungs-Regeln aus
/// │  FrenchGenderHeuristicRules.predict │    FrenchGenderHeuristicRules.swift
/// └─────────────────────────────────────┘
///    │
///    ▼
/// Output: ResolvedGender {
///   gender, article, source, confidence,
///   normalizedLemmaWithArticle, number
/// }
/// ```

/// Quelle, aus der das Genus stammt — für Transparenz / Review.
enum FrenchGenderSource: String, Codable, Equatable {
    case explicitArticle    // Artikel war im Input enthalten (le/la/un/une)
    case dbLookup           // aus Plural-Singular-Lookup oder Hauptnomen-Lookup
    case heuristic          // Endungs-Regel
    case unknown            // nichts greift — Residual für KI-Pipeline
}

enum FrenchNumber: String, Codable, Equatable {
    case singular
    case plural
}

/// Resultat der Pipeline.
struct ResolvedGender: Equatable {
    let gender: FrenchGenderHeuristicRules.Gender?   // nil → unbekannt
    let source: FrenchGenderSource
    let confidence: Double
    let number: FrenchNumber
    /// Lemma mit ergänztem Artikel für Display / Speicherung.
    /// Wenn das Genus nicht bestimmt werden kann, bleibt das Lemma
    /// unverändert.
    let normalizedLemma: String
}

enum FrenchGenderResolver {

    // MARK: - Public API

    /// Führt die komplette Pipeline für ein rohes lemma_fr aus.
    /// `pluralLookup` ist ein Callback, der bei Plural-Einträgen
    /// die Singular-Form in der Master-DB nachschlagen kann.
    /// Kann `nil` sein, dann wird Schritt 2a übersprungen.
    static func resolve(
        rawLemma: String,
        pluralLookup: ((String) -> FrenchGenderHeuristicRules.Gender?)? = nil
    ) -> ResolvedGender {
        let trimmed = rawLemma.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ResolvedGender(
                gender: nil,
                source: .unknown,
                confidence: 0.0,
                number: .singular,
                normalizedLemma: rawLemma
            )
        }

        // Schritt 0: Phrasen — Hauptnomen isolieren.
        // Für mehrwortige Nomen (z. B. „salle de bain", „œuf dur") ist
        // das erste nicht-Artikel-Wort das Hauptnomen.
        let (leadingArticle, core, remainingTail) = splitArticleAndCore(trimmed)

        // **Bug-Fix 2026-04-22 (Abend III)**: Number muss FRÜH bestimmt
        // werden und durch ALLE Pfade propagiert, sonst bekommt ein
        // Plural-Bareword („hommes") vom Heuristik-/KI-Pfad fälschlich
        // `number: .singular` und damit `l'` als Artikel.
        //
        // Reihenfolge:
        //   • Artikel „les" → Plural (auch bei Plural-Lookup-Miss)
        //   • Morphologie (endet auf -s/-x, nicht in Singular-Ausnahme) → Plural
        //   • sonst → Singular
        let detectedNumber = detectNumber(article: leadingArticle, core: core)

        // Schritt 1: Artikel-Extraktion (nur wenn eindeutig Singular — les ist ambig)
        if let articleInfo = genderFromArticle(leadingArticle) {
            return ResolvedGender(
                gender: articleInfo.gender,
                source: .explicitArticle,
                confidence: 1.0,
                number: articleInfo.number,
                // Lemma behält Artikel bei (z. B. „le livre" bleibt „le livre")
                normalizedLemma: trimmed
            )
        }

        // Ab hier: entweder `l'`, `les`, oder kein Artikel.
        // Wir brauchen Genus aus anderer Quelle.

        // **Bug-Fix 2026-06-09** — Monatsnamen und Eigennamen stehen im
        // Französischen artikellos und dürfen hier NICHT weiterlaufen.
        //
        // Ohne diesen Riegel griff am Ende der Endungs-Heuristik die
        // Auffangregel „endet auf -e → feminin" (Confidence 0.62) und
        // machte aus `novembre`/`septembre`/`octobre`/`décembre` ein
        // „la novembre" — im Quiz sichtbar (User-Bugreport). Monate sind
        // maskulin, aber „le novembre" wäre genauso falsch: sie stehen
        // schlicht ohne Artikel („en novembre").
        //
        // Rückgabe ohne Genus und mit unverändertem Lemma — der
        // Aufrufer baut daraus keinen Artikel.
        if isArticlelessFrenchNoun(core) {
            return ResolvedGender(
                gender: nil,
                source: .unknown,
                confidence: 0.0,
                number: detectedNumber,
                normalizedLemma: trimmed
            )
        }

        // Schritt 2a (DB): Plural-Sonderfall
        if leadingArticle.lowercased() == "les", let lookup = pluralLookup {
            if let singularGender = lookup(core) {
                return ResolvedGender(
                    gender: singularGender,
                    source: .dbLookup,
                    confidence: 0.95,
                    number: .plural,
                    // Plural-Form behält „les" + Core
                    normalizedLemma: "les \(core)\(remainingTail)"
                )
            }
        }

        // Auch bei Plural-Bareword („hommes" ohne „les"): Singular-Stem
        // bilden und DB-Lookup versuchen (z. B. „hommes" → „homme"
        // → m). Das fängt viele User-Daten auf, wo der Artikel fehlt.
        if detectedNumber == .plural, let lookup = pluralLookup {
            let stem = singularStem(of: core)
            if let singularGender = lookup(stem) {
                return ResolvedGender(
                    gender: singularGender,
                    source: .dbLookup,
                    confidence: 0.92,
                    number: .plural,
                    normalizedLemma: rebuildLemma(article: "les", core: core, tail: remainingTail)
                )
            }
        }

        // **Heuristik-Stufe entfernt (2026-08-07)**: Alle Nomen im
        // Master-Lexikon haben jetzt ein echtes `gender_fr` aus der DB
        // (Genus-Vervollständigungs-Durchlauf, ~1950 Wörter). Die
        // Endungs-Heuristik (`FrenchGenderHeuristicRules`) hätte hier nur
        // noch geraten — genau das wollte der User nicht. Verbleibende
        // Fälle ohne Genus sind ausschließlich die bewusst artikellosen
        // Nomen (Monate, Eigennamen), die schon oben über
        // `isArticlelessFrenchNoun` abgefangen werden.
        //
        // Fallback: Genus konnte nicht bestimmt werden.
        // Aber: wenn Number = plural erkannt wurde, **setzen wir trotzdem
        // „les" als Artikel** (User-Spec: Plurale dürfen NIE „l'" kriegen).
        if detectedNumber == .plural {
            return ResolvedGender(
                gender: nil,
                source: .unknown,
                confidence: 0.0,
                number: .plural,
                normalizedLemma: rebuildLemma(article: "les", core: core, tail: remainingTail)
            )
        }
        return ResolvedGender(
            gender: nil,
            source: .unknown,
            confidence: 0.0,
            number: .singular,
            normalizedLemma: trimmed
        )
    }

    // MARK: - Helpers

    /// Trennt „le livre" → (leadingArticle: "le", core: "livre", tail: "")
    /// oder „l'école" → ("l'", "école", "")
    /// oder „salle de bain" → ("", "salle", " de bain") — nur das erste
    /// Wort ist „core", der Rest wird beim Display wieder angeflanscht.
    static func splitArticleAndCore(_ text: String) -> (article: String, core: String, tail: String) {
        let lower = text.lowercased()

        // Apostrophe-Artikel zuerst (l' / L') — Unicode-Varianten beachten.
        let apostrophePrefixes = ["l'", "l\u{2019}", "d'", "d\u{2019}"]
        for prefix in apostrophePrefixes where lower.hasPrefix(prefix) {
            let after = text.dropFirst(prefix.count)
            let (core, tail) = firstWordAndTail(String(after))
            return (String(text.prefix(prefix.count)), core, tail)
        }

        // Space-getrennte Artikel
        let spaceArticles = [
            "les ", "le ", "la ",
            "un ", "une ", "des ",
            "du ", "au ", "aux "
        ]
        for art in spaceArticles where lower.hasPrefix(art) {
            let after = text.dropFirst(art.count)
            let (core, tail) = firstWordAndTail(String(after))
            return (String(text.prefix(art.count - 1)), core, tail)
        }

        // Kein Artikel — nimm erstes Wort als core
        let (core, tail) = firstWordAndTail(text)
        return ("", core, tail)
    }

    private static func firstWordAndTail(_ text: String) -> (core: String, tail: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let spaceIdx = trimmed.firstIndex(of: " ") {
            return (
                core: String(trimmed[..<spaceIdx]),
                tail: " " + String(trimmed[trimmed.index(after: spaceIdx)...])
            )
        }
        return (trimmed, "")
    }

    /// Genus aus dem Artikel ableiten, wenn eindeutig.
    private static func genderFromArticle(
        _ article: String
    ) -> (gender: FrenchGenderHeuristicRules.Gender, number: FrenchNumber)? {
        switch article.lowercased() {
        case "le", "un", "du", "au":
            return (.masculine, .singular)
        case "la", "une":
            return (.feminine, .singular)
        // les/aux/des sind Plural — Genus bleibt offen
        default:
            return nil
        }
    }

    /// **Artikel-Regel mit strikter Priorität** (User-Spec 2026-04-22 Abend III):
    ///
    ///   1. `number == .plural`  → „les"  (überschreibt alle anderen Regeln)
    ///   2. Singular + Vokal/stummes-h → „l'"
    ///   3. Singular + feminin  → „la"
    ///   4. Singular + maskulin → „le"
    ///
    /// Regel 1 MUSS zuerst stehen — Plural darf nie „l'" kriegen, auch
    /// wenn der Core mit Vokal beginnt („les ours", nicht „l'ours"-Plural).
    private static func articleFor(
        gender: FrenchGenderHeuristicRules.Gender,
        core: String,
        number: FrenchNumber
    ) -> String {
        // Priorität 1: Plural — IMMER „les"
        if number == .plural {
            return "les"
        }
        // Priorität 2: Elision vor Vokal oder h (nur Singular!)
        if startsWithVowelOrH(core) {
            return "l'"
        }
        // Priorität 3 + 4: Genus-basiertes Singular
        return gender == .masculine ? "le" : "la"
    }

    private static func startsWithVowelOrH(_ core: String) -> Bool {
        guard let firstScalar = core.lowercased().unicodeScalars.first else { return false }
        let char = Character(firstScalar)
        if elisionTriggers.contains(char) { return true }
        // Konservativ: jedes „h" → Elision. Die Ausnahmen des aspirierten h
        // (héros, haricot, honte) sind so selten, dass „l'" als Fallback
        // deutlich seltener falsch ist als „le héros" umgekehrt.
        if char == "h" { return true }
        return false
    }

    // MARK: - Number-Detection

    /// Bestimmt, ob ein Nomen Plural oder Singular ist — aus Artikel +
    /// Morphologie. Artikel „les" schlägt Morphologie.
    static func detectNumber(article: String, core: String) -> FrenchNumber {
        if article.lowercased() == "les" { return .plural }
        if isMorphologicalPlural(core) { return .plural }
        return .singular
    }

    /// Endet auf -s oder -x, aber ist NICHT in der Liste der
    /// „Singular-aber-sieht-aus-wie-Plural"-Ausnahmen.
    /// Beispiele: `pays`, `temps`, `bras` sind Singular trotz -s.
    static func isMorphologicalPlural(_ core: String) -> Bool {
        let lower = core.lowercased()
        guard lower.count > 2 else { return false }
        guard lower.hasSuffix("s") || lower.hasSuffix("x") else { return false }
        return !singularLookalikes.contains(lower)
    }

    /// Nomen, die auf -s oder -x enden, aber im Singular stehen.
    /// Manuell gepflegt — bei Bedarf erweiterbar.
    private static let singularLookalikes: Set<String> = [
        "pays", "temps", "bras", "corps", "fils", "cours", "mois",
        "jus", "dos", "os", "repas", "bois", "pois", "pas",
        "processus", "cactus", "autobus", "bus", "virus", "campus",
        "prix", "choix", "noix", "voix", "toux", "roux",
        "paix", "crucifix", "flux", "reflux", "lynx", "sphinx",
        "fois"
    ]

    /// Bildet einen Singular-Stem aus einer (vermuteten) Plural-Form —
    /// simple Regel: -s/-x am Ende entfernen, -aux → -al zurücksetzen.
    /// Wird für Heuristik und Lookup-Fallback genutzt.
    static func singularStem(of core: String) -> String {
        let lower = core.lowercased()
        // -aux → -al (z. B. „chevaux" → „cheval", „journaux" → „journal")
        if lower.hasSuffix("aux"), lower.count > 4 {
            return String(core.dropLast(3)) + "al"
        }
        // -eux → -eu / -eu häufig auch Singular (Ausnahme)
        // Keine generische Regel — skip.
        if lower.hasSuffix("s") || lower.hasSuffix("x") {
            return String(core.dropLast())
        }
        return core
    }

    private static let elisionTriggers: Set<Character> = [
        "a", "à", "â", "ä", "æ",
        "e", "é", "è", "ê", "ë",
        "i", "î", "ï",
        "o", "ô", "ö", "œ",
        "u", "û", "ü", "ù",
        "y"
    ]

    /// Setzt den Lemma-String aus (potenziell neu gebautem) Artikel,
    /// Core und Tail wieder zusammen. Für `l'` ohne Space, sonst mit.
    private static func rebuildLemma(article: String, core: String, tail: String) -> String {
        if article == "l'" || article == "L'" {
            return "\(article)\(core)\(tail)"
        }
        if article.isEmpty {
            return "\(core)\(tail)"
        }
        return "\(article) \(core)\(tail)"
    }
}

// MARK: - Debug-Self-Tests

#if DEBUG
/// **Self-Tests** für die Plural-Artikel-Regeln. Wird einmal pro
/// App-Start ausgeführt und schlägt bei Regression Alarm via
/// `assertionFailure` — kein echtes XCTest-Target nötig.
enum FrenchGenderResolverSelfTest {

    struct Case {
        let input: String
        let expectedArticle: String?   // nil = „egal" (nur number/gender prüfen)
        let expectedNumber: FrenchNumber
        let expectedGender: FrenchGenderHeuristicRules.Gender?
        let note: String
    }

    static func runIfNeeded() {
        guard !hasRun else { return }
        hasRun = true

        let cases: [Case] = [
            // **User-Spec-Testfall 2026-04-22 Abend III**:
            // „hommes" bareword (kein Artikel) → muss „les hommes" werden.
            Case(
                input: "hommes",
                expectedArticle: "les",
                expectedNumber: .plural,
                expectedGender: nil,    // kann über Heuristik/Lookup auch gefunden werden, aber hier tolerant
                note: "Plural-Bareword muss les-Artikel bekommen"
            ),
            // „les amis" mit Artikel — Artikel + Plural behalten.
            Case(
                input: "les amis",
                expectedArticle: "les",
                expectedNumber: .plural,
                expectedGender: nil,
                note: "les-Artikel vorhanden"
            ),
            // Singular-Ausnahme: „pays" sieht wie Plural aus, ist Singular.
            Case(
                input: "pays",
                expectedArticle: nil,   // je nach Heuristik-Treffer
                expectedNumber: .singular,
                expectedGender: nil,
                note: "Singular-Ausnahme trotz -s"
            ),
            // Vokal-Anlaut Singular: „ami" → „l'ami"
            Case(
                input: "ami",
                expectedArticle: "l'",
                expectedNumber: .singular,
                expectedGender: nil,
                note: "Vokal-Elision Singular"
            ),
            // Maskulin-Artikel: „le livre" → bleibt „le livre"
            Case(
                input: "le livre",
                expectedArticle: "le",
                expectedNumber: .singular,
                expectedGender: .masculine,
                note: "Expliziter le-Artikel"
            )
        ]

        var failures: [String] = []
        for c in cases {
            let result = FrenchGenderResolver.resolve(rawLemma: c.input)
            let article = extractArticleFromLemma(result.normalizedLemma)
            let numberOK = (result.number == c.expectedNumber)
            let articleOK = c.expectedArticle == nil || article == c.expectedArticle
            let genderOK = (c.expectedGender == nil) || (result.gender == c.expectedGender)
            if !(numberOK && articleOK && genderOK) {
                failures.append("""
                FAIL: \(c.note)
                   input=\"\(c.input)\"  normalized=\"\(result.normalizedLemma)\"
                   number: got=\(result.number) expected=\(c.expectedNumber)  \(numberOK ? "✓" : "✗")
                   article: got=\(article ?? "nil") expected=\(c.expectedArticle ?? "(any)")  \(articleOK ? "✓" : "✗")
                   gender: got=\(result.gender?.rawValue ?? "nil") expected=\(c.expectedGender?.rawValue ?? "(any)")  \(genderOK ? "✓" : "✗")
                """)
            }
        }
        if failures.isEmpty {
            appDebugLog("✅ [FrenchGenderResolverSelfTest] alle \(cases.count) Fälle grün")
        } else {
            appDebugLog("❌ [FrenchGenderResolverSelfTest] \(failures.count)/\(cases.count) gefailt:")
            for f in failures { appDebugLog(f) }
            assertionFailure("FrenchGenderResolver self-test failed — siehe console")
        }
    }

    private static var hasRun = false

    private static func extractArticleFromLemma(_ lemma: String) -> String? {
        let lower = lemma.lowercased()
        let apos = ["l'", "l\u{2019}"]
        for a in apos where lower.hasPrefix(a) { return "l'" }
        let spaced = ["les ", "le ", "la ", "un ", "une ", "des "]
        for a in spaced where lower.hasPrefix(a) {
            return String(a.dropLast())   // trailing space weg
        }
        return nil
    }
}
#endif
