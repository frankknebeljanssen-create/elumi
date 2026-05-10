// ChatMarkerParser.swift
// **Léa-Chat MVP Schritt 2A (2026-05-10)** — Parser für die Marker,
// die Léa per System-Prompt am Ende ihrer Nachrichten anhängt.
//
// **Schritt 2B-1 (2026-05-10)** — Erweitert um zwei neue Marker-Sorten:
//   • `[VOCAB: <wort>]` — Léa markiert ein vom User korrekt benutztes
//     Lektionswort. Marker wird komplett aus dem cleanText entfernt;
//     das Wort selbst wandert in `vocabUsed` und wird vom iOS-Client
//     in der zugehörigen User-Bubble grün hinterlegt.
//   • `[NEW: <wort>|<deutsche_übersetzung>]` — Léa führt ein Wort ein,
//     das nicht in der aktiven Wortschatz-Liste steht. Der Marker wird
//     durch das Wort selbst ersetzt (cleanText behält das Wort), die
//     Übersetzung wandert in `newWords`. iOS-Client unterstreicht das
//     Wort blau und öffnet bei Tap einen Tooltip.
//
// **Marker-Format-Übersicht** (single-line, irgendwo in der Nachricht):
//   • Korrektur am Ende: `(💡 [FEHLER: <user-text>] → Kleiner Tipp:
//     <deutsche-erklärung>)`
//   • VOCAB inline: `[VOCAB: ça va]`
//   • NEW inline: `[NEW: vacances|Ferien]`
//
// Der Parser läuft sequenziell:
//   1. VOCAB-Marker: aus dem Text entfernen, Wörter sammeln.
//   2. NEW-Marker: durch das reine Wort ersetzen, Übersetzung sammeln.
//   3. FEHLER-Marker: aus dem Text entfernen, FoundError sammeln.
//
// Robust gegen malformed Marker — bei Regex-Compile-Fail oder
// unerwartetem Format wird der Text 1:1 als cleanText durchgereicht
// und das jeweilige Marker-Array bleibt leer. Kein Crash, kein
// User-sichtbarer Fehler.
//
// Spec sieht max 1 Korrektur und max wenige VOCAB-/NEW-Marker pro
// Nachricht vor — der Parser akzeptiert aber N pro Sorte als Defensive,
// falls Léa sich nicht an die Spec hält.

import Foundation

/// Ein einzelner Korrektur-Treffer aus Léas Antwort.
struct FoundError: Equatable {
    /// Der Text, den der User falsch geschrieben hat — exakt wie aus
    /// dem `[FEHLER: …]`-Marker extrahiert. Wird im iOS-Client gegen
    /// den User-Message-Text gematcht (Substring-Range), um die
    /// Underline-Span zu setzen.
    let userText: String

    /// Léas deutsche Erklärung mit korrekter Form (Tipp-Text aus
    /// `Kleiner Tipp: …`). Wird in der `CorrectionCardView` gerendert.
    let germanTip: String
}

/// **Schritt 2B-1** — Ein einzelnes neues Wort aus einem `[NEW: …|…]`-
/// Marker. Wird auf der Léa-Message persistiert (JSON-encoded), damit
/// die Bubble-View das Wort blau unterstreichen und der Tooltip die
/// Übersetzung anzeigen kann.
struct FoundNewWord: Equatable, Codable {
    /// Das französische Wort, exakt wie Léa es geschrieben hat
    /// (inklusive Artikel/Apostroph wenn vorhanden).
    let word: String

    /// Deutsche Übersetzung, kommt direkt aus Léas Marker (rechte
    /// Seite des `|`-Trenners). Frei-Text, nicht weiter validiert.
    let translation: String
}

/// Ergebnis des Parsings: Léas Text ohne Korrektur-/VOCAB-Marker
/// (NEW-Wörter bleiben im Text, nur die Marker-Brackets sind weg)
/// + alle Marker-Daten als getrennte Listen.
struct ParsedMessage: Equatable {
    let cleanText: String
    let foundErrors: [FoundError]

    /// **Schritt 2B-1** — Lektionswörter aus `[VOCAB: …]`-Markern.
    /// Reihenfolge entspricht der Vorkommens-Reihenfolge in Léas
    /// rohem Text (forward).
    let vocabUsed: [String]

