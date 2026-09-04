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
    ///   • `(.+?)` — Group 2 = deutsche Erklärung, **LAZY** mit
    ///     dotMatchesLineSeparators
    ///   • `\)` — schließende Klammer (kein End-Anchor mehr)
    ///
    /// **Bug-K-Fix (2026-05-10)** — vorher: Greedy `(.+)` + End-Anchor
    /// `\)\s*$` backtracked bis zur LETZTEN `)` am Message-Ende. Bei
    /// (spec-widrigen) Multi-FEHLER-Markern wurden ALLE Marker zu einem
    /// einzigen gemergt — User-Bubble-Card zeigte dann den ersten Marker-
    /// Tipp + rohe Marker-Strings der späteren. Sonnet 4.6 hält die
    /// „max 1"-Regel nicht zuverlässig ein (Frank's Smoke), daher
    /// brauchten wir defense-in-depth: Prompt enforced (ABSOLUTE REGEL)
    /// + Parser lazy.
    ///
    /// **Trade-off Inner-Klammern**: das vorherige Greedy+End-Anchor war
    /// stabil bei `Es heißt 'allé(e)' (Partizip)...` — Inner-Klammern im
    /// Tipp wurden mit-konsumiert. Mit Lazy + erster-`)`-Match bricht der
    /// Match jetzt potentiell zu früh ab, wenn der Tipp eine Inner-Klammer
    /// enthält. Frank's RISK-FLAG: Smoke zeigt, follow-up wenn nötig.
    private static let errorPattern = #"\(💡\s*\[FEHLER:\s*([^\]]+)\]\s*→\s*Kleiner\s+Tipp:\s*(.+?)\)"#

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
        // Lazy `.+?` auch über Newlines hinweggreift; manche
        // Léa-Antworten haben einen Zeilenumbruch zwischen dem
        // Konversationstext und dem Marker. Mit Lazy bleibt das
        // unproblematisch — der Match endet sauber am ersten `)`.
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

    /// Sammelt alle `[VOCAB: wort]`-Marker im Text, **ersetzt** sie
    /// durch das reine Wort (analog zu NEW-Markern) und gibt die
    /// Wörter in Vorkommens-Reihenfolge zurück.
    ///
    /// **Bug-L-Fix (2026-05-10)** — vorher hat `removeSubrange` das
    /// komplette Marker-Block inkl. Wort entfernt. Wenn Sonnet einen
    /// VOCAB-Marker INLINE in der Antwort positioniert
    /// (`Tu [VOCAB: fais] quoi à l'école?`) wurde der Satz broken
    /// (`Tu  quoi à l'école?`). Spec-Annahme war End-of-Message-
    /// Marker, Sonnet's Realität ist inline — replace-with-word ist
    /// robust gegen beide Pattern. User-Bubble-Highlight läuft eh
    /// über `vocabUsed[]`-Array, ist von der Strip-Logik unabhängig.
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

        // Marker reverse durch das reine Wort ersetzen (statt strippen).
        // Reverse-Iteration hält NSRange-Indizes stabil für vorherige
        // Matches.
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: text),
                  match.numberOfRanges >= 2,
                  let wordRange = Range(match.range(at: 1), in: text)
            else { continue }
            let word = String(text[wordRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            // Defensive: leeres Wort → einfach den Marker entfernen
            // (sonst bleibt ein leerer String, der nichts kaputt macht
            // aber visuell auch nichts hilft).
            text.replaceSubrange(fullRange, with: word)
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

    /// Sammelt Korrektur-Marker. **Bug-K-Fix (2026-05-10)**: Mit dem
    /// Lazy-Pattern können theoretisch mehrere Matches kommen (wenn
    /// Sonnet die ABSOLUTE-REGEL des System-Prompts verletzt). Wir
    /// nehmen nur den **ersten** Match — Sonnet's „wichtigster Fehler"
    /// heuristisch — als die eine CorrectionCard.
    ///
    /// **Defense (2026-05-20)**: Vorher wurde NUR der erste Marker
    /// gestrippt; weitere Marker blieben roh im cleanText sichtbar (als
    /// Smoke-Signal). Das konnte als „doppelte Korrektur" in der Bubble
    /// erscheinen. Jetzt strippen wir ALLE Marker aus dem Text (reverse-
    /// iteriert für Index-Stabilität), geben aber weiterhin nur den ersten
    /// als FoundError zurück. Bei >1 Match: WARN-Log als Spec-Violation-
    /// Signal. Für aktuelle Outputs (immer 1 Marker) ändert sich nichts.
    private static func extractAndStripErrors(in text: inout String) -> [FoundError] {
        guard let regex = errorRegex else { return [] }
        let nsRange = NSRange(text.startIndex..<text.endIndex, in: text)
        let matches = regex.matches(in: text, options: [], range: nsRange)
        guard let firstMatch = matches.first else { return [] }

        if matches.count > 1 {
            print("⚠️ [LeaSpec] Sonnet violated ABSOLUTE RULE: \(matches.count) FEHLER markers in single response")
        }

        guard firstMatch.numberOfRanges >= 3,
              let userRange = Range(firstMatch.range(at: 1), in: text),
              let tipRange = Range(firstMatch.range(at: 2), in: text)
        else { return [] }
        let user = String(text[userRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let tip = String(text[tipRange])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty, !tip.isEmpty else { return [] }
        let error = FoundError(userText: user, germanTip: tip)

        // ALLE Marker reverse strippen → Index-Stabilität für die je
        // vorherigen Matches. Nur `firstMatch` wird als FoundError
        // zurückgegeben; die übrigen verschwinden lediglich aus dem Text.
        for match in matches.reversed() {
            if let range = Range(match.range, in: text) {
                text.removeSubrange(range)
            }
        }
        return [error]
    }
}
