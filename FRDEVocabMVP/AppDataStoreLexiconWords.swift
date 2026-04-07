import Foundation

enum DataStoreLexiconWordSupport {
    static let ocrCustomWords: [String] = Array(
        expandedFrenchLexiconWordSet
            .union(expandedGermanLexiconWordSet)
    ).sorted()

    static func lexiconWordSet(for language: StudyLanguage) -> Set<String> {
        switch language {
        case .french:
            return expandedFrenchLexiconWordSet
        case .english:
            return []
        }
    }

    static let germanLexiconWordSet: Set<String> = expandedGermanLexiconWordSet
    static let likelyGermanNounSet: Set<String> = makeLikelyGermanNounSet()

    private static let baseFrenchLexiconWordSet: Set<String> = Set(
        normalizedLexiconWords(from: OfflineFrenchGermanKnowledgePool.frenchSourceTerms) +
        BuiltInVocabularyCatalog.frenchBeginnerLexiconWords +
        BuiltInVocabularyCatalog.frenchIntermediateLexiconWords +
        BuiltInVocabularyCatalog.frenchAdvancedLexiconWords
    )

    private static let baseGermanLexiconWordSet: Set<String> = Set(
        normalizedLexiconWords(from: OfflineFrenchGermanKnowledgePool.germanTargetTerms) +
        BuiltInVocabularyCatalog.germanValidationLexiconWords
    )

    private static let expandedFrenchLexiconWordSet: Set<String> = expandedLexiconWords(
        from: baseFrenchLexiconWordSet,
        morphology: .french
    )

    private static let expandedGermanLexiconWordSet: Set<String> = expandedLexiconWords(
        from: baseGermanLexiconWordSet,
        morphology: .german
    )

    private static func makeLikelyGermanNounSet() -> Set<String> {
        // Keep this independent from `defaultItems` and other `VocabularyItem` factories.
        // `VocabularyItem` normalization uses `germanDisplayText`, which consults this noun set
        // for phrase capitalization. Referencing `defaultItems` here creates a runtime
        // initialization cycle that can crash when Quiz loads the built-in data.
        var nouns = Set(
            BuiltInVocabularyCatalog.germanValidationLexiconWords.filter { !$0.isEmpty && !$0.contains(" ") }
        )

        nouns.formUnion(
            OfflineFrenchGermanKnowledgePool.translatedRecords
                .filter { $0.cardType == .words }
                .flatMap { normalizedGermanNounCandidates(from: $0.targetTerm) }
        )

        nouns.formUnion(["hunger", "durst", "frage", "thema", "tisch", "reservierung"])
        return nouns
    }

    private static func normalizedGermanNounCandidates(from text: String) -> [String] {
        let normalized = normalizedLookupText(text)
        guard !normalized.isEmpty else { return [] }

        let words = normalized.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return [] }

        if let first = words.first, germanArticleHints.contains(first) {
            let noun = words.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return noun.isEmpty ? [] : [noun]
        }

        if words.count <= 2 {
            return [normalized]
        }

        return []
    }

    private static func normalizedLexiconWords(from lines: [String]) -> [String] {
        lines
            .flatMap { line in
                line
                    .lowercased()
                    .folding(options: String.CompareOptions.diacriticInsensitive, locale: Locale.current)
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
            }
            .filter { !$0.isEmpty }
    }

    private enum LexiconMorphology {
        case french
        case german
    }

    private static func expandedLexiconWords(
        from baseWords: Set<String>,
        morphology: LexiconMorphology
    ) -> Set<String> {
        Set(
            baseWords
                .flatMap { lexiconVariants(for: $0, morphology: morphology) }
                .compactMap(normalizedLexiconToken(_:))
        )
    }

    private static func lexiconVariants(
        for word: String,
        morphology: LexiconMorphology
    ) -> Set<String> {
        guard let token = normalizedLexiconToken(word) else { return [] }

        var variants: Set<String> = [token]
        let length = token.count

        guard length >= 3 else { return variants }

        switch morphology {
        case .french:
            variants.insert(token + "s")
            variants.insert(token + "es")
            variants.insert(token + "ment")

            if token.hasSuffix("er") {
                let stem = String(token.dropLast(2))
                if stem.count >= 2 {
                    ["e", "es", "ons", "ez", "ent", "é", "ée", "és", "ées", "ant", "era", "erai", "eront"]
                        .forEach { variants.insert(stem + $0) }
                }
            }

            if token.hasSuffix("ir") {
                let stem = String(token.dropLast(2))
                if stem.count >= 2 {
                    ["is", "it", "issons", "issez", "issent", "ira", "irai", "iront"]
                        .forEach { variants.insert(stem + $0) }
                }
            }

            if token.hasSuffix("re") {
                let stem = String(token.dropLast(2))
                if stem.count >= 2 {
                    ["s", "", "ons", "ez", "ent", "u", "ue", "us", "ues"]
                        .forEach { variants.insert(stem + $0) }
                }
            }

            if token.hasSuffix("tion") {
                variants.insert(String(token.dropLast(4)) + "tions")
            }

            if token.hasSuffix("eux") {
                variants.insert(String(token.dropLast(1)) + "se")
                variants.insert(String(token.dropLast(1)) + "ses")
            }

            if token.hasSuffix("if") {
                variants.insert(String(token.dropLast()) + "ve")
                variants.insert(String(token.dropLast()) + "ves")
            }

            if token.hasSuffix("e") {
                variants.insert(token + "s")
            } else {
                variants.insert(token + "e")
                variants.insert(token + "es")
            }

        case .german:
            ["e", "en", "er", "n", "s", "em", "es"].forEach { variants.insert(token + $0) }

            if token.hasSuffix("e") {
                variants.insert(token + "n")
                variants.insert(token + "r")
                variants.insert(token + "m")
            }

            if token.hasSuffix("er") {
                variants.insert(token + "n")
                variants.insert(token + "s")
            }

            if token.hasSuffix("ung") {
                variants.insert(token + "en")
            }

            if token.hasSuffix("keit") || token.hasSuffix("heit") {
                variants.insert(token + "en")
            }

            if token.hasSuffix("isch") || token.hasSuffix("lich") || token.hasSuffix("ig") {
                ["e", "en", "em", "er", "es"].forEach { variants.insert(token + $0) }
            }
        }

        return variants.filter { normalizedLexiconToken($0) != nil }
    }

    private static func normalizedLexiconToken(_ token: String) -> String? {
        let cleaned = token
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .folding(options: String.CompareOptions.diacriticInsensitive, locale: Locale.current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .joined()

        guard cleaned.count >= 2, cleaned.count <= 28 else { return nil }
        return cleaned
    }
}
