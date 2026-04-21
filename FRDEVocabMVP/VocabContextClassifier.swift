import Foundation

/// Kontext-Klassifikator für mehrdeutige französische Wörter.
///
/// Löst genau den Fall, den der User im Spec beschrieben hat:
///   • „le" → Artikel (vor Nomen) ODER Pronomen (nach/vor Verb)
///   • „la" → Artikel ODER Pronomen
///   • „les" → Artikel (Plural) ODER Pronomen („sie/ihn" → beide)
///
/// Die App hat auf gespeicherten `VocabularyItem`-Ebene nur **zwei**
/// Kontext-Quellen: den französischen Eintrag selbst und seine
/// deutsche Übersetzung. Die deutsche Seite ist in den meisten Fällen
/// entscheidend:
///
///   Original: „le"
///   Deutsch: „der"  → Artikel
///   Deutsch: „ihn"  → Pronomen
///   Deutsch: „es"   → Pronomen
///
/// Bei Scan-Zeit hat das LLM schon seinen `word_class`-Tag gesetzt —
/// dieser Classifier ist die **Fallback-Schicht**, wenn
///   • `word_class == nil` (alter Eintrag vor der Prompt-Version)
///   • `word_class == "article"` aber Deutsch ist ein Pronomen-Wort →
///     Korrektur zu „pronoun"
///
/// Lightweight: keine externen NLP-Libs, keine Satzkontext-Analyse —
/// reicht für die ambiguen Fälle, die in gespeicherten Listen
/// vorkommen.
enum VocabContextClassifier {

    /// Mögliche Wortklassen, die dieser Classifier refined. Identisch
    /// zum `word_class`-String-Format des AI-Prompts.
    enum RefinedClass: String {
        case article
        case pronoun
        case noun
        case verb
        case adjective
        case adverb
        case phrase

        var rawWordClass: String { rawValue }
    }

    /// Liefert eine kontext-refined Wortklasse, wenn der Eintrag einer
    /// der bekannten Ambiguitäten entspricht. Nil, wenn keine Änderung
    /// zum bestehenden Stand sinnvoll ist.
    ///
    /// - Parameters:
    ///   - french: Der französische Eintrag (z. B. „le").
    ///   - german: Die deutsche Übersetzung (z. B. „ihn" oder „der").
    ///   - storedWordClass: Das aktuelle `word_class`-Label, falls
    ///     vorhanden (hilft uns, nur dort zu überschreiben, wo nötig).
    static func refinedWordClass(
        french: String,
        german: String,
        storedWordClass: String? = nil
    ) -> RefinedClass? {
        let fr = french.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let de = german.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // Nur prüfen, wenn der French-Teil einer der bekannten
        // ambiguousen Tokens ist. Das sind französische kurze Wörter,
        // die sowohl Artikel als auch Pronomen sein können.
        let ambiguousTokens: Set<String> = ["le", "la", "les", "l'", "l’"]
        guard ambiguousTokens.contains(fr) else { return nil }

        // Wenn die deutsche Übersetzung ein bekannter Artikel ist →
        // französisch ist auch Artikel.
        let germanArticles: Set<String> = [
            "der", "die", "das", "den", "dem", "des",
            "ein", "eine", "einer", "einem", "einen", "eines"
        ]
        if germanArticles.contains(de) {
            if storedWordClass?.lowercased() != "article" {
                return .article
            }
            return .article
        }

        // Wenn die deutsche Übersetzung ein Objekt-/Personalpronomen
        // ist → französisch ist Pronomen.
        let germanObjectPronouns: Set<String> = [
            "ihn", "sie", "es", "ihm", "ihr", "ihnen", "ihre", "ihren",
            "mich", "dich", "uns", "euch"
        ]
        if germanObjectPronouns.contains(de) {
            return .pronoun
        }

        // Ambivalent — wir überschreiben nichts.
        return nil
    }

    // MARK: - Convenience

    /// Liefert `.pronoun`, wenn die Kombination eindeutig Pronomen ist.
    /// Nützlich, um im UI den Artikel NICHT vor „le" zu setzen, wenn
    /// das Wort hier als Pronomen verwendet wird.
    static func isLikelyPronoun(french: String, german: String) -> Bool {
        refinedWordClass(french: french, german: german) == .pronoun
    }
}
