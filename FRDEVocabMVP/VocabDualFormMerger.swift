import Foundation

/// Smart-Merge: erkennt, wenn zwei direkt nacheinander liegende
/// Vokabel-Einträge eigentlich ein **einziger** Eintrag sein müssten —
/// typischerweise weil vorher ein Split zu aggressiv war oder das
/// Quellformat die beiden Teile einzeln geliefert hat.
///
/// Ergänzt den `VocabDualFormSplitter`. Pipeline:
///   1. Rohdaten einlesen
///   2. Split auf „/", „,", „;"
///   3. Linguistische Analyse
///   4. **Merge-Check (hier)** — Artikel+Nomen-Fragmente zu
///      einem sauberen Eintrag zusammenziehen
///   5. Finalisieren
///
/// Scope-Kontrolle — was wir **automatisch mergen**:
///   • **Artikel + Nomen**: „le" + „ami" → „l'ami" (Datenmodell-
///     kompatibel, keine UI-Änderung nötig).
///
/// Scope-Kontrolle — was wir **erkennen, aber NICHT mergen**:
///   • **Gender-Varianten** („ami" + „amie"): nur im Debug-Log
///     als potenzielle Merge-Kandidaten markiert. Echter Merge
///     würde einen `variants: []`-Slot im `VocabularyItem`
///     brauchen; das ist eine Schema-Migration für eine eigene
///     Slice. Die Paare werden also **separat** behalten
///     (user kann beide einzeln lernen).
///   • **Singular/Plural** („école" + „écoles"): gleich — nur
///     erkannt, nicht zusammengezogen.
///   • **Mehr-Artikel-Gruppe** („le"/„la"/„les"): explizit nicht
///     mergen (das sind drei unabhängige Vokabeln).
enum VocabDualFormMerger {

    struct MergeDecision {
        /// Wenn `merged != nil`, wird dieses `item` anstelle der
        /// beiden Input-Items in die Ergebnisliste eingetragen.
        let merged: VocabularyItem?
        /// Confidence 0…1 — siehe Thresholds unten.
        let confidence: Double
        /// Debug-Begründung.
        let rationale: String
    }

    /// Auto-Apply-Schwelle. Analog zum Splitter: ≥ 0.85 mergen wir
    /// automatisch; 0.6-0.85 = intern markieren (heute nur Debug-Log);
    /// < 0.6 = keine Aktion.
    static let autoApplyThreshold: Double = 0.85

    // MARK: - Listen-Pass

    /// **Voller Merge** — alle drei Merge-Typen (Artikel+Nomen,
    /// Gender-Varianten, Singular/Plural). Für Migration bestehender
    /// Listen gedacht (User-Aufräumung).
    static func mergeFragments(_ items: [VocabularyItem]) -> [VocabularyItem] {
        listPass(items, candidate: attemptMerge(a:b:))
    }

    /// **AP7 — Begrenzter Merge (Artikel+Nomen only)**.
    ///
    /// Einzig sinnvolle automatische Fusion im Live-FreeText-Flow:
    /// „le" + „ami" → „l'ami". Gender-Varianten und Sing/Plu bleiben
    /// als **separate** Einträge erhalten (granulares Lernmaterial).
    ///
    /// Threshold: gleiches `autoApplyThreshold = 0.85` wie beim vollen
    /// Merge — die Artikel+Nomen-Fusion hat ihre eigene Confidence-
    /// Berechnung in `tryMergeArticleNoun`.
    static func mergeArticleNounOnly(_ items: [VocabularyItem]) -> [VocabularyItem] {
        listPass(items) { a, b in
            // Nur Artikel+Nomen-Kandidaten, keine anderen.
            if let merged = tryMergeArticleNoun(article: a, noun: b) {
                return merged
            }
            if let merged = tryMergeArticleNoun(article: b, noun: a) {
                return merged
            }
            return MergeDecision(merged: nil, confidence: 0.0, rationale: "article+noun only — other cases not evaluated")
        }
    }

