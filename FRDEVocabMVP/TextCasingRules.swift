import Foundation

// MARK: - Zentrale Normalisierungs-Engine
//
// EINZIGE Quelle für Groß-/Kleinschreibung in der gesamten App.
// Alle bestehenden Display-Pfade (Scan, Import, Listen, Lexikon, Quiz) gehen durch hier.
//
// Regeln (konservativ, deterministisch, ohne Bedeutungs-Interpretation):
//
//   Deutsch:
//   • Token nach Artikel (der, die, das, ein, mein, dein, kein, ihr, euer, dieser, …) → groß
//   • Token nach Präposition+Artikel (im, am, beim, zum, zur, vom, ans, ins, …)       → groß
//   • Höflichkeitsform (Sie, Ihnen, Ihr)                                                → groß
//   • Bereits groß geschriebenes Token (und nicht in Artikel-/Präp-Liste)               → beibehalten
//   • Sonst                                                                             → klein
//
//   Französisch:
//   • Bereits groß geschriebenes Token (und kein Artikel)                              → beibehalten
//   • Sonst                                                                             → klein
//
//   Beide:
//   • Text endet mit „. ! ?“  → erster Buchstabe des ersten Tokens groß
//   • Slash/Pipe-Segmente    → jedes Segment unabhängig normalisiert
//   • Apostrophe/Bindestriche bleiben erhalten (Token bleibt zusammen)
//
// Keine Heuristiken, kein Raten, keine Wörterbuchabfragen. Eingaben, die das
// gewünschte Verhalten nicht treffen, werden durch Regelverfeinerung im Code
// hier oben gelöst — nicht durch Sonderfälle anderswo.

enum NormalizationLanguage {
    case german
    case french
}

enum TextNormalizationEngine {

    // MARK: - Rule Tables

    /// Artikel im Deutschen, in allen Flexionen. Nach diesen Tokens wird das
    /// nachfolgende Token großgeschrieben (Nominalisierung).
    static let germanArticles: Set<String> = [
        "der", "die", "das", "den", "dem", "des",
        "ein", "eine", "einen", "einem", "einer", "eines",
        "kein", "keine", "keinen", "keinem", "keiner", "keines",
        "mein", "meine", "meinen", "meinem", "meiner", "meines",
        "dein", "deine", "deinen", "deinem", "deiner", "deines",
        "sein", "seine", "seinen", "seinem", "seiner", "seines",
        "ihr", "ihre", "ihren", "ihrem", "ihrer", "ihres",
        "unser", "unsere", "unseren", "unserem", "unserer", "unseres",
        "euer", "eure", "euren", "eurem", "eurer", "eures",
        "dieser", "diese", "dieses", "diesen", "diesem",
        "jeder", "jede", "jedes", "jedem", "jeden",
        "welcher", "welche", "welches", "welchen", "welchem"
    ]

    /// Verschmelzungen aus Präposition + Artikel. Nach diesen Tokens wird das
    /// folgende Token großgeschrieben (z. B. „beim Essen“).
    static let germanPrepArticle: Set<String> = [
        "im", "am", "beim", "zum", "zur", "vom",
        "ans", "ins", "aufs", "durchs", "\u{00FC}bers", "ubers", "ums",
        "f\u{00FC}rs", "furs", "hinterm", "hinters", "vorm", "vors",
        "unterm", "unters"
    ]

    /// Höflichkeitsformen im Deutschen — immer groß.
    static let germanPolitePronouns: Set<String> = [
        "sie", "ihnen", "ihr", "ihre", "ihren", "ihrem", "ihrer", "ihres"
    ]

