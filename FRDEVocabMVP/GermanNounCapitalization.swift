import Foundation

/// **Single Source of Truth für deutsche Nomen-Kapitalisierung**
/// (2026-04-25 Refactor).
///
/// Vorher: drei parallele Implementierungen derselben Regel in
///   • `ScanAIPostProcessor.capitalizeFirstNounWord`
///   • `PhraseNounCapitalizationMigration.capitalizeFirstNounWord`
///   • `StandardVocabularyLoader.normalizeGermanNounTarget`
///
/// Jetzt: alle drei Call-Sites delegieren hierher — genau eine Regel-
/// definition, genau ein Artikel-Set. Änderungen (neue Artikel, andere
/// Regel) müssen nur an einer Stelle nachgezogen werden.
///
/// **Regel (fix, nicht konfigurierbar):**
/// Das **erste Nicht-Artikel-Wort** im deutschen Zieltext wird
/// kapitalisiert; alle weiteren Wörter bleiben unangetastet. Artikel
/// (`der/die/das/den/dem/des/ein/eine/…`) am Wortanfang bleiben klein.
/// Idempotent — bereits großgeschriebene Nomen werden nicht angefasst.
///
/// Beispiele:
///   • `"uhr"` → `"Uhr"`
///   • `"die uhr"` → `"die Uhr"`
///   • `"Uhr"` → `"Uhr"` (idempotent)
///   • `"der morgen"` → `"der Morgen"`
///   • `"schnell"` (Adverb) — nicht betroffen, wird nur über
///     `normalizeGermanNounTarget` mit `wordClass == "noun"`-Gate
///     gelöst
enum GermanNounCapitalization {

    /// Deutsche Artikel (bestimmt + unbestimmt, alle Kasus).
    /// Wörter, die mit einer dieser Formen identisch sind (im Lower-
    /// case, ohne Interpunktion), bleiben am Satzanfang klein.
    static let articleSet: Set<String> = [
        "der", "die", "das", "den", "dem", "des",
        "ein", "eine", "einen", "einem", "einer", "eines"
    ]

    /// Kapitalisiert das erste Nicht-Artikel-Wort in `target`.
    /// Alle weiteren Wörter bleiben unverändert. Idempotent.
    static func capitalizeFirstNounWord(in target: String) -> String {
        guard !target.isEmpty else { return target }

        let parts = target.split(separator: " ", omittingEmptySubsequences: false)
        var result: [String] = []
        var capitalizedFirstNoun = false

        for part in parts {
            let piece = String(part)
            if piece.isEmpty {
                result.append(piece)
                continue
            }
            if !capitalizedFirstNoun {
                let bare = piece.trimmingCharacters(in: .punctuationCharacters).lowercased()
                if articleSet.contains(bare) {
                    result.append(piece)
                } else {
                    if let first = piece.first, first.isLowercase {
                        result.append(first.uppercased() + piece.dropFirst())
                    } else {
                        result.append(piece)
                    }
                    capitalizedFirstNoun = true
                }
            } else {
                result.append(piece)
            }
        }
        return result.joined(separator: " ")
    }

    /// POS-gated Variante: wendet `capitalizeFirstNounWord` NUR an,
    /// wenn `wordClass == "noun"` / `"nomen"` / `"substantiv"` ist.
    /// Für alle anderen Wortarten bleibt der Text unverändert —
    /// schützt Verben, Adjektive usw. vor falscher Großschreibung.
    static func normalizeGermanNounTarget(_ target: String, wordClass: String?) -> String {
        let nounWordClasses: Set<String> = ["noun", "nomen", "substantiv"]
        guard nounWordClasses.contains(wordClass?.lowercased() ?? ""),
              !target.isEmpty else {
            return target
        }
        return capitalizeFirstNounWord(in: target)
    }
}
