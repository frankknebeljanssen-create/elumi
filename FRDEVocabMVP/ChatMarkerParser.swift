// ChatMarkerParser.swift
// **Léa-Chat MVP Schritt 2A (2026-05-10)** — Parser für die Korrektur-
// Marker, die Léa per System-Prompt am Ende ihrer Nachrichten anhängt.
//
// **Marker-Format** (single-line, am Ende der Nachricht):
//   `(💡 [FEHLER: <user-text>] → Kleiner Tipp: <deutsche-erklärung>)`
//
// Der Parser extrahiert Léas „cleanText" (ohne die Marker-Klammer)
// + alle gefundenen `FoundError`-Tupel. Robust gegen malformed Marker:
// bei Parser-Failure wird der gesamte Raw-Text als cleanText
// durchgereicht, `foundErrors` bleibt leer.
//
// Spec sieht max 1 Korrektur pro Nachricht vor (per Prompt-Regel),
// der Parser akzeptiert aber N Marker — falls Léa sich nicht an
// die Spec hält, sammeln wir alle gefundenen Errors.

import Foundation

/// Ein einzelner Korrektur-Treffer aus Léas Antwort.
struct FoundError: Equatable {
    /// Der Text, den der User falsch geschrieben hat — exakt wie aus
    /// dem `[FEHLER: …]`-Marker extrahiert. Wird im iOS-Client gegen
    /// die User-Message-Text gematcht (Substring-Range), um die
    /// Underline-Span zu setzen.
    let userText: String

    /// Léas deutsche Erklärung mit korrekter Form (Tipp-Text aus
    /// `Kleiner Tipp: …`). Wird in der `CorrectionCardView` gerendert.
    let germanTip: String
}

/// Ergebnis des Parsings: Léas Text ohne Marker + Liste aller
/// gefundenen Fehler.
struct ParsedMessage: Equatable {
    let cleanText: String
    let foundErrors: [FoundError]
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
    ///   • `([^)]+)` — Group 2 = deutsche Erklärung (alles bis
    ///     schließendes Pattern-Klammer)
    ///   • `\)` — schließende Klammer
    ///
    /// `dotMatchesLineSeparators` ist NICHT gesetzt — Marker sind
    /// per Spec single-line.
    private static let pattern = #"\(💡\s*\[FEHLER:\s*([^\]]+)\]\s*→\s*Kleiner\s+Tipp:\s*([^)]+)\)"#

    private static let regex: NSRegularExpression? = {
        try? NSRegularExpression(pattern: pattern, options: [])
    }()

    /// Parst Léas Raw-Antwort und extrahiert alle Korrektur-Marker.
    /// Bei Parser-Failure (kein Match, malformed Marker, Regex-
    /// Compile-Failure) wird der Raw-Text 1:1 als `cleanText`
    /// durchgereicht und `foundErrors` bleibt leer — kein Crash,
    /// kein User-sichtbarer Fehler, einfach Plain-Chat.
    static func parseLeaMessage(_ rawText: String) -> ParsedMessage {
        guard let regex else {
            return ParsedMessage(cleanText: rawText, foundErrors: [])
        }

        let nsRange = NSRange(rawText.startIndex..<rawText.endIndex, in: rawText)
        let matches = regex.matches(in: rawText, options: [], range: nsRange)

        guard !matches.isEmpty else {
            return ParsedMessage(cleanText: rawText, foundErrors: [])
        }

        var errors: [FoundError] = []
        for match in matches {
            guard match.numberOfRanges >= 3,
                  let userRange = Range(match.range(at: 1), in: rawText),
                  let tipRange = Range(match.range(at: 2), in: rawText) else {
                continue
            }
            let user = String(rawText[userRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let tip = String(rawText[tipRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !user.isEmpty, !tip.isEmpty else { continue }
            errors.append(FoundError(userText: user, germanTip: tip))
        }

        // CleanText: Marker(-Region) entfernen + Trailing-Whitespace
        // wegtrimmen. Wir entfernen rückwärts (von hinten nach vorne),
        // damit die NSRange-Indizes nicht verschoben werden.
        var clean = rawText
        for match in matches.reversed() {
            guard let r = Range(match.range, in: clean) else { continue }
            clean.removeSubrange(r)
        }
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)

        return ParsedMessage(cleanText: clean, foundErrors: errors)
    }
}