    /// Deutsche Funktionswörter, die NIE Nomen sein können. Werden immer klein
    /// geschrieben (ausser am Satzanfang, den behandelt die sentence-ending-
    /// Regel separat). Absichtlich OHNE Adjektive und Infinitive, weil diese
    /// nominalisiert werden können („das Gute", „das Gehen").
    static let germanAlwaysLowercase: Set<String> = [
        // Konjunktionen
        "und", "oder", "aber", "denn", "sondern", "doch",
        "weil", "wenn", "ob", "dass", "als", "wie", "damit", "obwohl",
        "da", "falls", "sofern", "bevor", "nachdem", "w\u{00E4}hrend", "wahrend",
        // Adverbien
        "hier", "dort", "jetzt", "heute", "morgen", "gestern",
        "immer", "nie", "oft", "manchmal", "bald", "schon", "noch",
        "sehr", "ganz", "ziemlich", "etwas", "kaum",
        "auch", "nur", "mal", "etwa", "gern", "gerne",
        "ja", "nein", "nicht",
        // H\u{00E4}ufige Verb-Flexionen (Indikativ Pr\u{00E4}sens/Pr\u{00E4}teritum — nie Nomen)
        "ist", "sind", "war", "waren", "bin", "bist", "seid",
        "hat", "haben", "hast", "habt", "hatte", "hatten",
        "heisst", "heisst", "hei\u{00DF}t", "hei\u{00DF}en", "heisse", "hei\u{00DF}e",
        "geht", "gehst", "kommt", "kommst",
        "macht", "machst", "sagt", "sagst", "sieht", "siehst",
        "wei\u{00DF}", "weiss",
        "kann", "kannst", "k\u{00F6}nnen", "konnen",
        "muss", "musst", "m\u{00FC}ssen", "mussen",
        "will", "willst", "wollen",
        "mag", "magst", "m\u{00F6}gen", "mogen",
        "soll", "sollst", "sollen",
        "darf", "darfst", "d\u{00FC}rfen", "durfen",
        "tut", "tun", "tust",
        "gibt", "gibst", "geben",
        "nimmt", "nimmst", "nehmen",
        "schl\u{00E4}ft", "schlaeft", "schlafen",
        "wird", "wirst", "werden", "werdet",
        "wurde", "wurden", "w\u{00FC}rde", "wurde",
        // Pronomen (ohne H\u{00F6}flichkeits-sie/ihr)
        "ich", "du", "er", "es", "wir",
        "mich", "dich", "mir", "dir", "ihm", "ihn", "uns", "euch",
        "man", "sich", "jemand", "niemand", "nichts",
        "jener", "jene", "jenes",
        // Pr\u{00E4}positionen
        "von", "zu", "mit", "bei", "nach", "aus", "auf", "in", "an",
        "f\u{00FC}r", "fur", "\u{00FC}ber", "uber", "unter", "vor", "hinter", "neben",
        "zwischen", "gegen", "ohne", "durch", "um", "bis", "seit",
        "trotz", "wegen", "statt", "au\u{00DF}er", "ausser",
        // Frageadverbien
        "wo", "wohin", "woher", "wann", "warum", "wieso", "weshalb", "wozu"
    ]

    /// Kleinbuchstabige französische Funktionswörter, die NICHT als Eigennamen
    /// durchgehen dürfen (obwohl sie am Satzanfang groß sein können).
    static let frenchArticleHintsForNormalization: Set<String> = [
        "le", "la", "les", "l", "un", "une", "des", "du",
        "au", "aux", "de", "d"
    ]

    private static let sentenceEndings: Set<Character> = [".", "!", "?"]
    private static let segmentSeparators: Set<Character> = ["/", "|"]

    // MARK: - Public API

    /// Zentrale Normalisierungsfunktion. Idempotent.
    static func normalize(_ text: String, language: NormalizationLanguage) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        // Terminal-Satzzeichen abspalten (kann mehrfach sein: „?!“, „…“ bleibt raus)
        var core = trimmed
        var terminal = ""
        while let last = core.last, sentenceEndings.contains(last) {
            terminal = String(last) + terminal
            core = String(core.dropLast())
        }
        let coreTrimmed = core.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !coreTrimmed.isEmpty else { return trimmed }

        let hasSentenceEnding = !terminal.isEmpty

        // Slash/Pipe-Segmente trennen und jedes unabhängig verarbeiten
        let (segments, separators) = splitSegments(coreTrimmed)

        var normalizedSegments: [String] = []
        for (index, segment) in segments.enumerated() {
            let forceCap = (index == 0 && hasSentenceEnding)
            normalizedSegments.append(
                normalizeSegment(segment, language: language, forceFirstTokenCapital: forceCap)
            )
        }