    /// Shared Listen-Traversal: geht die Liste durch, prüft jeweils
    /// zwei aufeinanderfolgende Items gegen den `candidate`-Evaluator,
    /// mergt bei positivem Entscheid.
    private static func listPass(
        _ items: [VocabularyItem],
        candidate: (VocabularyItem, VocabularyItem) -> MergeDecision
    ) -> [VocabularyItem] {
        guard items.count >= 2 else { return items }
        var result: [VocabularyItem] = []
        var index = 0
        while index < items.count {
            if index + 1 < items.count {
                let decision = candidate(items[index], items[index + 1])
                if let merged = decision.merged {
                    result.append(merged)
                    index += 2
                    continue
                }
            }
            result.append(items[index])
            index += 1
        }
        return result
    }

    // MARK: - Paar-Entscheidung

    /// Prüft zwei Items darauf, ob sie zusammengehören.
    ///   • Artikel + Nomen (→ „l'ami") — auto-merge bei Confidence ≥ 0.85
    ///   • Gender-Varianten (ami/amie) — echtes Merge via `variants:[]`
    ///     auf dem resultierenden `VocabularyItem`
    ///   • Singular/Plural (école/écoles) — analog
    static func attemptMerge(a: VocabularyItem, b: VocabularyItem) -> MergeDecision {
        // Fall 1: a ist nur ein Artikel, b ist das zugehörige Nomen.
        if let merged = tryMergeArticleNoun(article: a, noun: b) {
            return merged
        }
        // Fall 2: gespiegelt — b wäre der Artikel und a das Nomen.
        if let merged = tryMergeArticleNoun(article: b, noun: a) {
            return merged
        }
        // Fall 3: Gender-Varianten — ami/amie, copain/copine etc.
        if let merged = tryMergeGenderVariants(a: a, b: b) {
            return merged
        }
        // Fall 4: Singular/Plural — école/écoles, grain/grains.
        if let merged = tryMergeSingularPlural(a: a, b: b) {
            return merged
        }
        return MergeDecision(merged: nil, confidence: 0.0, rationale: "no merge case matched")
    }

    // MARK: - Fall: Gender-Varianten

