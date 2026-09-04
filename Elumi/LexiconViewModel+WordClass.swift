import Foundation

extension LexiconViewModel {
    func lexiconWordClassMarker(for entry: PreparedLexiconEntry) -> LexiconWordClassMarker? {
        // Legacy-Marker (nur noun/verb/adjective/phrase) — bleibt für DetailSheet-Header
        // wo expliziter Marker gewünscht ist. Für die Listen-Badges siehe `lexiconWordClassBadgeText`.
        if entry.displayCardType == .phrases { return .phrase }

        // **Bugfix** (User-Report: „hell (clair)" taucht unter Verben
        // auf, obwohl das Adjektiv-Pill gesetzt ist):
        // Vorher lief hier als erstes die Verb-Heuristik
        // (`StandardVocabularyLoader.isVerb`), die auf das Suffix „-ir"
        // greift — dadurch wurde „clair" fälschlich als Verb markiert,
        // während das Badge via `FrenchLemmaFormatter.wordClassLabel`
        // korrekt „Adjektiv" zeigte. Ergebnis: Filter und Pill
        // widersprachen sich.
        //
        // Neue Ordnung: erst das **gespeicherte** Wortklassen-Label
        // (Single Source of Truth — identisch zu dem, was das Badge
        // zeigt) respektieren. Nur wenn das Label unklar ist, greifen
        // die Heuristiken als Fallback.
        if let firstEntry = entry.entries.first {
            let storedLabel = FrenchLemmaFormatter.wordClassLabel(forLexiconEntry: firstEntry)
                .lowercased()
            switch storedLabel {
            case "nomen", "substantiv":
                return .noun
            case "verb":
                return .verb
            case "adjektiv", "adjektiv/adverb":
                return .adjective
            default:
                break  // Fallback auf Heuristik unten
            }
        }

        let hasNoun = entry.entries.contains(where: { $0.isGermanNoun })
        if hasNoun { return .noun }
        let sourceTerms = entry.entries.map(\.sourceTerm)
        // Adjektiv-Check **vor** der Verb-Heuristik — „clair", „noir",
        // „chair"-artige Wörter enden auf „-ir" und würden sonst von
        // `StandardVocabularyLoader.isVerb` als Verb eingestuft,
        // obwohl sie klar Adjektive sind.
        let isAdjLike = sourceTerms.contains { term in
            self.isLikelyAdjectiveLexiconEntry(makeStubEntry(sourceTerm: term))
        }
        if isAdjLike { return .adjective }
        if sourceTerms.contains(where: { StandardVocabularyLoader.isVerb($0) }) {
            return .verb
        }
        return nil
    }

    /// Zentrale Wortart-Anzeige fürs Wörterbuch — IMMER ein Label, nutzt
    /// `FrenchLemmaFormatter.wordClassLabel(forLexiconEntry:)` (Single Source of Truth).
    /// Liefert kompakte deutsche Bezeichnung („Nomen", „Verb", „Adverb", „Pronomen", …).
    func lexiconWordClassBadgeText(for entry: PreparedLexiconEntry) -> String? {
        guard let firstEntry = entry.entries.first else { return nil }
        let label = FrenchLemmaFormatter.wordClassLabel(forLexiconEntry: firstEntry)
        // „Wort" ist ein Default-Fallback ohne Aussagewert — lieber kein Badge.
        return label == "Wort" ? nil : label
    }

    private func makeStubEntry(sourceTerm: String) -> LexiconEntry {
        LexiconEntry(
            id: "stub|\(sourceTerm)",
            sourceTerm: sourceTerm,
            targetTerm: "",
            sourceLanguage: .french,
            cardType: .words
        )
    }

    func isLikelyNounLexiconEntry(_ entry: LexiconEntry) -> Bool {
        let displayCardType = resolvedLexiconCardType(for: entry)
        guard displayCardType == .words else { return false }

        let target = entry.targetTerm
        let normalizedTarget = normalizedLookupText(target)

        return entry.frenchGender != nil ||
            entry.germanGender != nil ||
            hasFrenchNounHint(entry.sourceTerm, cardType: displayCardType) ||
            startsWithGermanArticle(target) ||
            (!normalizedTarget.isEmpty && DataStore.likelyGermanNounSet.contains(normalizedTarget))
    }