        var rebuilt = ""
        for (i, seg) in normalizedSegments.enumerated() {
            rebuilt += seg
            if i < separators.count {
                rebuilt += separators[i]
            }
        }
        return rebuilt + terminal
    }

    // MARK: - Private: Segmentierung

    private static func splitSegments(_ text: String) -> (segments: [String], separators: [String]) {
        var segments: [String] = []
        var separators: [String] = []
        var buffer = ""
        for ch in text {
            if segmentSeparators.contains(ch) {
                segments.append(buffer)
                separators.append(String(ch))
                buffer = ""
            } else {
                buffer.append(ch)
            }
        }
        segments.append(buffer)
        return (segments, separators)
    }

    private static func normalizeSegment(
        _ segment: String,
        language: NormalizationLanguage,
        forceFirstTokenCapital: Bool
    ) -> String {
        let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return segment }

        let leadingWhitespace = segment.prefix { $0.isWhitespace }
        let trailingWhitespace = segment.reversed().prefix { $0.isWhitespace }.reversed()

        let tokens = trimmed.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        var normalizedTokens: [String] = []
        normalizedTokens.reserveCapacity(tokens.count)

        // Index des LETZTEN nicht-leeren Tokens — gebraucht für die
        // Nomen-Erkennung nach Artikel: ein Adjektiv zwischen Artikel
        // und Nomen darf nicht großgeschrieben werden („das saubere
        // Geschirrtuch", nicht „das Saubere Geschirrtuch").
        let lastMeaningfulIndex: Int = {
            for i in stride(from: tokens.count - 1, through: 0, by: -1) where !tokens[i].isEmpty {
                return i
            }
            return -1
        }()

        for (index, token) in tokens.enumerated() {
            guard !token.isEmpty else {
                normalizedTokens.append(token)
                continue
            }

            let previousLower = index > 0 ? tokens[index - 1].lowercased() : nil
            let isLastMeaningful = index == lastMeaningfulIndex
            var processed: String
            switch language {
            case .german:
                processed = normalizeGermanToken(
                    token,
                    previousTokenLower: previousLower,
                    isLastMeaningfulToken: isLastMeaningful
                )
            case .french:
                processed = normalizeFrenchToken(token)
            }

            if index == 0 && forceFirstTokenCapital {
                processed = capitalizeFirstLetter(processed)
            }

            normalizedTokens.append(processed)
        }

        return String(leadingWhitespace) + normalizedTokens.joined(separator: " ") + String(trailingWhitespace)
    }

    // MARK: - Private: Deutsch

    private static func normalizeGermanToken(
        _ token: String,
        previousTokenLower: String?,
        isLastMeaningfulToken: Bool
    ) -> String {
        let lower = token.lowercased()
        let lowerStem = letterStem(of: lower)
        let originallyCapitalized = startsWithUppercaseLetter(token)

        // 1) Höflichkeitsform immer groß
        if germanPolitePronouns.contains(lowerStem) {
            return capitalizeFirstLetter(lower)
        }

        // 2) Bekannte Artikel/Präp-Artikel immer klein (auch wenn im Input groß)
        if germanArticles.contains(lowerStem) || germanPrepArticle.contains(lowerStem) {
            return lower
        }

        // 3) Bekannte Nicht-Nomen (Konjunktionen, Adverbien, Verb-Flexionen,
        //    Pronomen, Präpositionen) → IMMER klein, schlägt Eigennamen-Heuristik.
        if germanAlwaysLowercase.contains(lowerStem) {
            return lower
        }

        // 4) Nach Artikel/Präp-Artikel → groß — ABER nur, wenn dieses Token
        //    tatsächlich das letzte Content-Token ist (= das Nomen). Steht
        //    zwischen Artikel und Nomen noch ein Adjektiv („das saubere
        //    Geschirrtuch"), darf das Adjektiv nicht großgeschrieben werden.
        //    Bug-Fix 2026-04-22 — vorher wurde jedes Token nach einem
        //    Artikel kapitalisiert, was bei „das saubere Geschirrtuch" zu
        //    „das Saubere Geschirrtuch" geführt hat.
        //
        //    Follow-up 2026-04-22 (abends): in Kompositum-Phrasen wie
        //    „den Regenschutz für den Kinderwagen vorbereiten" ist das
        //    Token nach dem Artikel („Regenschutz") ZWAR nicht das letzte
        //    — aber sehr wohl ein Nomen. Der naive „nicht letztes →
        //    lowercase"-Pfad hätte es kleingeschrieben. Deshalb: vor
        //    dem Lowercase-Fallback im Nomen-Lookup nachschauen. Treffer
        //    → Großschreibung. Kein Treffer → Adjektiv-Annahme und klein.
        if let prev = previousTokenLower {
            let prevStem = letterStem(of: prev)
            if germanArticles.contains(prevStem) || germanPrepArticle.contains(prevStem) {
                if isLastMeaningfulToken {
                    return capitalizeFirstLetter(lower)
                } else {
                    // Kompositum-Disambiguierung: bekanntes Nomen → groß,
                    // sonst Adjektiv/Modifier-Annahme → klein.
                    if StandardVocabularyLoader.germanNounSet.contains(lowerStem) {
                        return capitalizeFirstLetter(lower)
                    }
                    return lower
                }
            }
        }

        // 5) Eigennamen-Heuristik: Input war groß → behalten
        if originallyCapitalized {
            return token
        }

        // 6) Default: klein
        return lower
    }

    /// Entfernt führende/folgende Nicht-Buchstaben (Komma, Punkt, Klammern, Zahlen ...)
    /// damit das Token z.\u{00A0}B. als „da" in der Liste erkannt wird, obwohl
    /// im Text „Da," steht.
    private static func letterStem(of text: String) -> String {
        text.trimmingCharacters(in: CharacterSet.letters.inverted)
    }

    // MARK: - Private: Französisch

    private static func normalizeFrenchToken(_ token: String) -> String {
        let lower = token.lowercased()

        // Funktionswörter immer klein (selbst wenn Input groß)
        if frenchArticleHintsForNormalization.contains(lower) {
            return lower
        }

        // Eigennamen-Heuristik: Input war groß → behalten
        if startsWithUppercaseLetter(token) {
            return token
        }

        return lower
    }

    // MARK: - Private: Hilfen

    private static func capitalizeFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    private static func lowercaseFirstLetter(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    private static func startsWithUppercaseLetter(_ token: String) -> Bool {
        guard let first = token.first(where: { $0.isLetter }) else { return false }
        return first.isUppercase
    }
}