    /// „ami" (m) + „amie" (f) → ein Item mit `variants: [{ami, m}, {amie, f}]`.
    /// Basis-Item nimmt die maskuline Form als Leittext (Konvention).
    /// Display-Felder werden trotzdem kombiniert, damit ListDetailSheet
    /// „ami / amie" anzeigen kann.
    ///
    /// Confidence:
    ///   • Beide Worte gleiche Wortbasis (+ -e): +0.5
    ///   • Masc-Artikel bei einem, Fem-Artikel beim anderen: +0.25
    ///   • Deutsche Genus-Markierung im Translation-Prefix passt: +0.15
    ///   • Wordclass beide „noun": +0.1
    private static func tryMergeGenderVariants(
        a: VocabularyItem,
        b: VocabularyItem
    ) -> MergeDecision? {
        // Ähnlichkeit auf Basis-Wort — Standard-Fall „x / xe"
        guard let (masc, fem) = identifyMascFemPair(a: a, b: b) else {
            return nil
        }

        var confidence = 0.5

        // Artikel-Signal prüfen (mon ami/mon amie, le ami/la amie …)
        let aArticle = leadingArticle(masc.french).lowercased()
        let bArticle = leadingArticle(fem.french).lowercased()
        let mascArticles: Set<String> = ["le", "un", "mon", "ton", "son"]
        let femArticles: Set<String> = ["la", "une", "ma", "ta", "sa"]
        if mascArticles.contains(aArticle), femArticles.contains(bArticle) {
            confidence += 0.25
        } else if aArticle.hasPrefix("l'") || aArticle.hasPrefix("l’") {
            // Elision auf beiden Seiten — mindestens leichter Bonus
            confidence += 0.1
        }

        // Deutsche Genus-Markierung als Sanity-Check
        let germanMasc = ["der", "ein"]
        let germanFem = ["die", "eine"]
        let mascDeFirst = leadingArticle(masc.german).lowercased()
        let femDeFirst = leadingArticle(fem.german).lowercased()
        if germanMasc.contains(mascDeFirst), germanFem.contains(femDeFirst) {
            confidence += 0.15
        }

        if (masc.wordClass?.lowercased() == "noun") && (fem.wordClass?.lowercased() == "noun") {
            confidence += 0.1
        }
        confidence = min(1.0, confidence)

        guard confidence >= autoApplyThreshold else {
            return MergeDecision(
                merged: nil,
                confidence: confidence,
                rationale: "gender-variant candidate below threshold: \(confidence)"
            )
        }

        let variants: [VocabGenderVariant] = [
            VocabGenderVariant(french: masc.french, german: masc.german, tag: "m"),
            VocabGenderVariant(french: fem.french, german: fem.german, tag: "f")
        ]
        // Kombiniertes Display: „mon ami / mon amie" — Punkt-getrennte
        // Liste der beiden French/German-Formen. Die UI kann über
        // `variants != nil` erkennen und entsprechend rendern.
        let combinedFrench = "\(masc.french) / \(fem.french)"
        let combinedGerman = "\(masc.german) / \(fem.german)"

        let mergedItem = VocabularyItem(
            rawFrench: combinedFrench,
            rawGerman: combinedGerman,
            cardType: masc.cardType,
            level: masc.level ?? fem.level,
            sourceLanguage: masc.sourceLanguage,
            wordClass: "noun",
            variants: variants
        )
        #if DEBUG
        appDebugLog("🔗 [Merge] Gender-Variant: \"\(masc.french)\" (m) + \"\(fem.french)\" (f) → \"\(combinedFrench)\" (conf=\(String(format: "%.2f", confidence)))")
        #endif
        return MergeDecision(
            merged: mergedItem,
            confidence: confidence,
            rationale: "gender-variant merge"
        )
    }

    /// Erkennt das masculine-first Pair: wenn Basen identisch bis auf
    /// trailing „e", ist das längere die feminine Form. Rückgabe:
    /// (masc, fem) oder nil, wenn kein Paar.
    private static func identifyMascFemPair(
        a: VocabularyItem,
        b: VocabularyItem
    ) -> (masc: VocabularyItem, fem: VocabularyItem)? {
        let aBase = stripLeadingArticle(a.french).lowercased()
        let bBase = stripLeadingArticle(b.french).lowercased()
        // „xxxx" + „xxxxe" (kurzer = masc, länger = fem)
        if aBase + "e" == bBase { return (a, b) }
        if bBase + "e" == aBase { return (b, a) }
        // Typische -eur/-euse, -teur/-trice — noch nicht unterstützt.
        return nil
    }

    // MARK: - Fall: Singular/Plural

