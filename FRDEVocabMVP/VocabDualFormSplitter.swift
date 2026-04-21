import Foundation

/// Zentrale Dual-Form-Split-Logik für Vokabel-Einträge.
///
/// Konsolidiert die bisher in `VocabularyListDualFormMigration` und
/// `ScanAIPostProcessor` parallel implementierten Splits. Beide Pfade
/// rufen jetzt hier durch — damit sind Regeln, Separatoren und
/// Confidence-Bewertung an **einer** Stelle.
///
/// Spec (User):
///   • Trenner erkennen: „/", „,", „;"
///   • Fest-Ausdrücke nicht splitten (aujourd'hui, porte-monnaie)
///   • Beliebige Part-Anzahl (nicht nur 2) — für „le / la / les"
///   • Je Split eine Confidence berechnen (0.0 – 1.0)
///     - ≥ 0.8 → automatisch splitten
///     - 0.5 – 0.8 → splitten aber als „medium" markiert (UI-Hook)
///     - < 0.5 → NICHT splitten (unsicher, Original-Eintrag behalten)
enum VocabDualFormSplitter {

    // MARK: - Ergebnis-Typ

    struct SplitDecision {
        /// Gesplittete Teile oder `nil`, wenn wir nicht splitten.
        /// `nil`-Rückgabe heißt: Original-Eintrag bleibt unverändert
        /// im Bestand.
        let parts: [(source: String, target: String)]?
        /// Confidence der Entscheidung, 0…1.
        let confidence: Double
        /// Menschlich lesbare Begründung — geht in Debug-Logs.
        let rationale: String
    }

    /// Minimum-Confidence für „darf gesplittet werden".
    ///
    /// Erhöht von 0.5 auf 0.62 (AP3): gibt dem Splitter etwas mehr
    /// Vorsicht — Randfälle wie „Paris, 2024" oder asymmetrische
    /// Übersetzungen kippen nun eher auf „nicht splitten" als auf
    /// „splitten". Klare Fälle (le/la/les, ami/amie, école/écoles)
    /// bleiben weiterhin deutlich über der Schwelle.
    static let autoApplyThreshold: Double = 0.62

    /// Verbose-Logging-Flag. Im DEBUG-Build standardmäßig aktiv,
    /// damit die Entscheidungen pro Split nachvollziehbar sind.
    /// Im Release-Build ungenutzt — alle `print`s sind `#if DEBUG`
    /// umschlossen.
    #if DEBUG
    static var debugMode: Bool = true
    #else
    static let debugMode: Bool = false
    #endif

    // MARK: - Hauptentscheidung