    /// **Schritt 2B-1** — Neue Wörter aus `[NEW: …|…]`-Markern.
    /// Reihenfolge entspricht Vorkommens-Reihenfolge.
    let newWords: [FoundNewWord]
}

enum ChatMarkerParser {
    /// **Regex-Pattern** für den Korrektur-Marker.
    ///
    /// Aufbau:
    ///   • `\(💡` — öffnende Klammer + Glühbirnen-Emoji + optionales
    ///     Whitespace
    ///   • `\[FEHLER:` literal
    ///   • `([^\]]+)` — Group 1 = User-Text (alles bis schließendes ])
    ///   • `\]\s*→\s*Kleiner\s+Tipp:` literal mit Whitespace-Toleranz
    ///   • `(.+)` — Group 2 = deutsche Erklärung, GREEDY mit
    ///     dotMatchesLineSeparators
    ///   • `\)\s*$` — schließende Klammer am Ende der Message
    ///
    /// **Smoke-Bug-Fix 2B-2B (2026-05-10)** — vorheriges Pattern
    /// `([^)]+)\)` brach zu früh ab, sobald die deutsche Erklärung
    /// selbst eine Klammer enthielt (z.B. `Es heißt "à l'école"
    /// (nicht "au"), weil...`). Das innere `)` wurde als Marker-
    /// Close gewertet, der Rest landete in Léas Bubble. Greedy
    /// `(.+)` mit `\)\s*$`-End-Anchor backtracked bis zur LETZTEN
    /// schließenden Klammer am Message-Ende — Spec sieht Marker
    /// ohnehin nur am Ende vor. Trade-off: bei (spec-widrigen)
    /// Multi-FEHLER-Markern in einer Message würde der Greedy
    /// alle als einen erfassen — akzeptabel, weil Spec max 1
    /// erlaubt.
    private static let errorPattern = #"\(💡\s*\[FEHLER:\s*([^\]]+)\]\s*→\s*Kleiner\s+Tipp:\s*(.+)\)\s*$"#

    /// **Schritt 2B-1** — VOCAB-Marker. Group 1 = Wort/Phrase.
    /// Frisst alles bis zur schließenden Bracket — Whitespace-trim
    /// passiert beim Extract.
    private static let vocabPattern = #"\[VOCAB:\s*([^\]]+)\]"#

    /// **Schritt 2B-1** — NEW-Marker. Group 1 = Wort (keine Pipe/
    /// Bracket erlaubt), Group 2 = Übersetzung (keine Bracket).
    /// Pipes IN der Übersetzung wären Edge-Case (Léa würde
    /// "Ferien|Urlaub" schreiben) — der Pattern erlaubt das, weil
    /// Group 2 alles bis zur schließenden Bracket frisst.
    private static let newPattern = #"\[NEW:\s*([^\|\]]+)\|([^\]]+)\]"#

