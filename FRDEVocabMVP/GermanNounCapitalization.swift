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
/// **Regel (fix, nicht konfigurierbar), Stand 2026-08-05:**
///
/// 1. **Quellschreibweise schlägt Vermutung.** Enthält der Text schon
///    irgendwo einen Großbuchstaben, bleibt er **unverändert**. Die
///    Lexikon-Daten sind kuratiert und korrekt geschrieben; jede
///    Heuristik darüber kann nur verschlimmbessern.
/// 2. Nur wenn **gar nichts** großgeschrieben ist, wird das **letzte**
///    Wort kapitalisiert — im deutschen Nominalsyntagma steht der Kopf
///    (das eigentliche Nomen) hinten. Führende Artikel bleiben klein.
///
/// **Warum Punkt 1 (Bug-Fix 2026-08-05):** Die alte Regel lautete
/// „kapitalisiere das erste Nicht-Artikel-Wort" und nahm damit an, dass
/// hinter dem Artikel direkt das Nomen steht. Bei „Artikel + Adjektiv +
/// Nomen" traf sie zwangsläufig das Adjektiv: aus „die schlechte Note"
/// wurde „die Schlechte Note" (User-Report). Eine Auszählung der
/// Lexikon-DB zeigte das Ausmaß: von 35.426 Nomen-Zeilen waren 35.365
/// bereits korrekt geschrieben, 5.650 wurden durch die Regel **kaputt
/// gemacht** und nur rund 15 tatsächlich verbessert. Die Heuristik hat
/// also gut 90-mal mehr Schaden angerichtet als Nutzen gestiftet.
///
/// **Warum Punkt 2 statt „erstes Nicht-Artikel-Wort":** Für den
/// verbleibenden Fall (Scan-KI liefert alles klein) ist das letzte Wort
/// die verlässlichere Wahl — „die schlechte note" → „die schlechte
/// Note" statt „die Schlechte note".
///
/// Bekannte Grenze: Bei mehrgliedrigen Phrasen mit Präposition („der
/// regenschutz für den kinderwagen") wird nur der hintere Kopf
/// großgeschrieben. Das ist unvollständig, aber nicht falsch — und
/// betrifft ausschließlich vollständig kleingeschriebene Eingaben.
///
/// Beispiele:
///   • `"uhr"` → `"Uhr"`
///   • `"die uhr"` → `"die Uhr"`
///   • `"die schlechte note"` → `"die schlechte Note"`
///   • `"die schlechte Note"` → unverändert (Quelle hat schon Großbuchstaben)
///   • `"3D-Drucker"` → unverändert
///   • `"Uhr"` → `"Uhr"` (idempotent)
enum GermanNounCapitalization {

    /// Deutsche Artikel (bestimmt + unbestimmt, alle Kasus).
    /// Wörter, die mit einer dieser Formen identisch sind (im Lower-
    /// case, ohne Interpunktion), bleiben am Satzanfang klein.
    static let articleSet: Set<String> = [
        "der", "die", "das", "den", "dem", "des",
        "ein", "eine", "einen", "einem", "einer", "eines"
    ]

    /// Kapitalisiert den Nomen-Kopf in `target` — aber **nur**, wenn die
    /// Quelle gar keine Großschreibung mitbringt. Idempotent.
    ///
    /// Name aus Kompatibilitätsgründen unverändert (drei Call-Sites);
    /// die Regel dahinter ist seit 2026-08-05 eine andere, siehe
    /// Typ-Dokumentation.
    static func capitalizeFirstNounWord(in target: String) -> String {
        guard !target.isEmpty else { return target }

        // **Quellschreibweise schlägt Vermutung.** Ein einziger
        // Großbuchstabe irgendwo im Text genügt als Beleg, dass die
        // Quelle bewusst geschrieben wurde — dann hat keine Heuristik
        // hier etwas verloren. Das schützt „die schlechte Note" ebenso
        // wie „3D-Drucker" oder „das pH-Messgerät".
        if target.contains(where: { $0.isUppercase }) {
            return target
        }

        let parts = target.split(separator: " ", omittingEmptySubsequences: false)

        // Index des letzten nicht-leeren Tokens = Kopf des Syntagmas.
        // Im Deutschen steht das eigentliche Nomen hinten („die schlechte
        // Note"), deshalb hier und nicht vorne kapitalisieren.
        guard let headIndex = parts.indices.last(where: { !parts[$0].isEmpty }) else {
            return target
        }

        var result: [String] = []
        result.reserveCapacity(parts.count)

        for (index, part) in parts.enumerated() {
            let piece = String(part)
            guard index == headIndex, let first = piece.first, first.isLowercase else {
                result.append(piece)
                continue
            }
            // Reine Artikel nie kapitalisieren — greift nur, wenn der
            // Text ausschließlich aus einem Artikel besteht.
            let bare = piece.trimmingCharacters(in: .punctuationCharacters).lowercased()
            if articleSet.contains(bare) {
                result.append(piece)
            } else {
                result.append(first.uppercased() + piece.dropFirst())
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