    /// Prüft, ob Source+Target eine splitbare Dual-Form darstellen.
    /// Wenn die Confidence ≥ `autoApplyThreshold` ist, liefert die
    /// Methode die gesplitteten Parts; sonst bleibt `parts = nil`.
    static func attemptSplit(source: String, target: String) -> SplitDecision {
        // Early out: keine Separatoren → nichts zu splitten.
        let src = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let tgt = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard containsSeparator(src) || containsSeparator(tgt) else {
            return SplitDecision(parts: nil, confidence: 1.0,
                                 rationale: "no separator present")
        }

        // Fest-Ausdrücke blocken (auch wenn sie Apostroph enthalten,
        // den manche Regexes als Split-Kandidat verbuchen würden).
        if isFixedExpression(src) {
            return SplitDecision(parts: nil, confidence: 1.0,
                                 rationale: "fixed expression \(src) — block")
        }

        let srcParts = splitByDelimiters(src)
        let tgtParts = splitByDelimiters(tgt)

        // Asymmetrie → unklar. Nicht splitten, aber mit niedriger
        // Confidence markieren, damit der Debug-Log Ausschläge zeigt.
        guard srcParts.count >= 2,
              srcParts.count == tgtParts.count else {
            return SplitDecision(
                parts: nil,
                confidence: 0.2,
                rationale: "asymmetric parts: source=\(srcParts.count) target=\(tgtParts.count)"
            )
        }

        // Confidence zusammenbauen.
        let structure = structureScore(srcParts: srcParts, tgtParts: tgtParts)
        let dict = dictionaryScore(srcParts: srcParts)
        let grammar = grammarScore(srcParts: srcParts)
        let language = languageScore(srcParts: srcParts, tgtParts: tgtParts)
        let article = articleScore(srcParts: srcParts)

        // Gewichteter Durchschnitt (Structure hat mehr Einfluss, weil
        // ein symmetrischer Split das wichtigste Signal ist).
        let weights: [Double] = [0.30, 0.20, 0.20, 0.15, 0.15]
        let values:  [Double] = [structure, dict, grammar, language, article]
        let confidence = zip(weights, values).map(*).reduce(0, +)

        let rationale = String(
            format: "structure=%.2f dict=%.2f grammar=%.2f lang=%.2f article=%.2f → %.2f",
            structure, dict, grammar, language, article, confidence
        )

        // AP3: verbose Logging pro Split-Entscheidung — fasst alle
        // Einzelscores zusammen, damit man beim Review genau sieht,
        // welcher Faktor die Entscheidung getrieben hat. Nur im
        // Debug-Build, Threshold egal — auch die erfolgreichen Splits
        // werden geloggt.
        #if DEBUG
        if debugMode {
            print("""
            📡 [Split]
              text: source=\"\(src)\" | target=\"\(tgt)\"
              parts: source=\(srcParts.count) / target=\(tgtParts.count)
              structure=\(String(format: "%.2f", structure))
              dict=\(String(format: "%.2f", dict))
              grammar=\(String(format: "%.2f", grammar))
              language=\(String(format: "%.2f", language))
              article=\(String(format: "%.2f", article))
              final=\(String(format: "%.2f", confidence)) (threshold=\(autoApplyThreshold))
            """)
        }
        #endif

        guard confidence >= autoApplyThreshold else {
            return SplitDecision(parts: nil, confidence: confidence, rationale: rationale + " (below threshold)")
        }

        let paired = zip(srcParts, tgtParts).map { (source: $0, target: $1) }
        return SplitDecision(parts: paired, confidence: confidence, rationale: rationale)
    }

    // MARK: - Separator-Logik

    private static let separators: [Character] = ["/", ",", ";"]

    private static func containsSeparator(_ text: String) -> Bool {
        text.contains(where: { separators.contains($0) })
    }

