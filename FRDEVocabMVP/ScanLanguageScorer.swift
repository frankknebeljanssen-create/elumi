import Foundation
import NaturalLanguage

struct ScanLanguageScorer {
    func isSourceColumnFirst(
        first: String,
        second: String,
        sourceLanguage: StudyLanguage
    ) -> Bool {
        let firstSourceScore = sourceLanguageScore(for: first, language: sourceLanguage)
        let firstGermanScore = germanScore(for: first)
        let secondSourceScore = sourceLanguageScore(for: second, language: sourceLanguage)
        let secondGermanScore = germanScore(for: second)

        let sourceFirstScore = firstSourceScore + secondGermanScore
        let germanFirstScore = firstGermanScore + secondSourceScore

        return sourceFirstScore >= germanFirstScore
    }

    func sourceLanguageScore(
        for text: String,
        language: StudyLanguage
    ) -> Double {
        switch language {
        case .french:
            return frenchScore(for: text)
        case .english:
            return englishScore(for: text)
        }
    }

    func germanScore(for text: String) -> Double {
        languageScore(for: text, language: .german) + heuristicGermanScore(for: text)
    }

    func normalizedWords(in text: String) -> [String] {
        text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    func dictionaryCoverageScore(
        for text: String,
        language: StudyLanguage
    ) -> Double {
        let tokens = normalizedWords(in: text)
        guard !tokens.isEmpty else { return 0 }

        let lexicon = DataStore.lexiconWordSet(for: language)
        let matchCount = tokens.filter { lexicon.contains($0) }.count
        return (Double(matchCount) / Double(tokens.count)) * 0.9
    }

    func germanDictionaryCoverageScore(for text: String) -> Double {
        let tokens = normalizedWords(in: text)
        guard !tokens.isEmpty else { return 0 }

        let matchCount = tokens.filter { DataStore.germanLexiconWordSet.contains($0) }.count
        return Double(matchCount) / Double(tokens.count)
    }

    func sourceLexiconCoverageScore(
        for text: String,
        language: StudyLanguage
    ) -> Double {
        let tokens = normalizedWords(in: text)
        guard !tokens.isEmpty else { return 0 }

        let lexicon = DataStore.lexiconWordSet(for: language)
        let matchCount = tokens.filter { lexicon.contains($0) }.count
        return Double(matchCount) / Double(tokens.count)
    }

    private func frenchScore(for text: String) -> Double {
        languageScore(for: text, language: .french) + heuristicFrenchScore(for: text)
    }

    private func englishScore(for text: String) -> Double {
        languageScore(for: text, language: .english) + heuristicEnglishScore(for: text)
    }

    private func languageScore(for text: String, language: NLLanguage) -> Double {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text.lowercased())
        let hypotheses = recognizer.languageHypotheses(withMaximum: 2)
        return hypotheses[language] ?? 0
    }

    private func heuristicFrenchScore(for text: String) -> Double {
        let words = normalizedWords(in: text)
        let joined = words.joined(separator: " ")

        var score = 0.0

        let frenchMarkers = [
            "je", "tu", "il", "elle", "nous", "vous", "ils", "elles",
            "bonjour", "merci", "oui", "non", "avec", "pour", "dans",
            "est", "suis", "avoir", "etre", "être", "une", "des", "les",
            "un", "du", "de", "la", "le", "au", "aux", "pas", "que"
        ]

        for marker in frenchMarkers where words.contains(marker) {
            score += 0.55
        }

        if joined.contains("j ") || joined.contains("qu ") || joined.contains("c ") {
            score += 0.35
        }

        if text.range(of: "[àâçéèêëîïôùûüÿœæ]", options: .regularExpression) != nil {
            score += 1.1
        }

        return score
    }

    private func heuristicGermanScore(for text: String) -> Double {
        let words = normalizedWords(in: text)
        let joined = words.joined(separator: " ")

        var score = 0.0

        let germanMarkers = [
            "ich", "du", "er", "sie", "wir", "ihr", "danke", "bitte",
            "und", "mit", "für", "nicht", "ein", "eine", "der", "die",
            "das", "dem", "den", "ist", "bin", "habe", "haben", "gut",
            "heute", "morgen", "wo", "was", "wie"
        ]

        for marker in germanMarkers where words.contains(marker) {
            score += 0.55
        }

        if text.range(of: "[äöüß]", options: .regularExpression) != nil {
            score += 1.1
        }

        if joined.contains("sch") || joined.contains("ein ") || joined.contains("ich") {
            score += 0.3
        }

        return score
    }

    private func heuristicEnglishScore(for text: String) -> Double {
        let words = normalizedWords(in: text)
        let joined = words.joined(separator: " ")

        var score = 0.0

        let englishMarkers = [
            "i", "you", "he", "she", "we", "they", "hello", "please",
            "thanks", "thank", "where", "what", "when", "how", "with",
            "for", "school", "book", "friend", "family", "house", "city",
            "day", "night", "food", "water", "ready", "today", "tomorrow",
            "mother", "father", "sister", "brother", "teacher", "student",
            "table", "chair", "window", "door", "street", "river", "garden",
            "question", "answer", "lesson", "page", "unit", "poet", "writer",
            "song", "music", "breakfast", "lunch", "dinner", "summer", "winter",
            "spring", "autumn", "morning", "evening", "animal", "bird", "horse"
        ]

        for marker in englishMarkers where words.contains(marker) {
            score += 0.55
        }

        if joined.contains("th") || joined.contains("ing") || joined.contains("you") {
            score += 0.25
        }

        if text.range(
            of: #"(?i)\b[a-z]*w[a-z]*\b|\b[a-z]*k[a-z]*\b|\b[a-z]*y[a-z]*\b"#,
            options: .regularExpression
        ) != nil {
            score += 0.2
        }

        if text.range(
            of: #"(?i)\b[a-z]*(sh|th|ch|ck|ee|oo|ea|ow|ay|igh)[a-z]*\b"#,
            options: .regularExpression
        ) != nil {
            score += 0.28
        }

        return score
    }
}