    func isLikelyVerbLexiconEntry(_ entry: LexiconEntry) -> Bool {
        let normalizedSource = normalizedLookupText(entry.sourceTerm)
        let normalizedTarget = normalizedLookupText(entry.targetTerm)

        return looksLikeFrenchInfinitiveLexiconWord(normalizedSource) ||
            looksLikeGermanVerbLexiconWord(normalizedTarget)
    }

    func isLikelyAdjectiveLexiconEntry(_ entry: LexiconEntry) -> Bool {
        let normalizedSource = normalizedLookupText(entry.sourceTerm)
        let normalizedTarget = normalizedLookupText(entry.targetTerm)

        guard normalizedSource.split(separator: " ").count == 1,
              normalizedTarget.split(separator: " ").count == 1 else {
            return false
        }

        return Self.commonFrenchAdjectiveWords.contains(normalizedSource) ||
            Self.commonGermanAdjectiveWords.contains(normalizedTarget) ||
            Self.frenchAdjectiveSuffixes.contains(where: normalizedSource.hasSuffix) ||
            Self.germanAdjectiveSuffixes.contains(where: normalizedTarget.hasSuffix)
    }

    func looksLikeFrenchInfinitiveLexiconWord(_ normalizedSource: String) -> Bool {
        let words = normalizedSource.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return false }

        let infinitiveCandidate: String
        if words.count == 1 {
            infinitiveCandidate = words[0]
        } else if words.count == 2, ["se", "s"].contains(words[0]) {
            infinitiveCandidate = words[1]
        } else {
            return false
        }

        guard infinitiveCandidate.count >= 4 else { return false }
        return ["er", "ir", "re", "oir"].contains(where: infinitiveCandidate.hasSuffix)
    }

    func looksLikeGermanVerbLexiconWord(_ normalizedTarget: String) -> Bool {
        let words = normalizedTarget.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return false }

        if normalizedTarget.hasPrefix("sich ") || normalizedTarget.hasPrefix("etw ") || normalizedTarget.hasPrefix("jdn ") {
            return true
        }

        guard words.count <= 2, let first = words.first else { return false }
        guard !germanArticleHints.contains(first) else { return false }

        if Self.commonGermanVerbWords.contains(first) {
            return true
        }

        return first.count >= 5 && ["en", "eln", "ern"].contains(where: first.hasSuffix)
    }

    private static let commonFrenchAdjectiveWords: Set<String> = [
        "grand", "grande", "petit", "petite", "bon", "bonne", "mauvais", "mauvaise",
        "jeune", "vieux", "vieille", "beau", "belle", "joli", "jolie", "gentil",
        "gentille", "heureux", "heureuse", "triste", "rapide", "lent", "lente",
        "facile", "difficile", "important", "importante", "possible", "impossible",
        "fort", "forte", "faible", "prochain", "prochaine", "nouveau", "nouvelle",
        "vrai", "vraie", "faux", "fausse", "propre", "sale", "calme", "super"
    ]

    private static let commonGermanAdjectiveWords: Set<String> = [
        "groß", "klein", "gut", "schlecht", "jung", "alt", "schon", "schön", "neu",
        "schnell", "langsam", "leicht", "schwer", "wichtig", "moglich", "möglich",
        "ruhig", "stark", "schwach", "sauber", "schmutzig", "super", "traurig",
        "glucklich", "glücklich", "froh", "kalt", "warm", "heiß", "heiss"
    ]

    private static let commonGermanVerbWords: Set<String> = [
        "sein", "haben", "machen", "gehen", "kommen", "geben", "nehmen", "finden",
        "bleiben", "heißen", "heissen", "lernen", "arbeiten", "sprechen", "fragen",
        "antworten", "helfen", "rufen", "suchen", "spielen", "wohnen", "lieben",
        "brauchen", "sehen", "hören", "fühlen", "fuhlen", "denken", "bringen"
    ]

    private static let frenchAdjectiveSuffixes = [
        "able", "ible", "eux", "euse", "if", "ive", "ique", "aire", "al", "ale",
        "el", "elle", "ant", "ante", "ent", "ente", "ois", "oise", "ais", "aise"
    ]

    private static let germanAdjectiveSuffixes = [
        "ig", "lich", "isch", "los", "sam", "bar", "haft", "frei", "reich", "arm"
    ]
}