    /// Splittet an `/`, `,`, `;`. Normalisiert Whitespace, trimt und
    /// filtert leere Teile.
    static func splitByDelimiters(_ text: String) -> [String] {
        var normalized = text
        for sep in [" / ", "/ ", " /"] {
            normalized = normalized.replacingOccurrences(of: sep, with: "/")
        }
        for sep in [" , ", ", ", " ,"] {
            normalized = normalized.replacingOccurrences(of: sep, with: ",")
        }
        for sep in [" ; ", "; ", " ;"] {
            normalized = normalized.replacingOccurrences(of: sep, with: ";")
        }
        let separatorSet = CharacterSet(charactersIn: String(separators))
        return normalized
            .components(separatedBy: separatorSet)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// Fest-Ausdruck-Whitelist — Context-Awareness-Layer.
    ///
    /// Französische Fest-Ausdrücke („il y a", „c'est", „qu'est-ce que",
    /// „aujourd'hui", „parce que") werden hier explizit als
    /// **nicht-splittbare Einheit** markiert. Das verhindert, dass
    /// ein internes Komma (z. B. in einer längeren Phrase oder bei
    /// einer Variant-Aufzählung) den Fest-Ausdruck zerreißt.
    ///
    /// Zusätzliche Regel: Einträge mit Bindestrich (ohne andere Trenner)
    /// sind Bindestrich-Komposita wie „porte-monnaie" und bleiben als
    /// Einheit erhalten.
    static func isFixedExpression(_ text: String) -> Bool {
        let lower = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let exact: Set<String> = [
            // Apostroph-Ausdrücke
            "aujourd'hui",
            "aujourd’hui",
            "presqu'île",
            "presqu’île",
            "c'est-à-dire",
            "c’est-à-dire",
            "qu'est-ce que",
            "qu’est-ce que",
            "qu'est-ce qu'",
            "qu’est-ce qu’",

            // Vorkommen in der App — „il y a" ist extrem häufig und
            // wurde vor dem Fix als „il" + „y" + „a" falsch zerlegt,
            // sobald Kommas in der Übersetzung auftauchten.
            "il y a",
            "il y avait",
            "ça va",

            // Verbindungs-Konjunktionen / Präpositions-Phrasen
            "parce que",
            "même si",
            "au lieu de",
            "en train de",
            "à cause de",

            // Bindestrich-Komposita
            "porte-monnaie",
            "porte-bonheur",
            "arc-en-ciel",
            "sous-marin",
            "week-end"
        ]
        if exact.contains(lower) { return true }
        // Kein Separator, aber Bindestrich → wahrscheinlich Kompositum,
        // als fest behandeln.
        if lower.contains("-") && !separators.contains(where: { lower.contains($0) }) {
            return true
        }
        return false
    }

    // MARK: - Confidence-Factoren (0…1)

    /// Gleichmäßige Part-Anzahl und klare Separatoren → hoch.
    private static func structureScore(srcParts: [String], tgtParts: [String]) -> Double {
        guard srcParts.count == tgtParts.count else { return 0.2 }
        // 2-Part-Splits sind am verlässlichsten, 3-Part noch gut,
        // 4+ wird zunehmend fuzzy.
        switch srcParts.count {
        case 2: return 1.0
        case 3: return 0.90
        case 4: return 0.75
        default: return 0.60
        }
    }

    /// Anteil der source-Parts, die im Lexikon gefunden werden.
    private static func dictionaryScore(srcParts: [String]) -> Double {
        guard !srcParts.isEmpty else { return 0 }
        let bareTerms = srcParts.map { stripLeadingArticle(from: $0) }
        let hits = bareTerms.filter { term in
            // Gender-Lookup reicht als Indikator „kennt die DB"
            SupplementalFreeDictLexicon.sourceOnlyGender(for: term) != nil
                || frenchGenderInfo(for: term, cardType: .words) != nil
        }
        return Double(hits.count) / Double(srcParts.count)
    }

    /// Wortart-Plausibilität: wie viele Parts analysieren als sinnvoller
    /// Wortklasse (noun/verb/adjective) statt „unknown"?
    private static func grammarScore(srcParts: [String]) -> Double {
        guard !srcParts.isEmpty else { return 0 }
        var hits = 0
        for part in srcParts {
            let result = FrenchListStatisticsAggregator.cachedAnalyze(part)
            switch result.primaryPos {
            case .noun, .verb, .adjective, .adverb, .phrase, .sentence:
                hits += 1
            case .unknown:
                // Wenn ein direkter Wordclass-Tag vorhanden ist, auch zählen.
                if let direct = result.directWordClass, !direct.isEmpty {
                    hits += 1
                }
            }
        }
        return Double(hits) / Double(srcParts.count)
    }

    /// Source sollte französisch „wirken", Target deutsch.
    /// Heuristisch — zählen charakteristische Buchstaben je Sprache.
    private static func languageScore(srcParts: [String], tgtParts: [String]) -> Double {
        let frLikelihood = srcParts.map(frenchLikeScore(_:)).reduce(0, +) / Double(max(1, srcParts.count))
        let deLikelihood = tgtParts.map(germanLikeScore(_:)).reduce(0, +) / Double(max(1, tgtParts.count))
        return (frLikelihood + deLikelihood) / 2
    }

    /// Typische Französisch-Indikatoren: `é è ê ë à â ç ù`, Apostroph
    /// nach l/c/j/d/n/s/t. Wenn mindestens einer vorhanden oder nur
    /// ASCII-Buchstaben: Score ≥ 0.7.
    private static func frenchLikeScore(_ text: String) -> Double {
        let lower = text.lowercased()
        let frenchMarkers: Set<Character> = ["é", "è", "ê", "ë", "à", "â", "ç", "ù", "û", "ô", "î", "ï"]
        let hasGermanOnly = lower.contains(where: { "äöüß".contains($0) })
        if hasGermanOnly { return 0.3 }
        if lower.contains(where: { frenchMarkers.contains($0) }) { return 1.0 }
        // Nur ASCII + leading French-Artikel → plausibel
        if hasFrenchLeadingPattern(lower) { return 0.9 }
        return 0.7
    }

    private static func germanLikeScore(_ text: String) -> Double {
        let lower = text.lowercased()
        let germanMarkers: Set<Character> = ["ä", "ö", "ü", "ß"]
        let hasFrenchOnly = lower.contains(where: { "éèêëàâçùûôîï".contains($0) })
        if hasFrenchOnly { return 0.3 }
        if lower.contains(where: { germanMarkers.contains($0) }) { return 1.0 }
        if hasGermanLeadingPattern(lower) { return 0.95 }
        return 0.7
    }

    private static func hasFrenchLeadingPattern(_ lower: String) -> Bool {
        ["le ", "la ", "les ", "l'", "un ", "une ", "des ", "du ", "mon ", "ma ", "mes ", "ton ", "ta ", "tes "].contains { lower.hasPrefix($0) }
    }

    private static func hasGermanLeadingPattern(_ lower: String) -> Bool {
        ["der ", "die ", "das ", "den ", "dem ", "ein ", "eine ", "einer ", "einem "].contains { lower.hasPrefix($0) }
    }

    /// Artikel-Muster: „le / la / les", „un / une", „mon / ma / mes"
    /// sind klare Genus/Numerus-Paare. Wenn die Parts diesem Muster
    /// folgen, Bonus.
    private static func articleScore(srcParts: [String]) -> Double {
        let lowers = srcParts.map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
        let articleSets: [Set<String>] = [
            ["le", "la", "les"],
            ["le", "la"],
            ["un", "une"],
            ["mon", "ma", "mes"],
            ["ton", "ta", "tes"],
            ["son", "sa", "ses"],
            ["ce", "cette", "ces"]
        ]
        if let matched = articleSets.first(where: { Set(lowers) == $0 }),
           matched.count == lowers.count {
            return 1.0
        }

        // Auch Paare wie „mon ami / mon amie": gleicher Artikel-Prefix,
        // unterschiedliche Wortform.
        let prefixes = lowers.compactMap { leading(in: $0) }
        let uniquePrefixes = Set(prefixes)
        if uniquePrefixes.count == 1, prefixes.count == lowers.count {
            return 0.9  // gleicher Artikel, unterschiedliche Wörter = starkes Genus-Paar-Signal
        }

        // Unterschiedliche aber bekannte Artikel-Prefixes → m/f-Paar.
        let mascFem: Set<Set<String>> = [
            ["le", "la"], ["un", "une"], ["mon", "ma"], ["ton", "ta"], ["son", "sa"]
        ]
        if mascFem.contains(Set(prefixes)) {
            return 1.0
        }
        return 0.5  // neutral
    }

    private static func leading(in text: String) -> String? {
        let words = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = words.first else { return nil }
        // Apostroph-Artikel: „l'ami" → „l'"
        if first.hasPrefix("l'") || first.hasPrefix("l’") {
            return "l'"
        }
        // Ein-Wort-Eintrag (e. g. „le"): nehme den Eintrag selbst
        if words.count == 1 {
            return String(first)
        }
        return String(first)
    }

    // MARK: - Helpers

    private static func stripLeadingArticle(from text: String) -> String {
        let lower = text.lowercased()
        for prefix in ["le ", "la ", "les ", "l'", "l’", "un ", "une ", "des ", "du ", "de la ",
                       "mon ", "ma ", "mes ", "ton ", "ta ", "tes ", "son ", "sa ", "ses "]
        where lower.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count))
        }
        return text
    }
}
