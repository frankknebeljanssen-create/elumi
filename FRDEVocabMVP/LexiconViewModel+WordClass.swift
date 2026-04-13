import Foundation

extension LexiconViewModel {
    func lexiconWordClassMarker(for entry: PreparedLexiconEntry) -> LexiconWordClassMarker? {
        if entry.displayCardType == .phrases { return .phrase }

        let hasNoun = entry.entries.contains(where: { $0.isGermanNoun })
        let hasNonNoun = entry.entries.contains(where: { !$0.isGermanNoun })

        if hasNoun && !hasNonNoun { return .noun }
        if hasNonNoun && !hasNoun {
            // Use StandardVocabularyLoader for precise word class
            let sourceTerms = entry.entries.map(\.sourceTerm)
            if sourceTerms.contains(where: { StandardVocabularyLoader.isVerb($0) }) {
                return .verb
            }
            return .adjective
        }

        return nil
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