// MARK: - Kompatibilitäts-Wrapper (Alt-API)
//
// Bestehende Aufrufer rufen TextCasingRules.applyGerman/applyFrench.
// Diese Funktionen delegieren jetzt ausschließlich an die Engine.
// Bitte NICHT mehr direkt benutzen — `TextNormalizationEngine.normalize` verwenden.

enum TextCasingRules {

    /// Deutsch-Casing + Slash-Rekonstruktion basierend auf Source-Struktur.
    ///
    /// Slash-Rekonstruktion: Wenn die französische Source einen „/" enthält
    /// (z. B. „le/la"), aber die deutsche Übersetzung nur Leerzeichen („der die"),
    /// wird der Schrägstrich eingefügt → „der/die". Reine Struktur-Anpassung,
    /// keine Casing-Regel. Casing macht die Engine.
    static func applyGerman(_ text: String, sourceHint: String? = nil) -> String {
        let restructured = reconstructSlashSeparator(in: text, sourceHint: sourceHint)
        return TextNormalizationEngine.normalize(restructured, language: .german)
    }

    static func applyFrench(_ text: String) -> String {
        return TextNormalizationEngine.normalize(text, language: .french)
    }

    // Kleine öffentliche Helfer, die anderswo verwendet werden.
    static func capitalizeFirstLetter(of text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    static func lowercaseFirstLetter(of text: String) -> String {
        guard let first = text.first else { return text }
        return first.lowercased() + text.dropFirst()
    }

    private static func reconstructSlashSeparator(in text: String, sourceHint: String?) -> String {
        guard let hint = sourceHint, hint.contains("/") else { return text }
        guard !text.contains("/"), !text.contains("|") else { return text }
        let words = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        // Nur bei genau zwei Tokens rekonstruieren (z. B. „der die" → „der/die"),
        // damit längere Texte nicht fälschlich verändert werden.
        guard words.count == 2 else { return text }
        return "\(words[0])/\(words[1])"
    }
}

// MARK: - Selbst-Tests (DEBUG)
//
// Laufen einmalig beim App-Start und schreiben nach Konsole. Ein ❌ zeigt
// sofort an, dass ein Regelwechsel hier die Spec-Fälle bricht.

#if DEBUG
enum TextNormalizationEngineSelfTest {
    static let didRun: Bool = {
        runSelfTests()
        return true
    }()