    /// „école" + „écoles" → ein Item mit `variants: [{école, sg}, {écoles, pl}]`.
    private static func tryMergeSingularPlural(
        a: VocabularyItem,
        b: VocabularyItem
    ) -> MergeDecision? {
        guard let (singular, plural) = identifySingularPluralPair(a: a, b: b) else {
            return nil
        }
        var confidence = 0.5

        // Artikel-Signal (le/la/l' vs les/des)
        let singArticle = leadingArticle(singular.french).lowercased()
        let plurArticle = leadingArticle(plural.french).lowercased()
        let singularArticles: Set<String> = ["le", "la", "un", "une", "mon", "ma", "ton", "ta", "son", "sa"]
        let pluralArticles: Set<String> = ["les", "des", "mes", "tes", "ses"]
        if (singularArticles.contains(singArticle) || singArticle.hasPrefix("l'") || singArticle.hasPrefix("l’"))
            && pluralArticles.contains(plurArticle) {
            confidence += 0.3
        }

        // Deutsche Entsprechung: Plural oft derselbe Artikel oder s/e
        let singDeFirst = leadingArticle(singular.german).lowercased()
        let plurDeFirst = leadingArticle(plural.german).lowercased()
        if singDeFirst != plurDeFirst || singDeFirst.isEmpty {
            // Unterschiedliche oder fehlende German-Artikel → akzeptabel
            confidence += 0.05
        }
        if (singular.wordClass?.lowercased() == "noun") || (plural.wordClass?.lowercased() == "noun") {
            confidence += 0.1
        }
        confidence = min(1.0, confidence)

        guard confidence >= autoApplyThreshold else {
            return MergeDecision(
                merged: nil,
                confidence: confidence,
                rationale: "sing-plu candidate below threshold: \(confidence)"
            )
        }

        let variants: [VocabGenderVariant] = [
            VocabGenderVariant(french: singular.french, german: singular.german, tag: "sg"),
            VocabGenderVariant(french: plural.french, german: plural.german, tag: "pl")
        ]
        let combinedFrench = "\(singular.french) / \(plural.french)"
        let combinedGerman = "\(singular.german) / \(plural.german)"
        let mergedItem = VocabularyItem(
            rawFrench: combinedFrench,
            rawGerman: combinedGerman,
            cardType: singular.cardType,
            level: singular.level ?? plural.level,
            sourceLanguage: singular.sourceLanguage,
            wordClass: "noun",
            variants: variants
        )
        #if DEBUG
        appDebugLog("🔗 [Merge] Singular/Plural: \"\(singular.french)\" + \"\(plural.french)\" → \"\(combinedFrench)\" (conf=\(String(format: "%.2f", confidence)))")
        #endif
        return MergeDecision(
            merged: mergedItem,
            confidence: confidence,
            rationale: "singular/plural merge"
        )
    }

    /// „école" + „écoles" → (singular=école, plural=écoles).
    /// Unterstützt auch -x / -aux-Plurale.
    private static func identifySingularPluralPair(
        a: VocabularyItem,
        b: VocabularyItem
    ) -> (singular: VocabularyItem, plural: VocabularyItem)? {
        let aBase = stripLeadingArticle(a.french).lowercased()
        let bBase = stripLeadingArticle(b.french).lowercased()
        if aBase + "s" == bBase { return (a, b) }
        if bBase + "s" == aBase { return (b, a) }
        if aBase + "x" == bBase { return (a, b) }
        if bBase + "x" == aBase { return (b, a) }
        // -al → -aux (cheval/chevaux)
        if aBase.hasSuffix("al"), bBase == String(aBase.dropLast(2)) + "aux" { return (a, b) }
        if bBase.hasSuffix("al"), aBase == String(bBase.dropLast(2)) + "aux" { return (b, a) }
        return nil
    }

    /// Liefert das erste Wort (bis zum ersten Leerzeichen). Für
    /// „l'ami" und „l'école" → „l'". Sonst das erste Wort.
    private static func leadingArticle(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("l'") { return "l'" }
        if trimmed.lowercased().hasPrefix("l’") { return "l’" }
        if let spaceIndex = trimmed.firstIndex(of: " ") {
            return String(trimmed[..<spaceIndex])
        }
        return trimmed
    }

    // MARK: - Fall: Artikel + Nomen