    private static let errorRegex: NSRegularExpression? = {
        // **2B-2B Smoke-Fix** — `dotMatchesLineSeparators` damit der
        // Greedy `.+` auch über Newlines hinweggreift; manche
        // Léa-Antworten haben einen Zeilenumbruch zwischen dem
        // Konversationstext und dem Marker.
        try? NSRegularExpression(pattern: errorPattern, options: [.dotMatchesLineSeparators])
    }()
    private static let vocabRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: vocabPattern, options: [])
    }()
    private static let newRegex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: newPattern, options: [])
    }()

    /// Parst Léas Raw-Antwort und extrahiert alle Marker. Bei Parser-
    /// Failure (Regex-Compile-Fehler, unerwartetes Format) wird der
    /// Raw-Text 1:1 als cleanText durchgereicht und alle Marker-Arrays
    /// bleiben leer.
    static func parseLeaMessage(_ rawText: String) -> ParsedMessage {
        // Wir arbeiten auf einer mutablen Kopie und strippen Marker
        // sequenziell. Reihenfolge: VOCAB → NEW → FEHLER. Begründung:
        //   • VOCAB raus zuerst, weil die Marker das Lektionswort
        //     EXAKT umschließen — unabhängig von anderen Markern.
        //   • NEW als zweites: ersetzt den ganzen Marker durch das
        //     reine Wort, Wort bleibt im Text. Wenn nach VOCAB-Strip
        //     bereits Whitespace-Reste übrig sind, stören sie hier
        //     nicht (Pattern matched nur den NEW-Block).
        //   • FEHLER zuletzt: am Ende einer Nachricht, frisst alles
        //     in der Klammer.
        // Final: trimmen für saubere Bubble-Präsentation.
        var working = rawText

        let vocabUsed = extractAndStripVocab(in: &working)
        let newWords = extractAndReplaceNewMarkers(in: &working)
        let foundErrors = extractAndStripErrors(in: &working)

        let cleanText = working.trimmingCharacters(in: .whitespacesAndNewlines)
        return ParsedMessage(
            cleanText: cleanText,
            foundErrors: foundErrors,
            vocabUsed: vocabUsed,
            newWords: newWords
        )
    }

    // MARK: - VOCAB-Extraction

    /// Sammelt alle `[VOCAB: wort]`-Marker im Text, entfernt sie
    /// vollständig (inklusive Marker-Brackets), und gibt die Wörter
    /// in Vorkommens-Reihenfolge zurück.
    private static func extractAndStripVocab(in text: inout String) -> [String] {
        guard let regex = vocabRegex else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard !matches.isEmpty else { return [] }

        // Wörter forward sammeln (für stabile Reihenfolge im UI).
        var words: [String] = []
        for match in matches {
            guard match.numberOfRanges >= 2,
                  let wordRange = Range(match.range(at: 1), in: text)
            else { continue }
            let word = String(text[wordRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !word.isEmpty {
                words.append(word)
            }
        }

        // Marker reverse strippen, damit NSRange-Indizes stabil bleiben.
        for match in matches.reversed() {
            if let range = Range(match.range, in: text) {
                text.removeSubrange(range)
            }
        }
        return words
    }

    // MARK: - NEW-Extraction

    /// Sammelt alle `[NEW: wort|übersetzung]`-Marker im Text, ersetzt
    /// sie durch das reine Wort (cleanText behält das Wort lesbar),
    /// und gibt die FoundNewWord-Tupel in Vorkommens-Reihenfolge
    /// zurück.
    private static func extractAndReplaceNewMarkers(in text: inout String) -> [FoundNewWord] {
        guard let regex = newRegex else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard !matches.isEmpty else { return [] }

        // FoundNewWord forward sammeln.
        var foundNew: [FoundNewWord] = []
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let wordRange = Range(match.range(at: 1), in: text),
                  let transRange = Range(match.range(at: 2), in: text)
            else { continue }
            let word = String(text[wordRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let trans = String(text[transRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !word.isEmpty, !trans.isEmpty else { continue }
            foundNew.append(FoundNewWord(word: word, translation: trans))
        }

        // Marker reverse durch das Wort ersetzen.
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let wordRange = Range(match.range(at: 1), in: text),
                  let fullRange = Range(match.range, in: text)
            else { continue }
            let word = String(text[wordRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Defensive: leeres Wort → Marker einfach entfernen.
            text.replaceSubrange(fullRange, with: word)
        }
        return foundNew
    }

    // MARK: - FEHLER-Extraction

    /// Sammelt alle Korrektur-Marker im Text und entfernt sie. Identisch
    /// zur 2A-Logik, nur in eine separate Helper-Funktion ausgelagert.
    private static func extractAndStripErrors(in text: inout String) -> [FoundError] {
        guard let regex = errorRegex else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard !matches.isEmpty else { return [] }

        var errors: [FoundError] = []
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let userRange = Range(match.range(at: 1), in: text),
                  let tipRange = Range(match.range(at: 2), in: text)
            else { continue }
            let user = String(text[userRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tip = String(text[tipRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !user.isEmpty, !tip.isEmpty else { continue }
            errors.append(FoundError(userText: user, germanTip: tip))
        }

        for match in matches.reversed() {
            if let range = Range(match.range, in: text) {
                text.removeSubrange(range)
            }
        }
        return errors
    }
}