    private struct Case {
        let input: String
        let language: NormalizationLanguage
        let expected: String
    }

    private static func runSelfTests() {
        let cases: [Case] = [
            // User-Spec Testfälle
            Case(input: "das gehen",     language: .german, expected: "das Gehen"),
            Case(input: "beim essen",    language: .german, expected: "beim Essen"),
            Case(input: "je vais.",      language: .french, expected: "Je vais."),
            Case(input: "c'est fini.",   language: .french, expected: "C'est fini."),
            Case(input: "le/la",         language: .french, expected: "le/la"),
            Case(input: "der/die.",      language: .german, expected: "Der/die."),
            // Zusatz-Sicherungsfälle
            Case(input: "das videospiel",    language: .german, expected: "das Videospiel"),
            Case(input: "der Freund",        language: .german, expected: "der Freund"),
            Case(input: "Freund",            language: .german, expected: "Freund"),
            Case(input: "Samstag",           language: .german, expected: "Samstag"),
            Case(input: "Sie kommt morgen.", language: .german, expected: "Sie kommt morgen."),
            Case(input: "sie",               language: .german, expected: "Sie"),
            Case(input: "Paris est belle.",  language: .french, expected: "Paris est belle."),
            Case(input: "LA",                language: .french, expected: "la"),
            Case(input: "maison",            language: .french, expected: "maison"),
            Case(input: "Maison",            language: .french, expected: "Maison"),
            // Regression-Fälle: Funktionswörter gewinnen gegen Eigennamen-Heuristik
            Case(input: "sich Und andere vorstellen", language: .german, expected: "sich und andere vorstellen"),
            Case(input: "Da, hier",                   language: .german, expected: "da, hier"),
            Case(input: "Das Sind Noe Und Max",       language: .german, expected: "das sind Noe und Max"),
            Case(input: "Ich Bin Hier.",              language: .german, expected: "Ich bin hier."),
            Case(input: "ce sont",                    language: .german, expected: "ce sont"),
            Case(input: "das Sind",                   language: .german, expected: "das sind"),
            // Punkt am Ende MUSS den ersten Buchstaben großsetzen und erhalten bleiben.
            // Komma in der Mitte darf NICHT als Satzende zählen.
            Case(input: "Das ist gut.",               language: .german, expected: "Das ist gut."),
            Case(input: "da, hier",                   language: .german, expected: "da, hier"),
            Case(input: "Da, hier.",                  language: .german, expected: "Da, hier."),
            Case(input: "ja, aber hier",              language: .german, expected: "ja, aber hier"),
            Case(input: "Hallo, wie geht's?",         language: .german, expected: "Hallo, wie geht's?")
        ]

        var failures = 0
        for c in cases {
            let got = TextNormalizationEngine.normalize(c.input, language: c.language)
            if got != c.expected {
                failures += 1
                print("\u{274C} [Normalize] '\(c.input)' (\(c.language)) → '\(got)' (erwartet '\(c.expected)')")
            }
        }
        if failures == 0 {
            print("\u{2705} [Normalize] \(cases.count) Selbst-Tests bestanden")
        } else {
            print("\u{274C} [Normalize] \(failures) von \(cases.count) Tests fehlgeschlagen")
        }
    }
}
#endif