    /// Wenn `article.french` **ausschließlich** ein französischer
    /// Artikel ist (keine weiteren Wörter), und `noun.french` das
    /// zugehörige Nomen, wird das Paar zu einem einzigen Eintrag
    /// vereint. Elision wird angewendet: „le" + „ami" → „l'ami".
    ///
    /// Auto-Merge nur wenn Confidence ≥ 0.85:
    ///   • Artikel ist klar in unserer Liste (le/la/les/l'/un/une/des)
    ///   • `noun.french` besteht aus einem einzigen Wort
    ///   • `article.german` ist ein bekannter deutscher Artikel
    ///   • Target-Kombination ist sinnvoll („der" + „Freund" → „der Freund")
    private static func tryMergeArticleNoun(
        article: VocabularyItem,
        noun: VocabularyItem
    ) -> MergeDecision? {
        let frArticle = article.french
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let frNoun = noun.french.trimmingCharacters(in: .whitespacesAndNewlines)

        let knownFrenchArticles: Set<String> = [
            "le", "la", "les", "l'", "l’", "un", "une", "des", "du", "de la"
        ]
        guard knownFrenchArticles.contains(frArticle) else { return nil }

        // `noun.french` darf kein Artikel enthalten und soll ein Wort sein.
        let nounWords = frNoun.split(separator: " ")
        guard nounWords.count == 1 else { return nil }
        let bareNoun = String(nounWords[0])
        let nounLower = bareNoun.lowercased()
        guard !knownFrenchArticles.contains(nounLower) else { return nil }

        // Elision: bei Vokal/H am Anfang → „l'"
        let elisionVowels: Set<Character> = ["a", "e", "i", "o", "u", "h",
                                             "à", "â", "é", "è", "ê", "ë",
                                             "î", "ï", "ô", "ö", "ù", "û", "ü"]
        let firstChar = bareNoun.first.map { Character($0.lowercased()) }
        let needsElision = firstChar.map { elisionVowels.contains($0) } ?? false

        let mergedFrench: String
        if needsElision, frArticle == "le" || frArticle == "la" || frArticle == "l'" || frArticle == "l’" {
            mergedFrench = "l'\(bareNoun)"
        } else {
            mergedFrench = "\(frArticle) \(bareNoun)"
        }

        // German side: „der" + „Freund" → „der Freund". Falls ein
        // Teil leer ist, fallen wir auf den anderen zurück (konservativ).
        let deArticle = article.german.trimmingCharacters(in: .whitespacesAndNewlines)
        let deNoun = noun.german.trimmingCharacters(in: .whitespacesAndNewlines)
        let mergedGerman: String = {
            if !deArticle.isEmpty && !deNoun.isEmpty {
                return "\(deArticle) \(deNoun)"
            }
            return deNoun.isEmpty ? deArticle : deNoun
        }()

        // Confidence:
        //   • Clear article (in list): +0.4
        //   • Single-word noun: +0.2
        //   • German article present: +0.15
        //   • Elision-correct: +0.1
        //   • Kombiniertes Ergebnis im DB-Lexikon: +0.15
        var confidence = 0.4 + 0.2
        if !deArticle.isEmpty, ["der", "die", "das", "den", "dem"].contains(deArticle.lowercased()) {
            confidence += 0.15
        }
        if needsElision { confidence += 0.1 }
        if let g = SupplementalFreeDictLexicon.sourceOnlyGender(for: mergedFrench), !g.isEmpty {
            confidence += 0.15
        }
        confidence = min(1.0, confidence)

        guard confidence >= autoApplyThreshold else {
            return MergeDecision(
                merged: nil,
                confidence: confidence,
                rationale: "article+noun candidate below threshold: \(confidence)"
            )
        }

        #if DEBUG
        appDebugLog("🔗 [Merge] Artikel+Nomen: \"\(article.french)\" + \"\(noun.french)\" → \"\(mergedFrench)\" / \"\(mergedGerman)\" (conf=\(String(format: "%.2f", confidence)))")
        #endif

        let mergedItem = VocabularyItem(
            rawFrench: mergedFrench,
            rawGerman: mergedGerman,
            cardType: .words,
            level: noun.level ?? article.level,
            sourceLanguage: noun.sourceLanguage,
            wordClass: "noun"
        )
        return MergeDecision(
            merged: mergedItem,
            confidence: confidence,
            rationale: "article+noun merge: article=\(frArticle), noun=\(bareNoun)"
        )
    }

    // MARK: - Helpers

    private static func stripLeadingArticle(_ text: String) -> String {
        let lower = text.lowercased()
        let articles = ["le ", "la ", "les ", "l'", "l’", "un ", "une ", "des ", "du ",
                        "mon ", "ma ", "mes ", "ton ", "ta ", "tes ", "son ", "sa ", "ses "]
        for a in articles where lower.hasPrefix(a) {
            return String(text.dropFirst(a.count))
        }
        return text
    }
}
