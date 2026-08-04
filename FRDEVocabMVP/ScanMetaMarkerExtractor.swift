import Foundation

/// **Meta-Marker-Extraktor** für Scan-Ergebnisse (Bug-Fix 2026-04-24).
///
/// Trennt grammatikalische Annotations-Marker wie `(m)`, `(f)`,
/// `(pl.)`, `(inv.)`, `adj.`, `fam.`, etc. vom eigentlichen
/// Vokabel-Text. Diese Marker landeten vorher SICHTBAR im
/// `source`-/`target`-String, statt als strukturierte Metadaten neben
/// der Vokabel zu leben.
///
/// Beispiel:
///   Input  : `le voyage (m)`
///   Output : `(cleaned: "le voyage", marker: "m")`
///
///   Input  : `la maison (f)`
///   Output : `(cleaned: "la maison", marker: "f")`
///
///   Input  : `chaussures (pl.)`
///   Output : `(cleaned: "chaussures", marker: "pl")`
///
///   Input  : `bonbon`
///   Output : `(cleaned: "bonbon", marker: nil)`
///
/// Erkennung sehr konservativ — wir extrahieren nur **explizit
/// gekapselte** Marker in runden Klammern am Anfang oder Ende des
/// Strings. Markers in der Mitte (z. B. „prendre (qch) à qn") bleiben
/// erhalten, weil dort die Klammern semantisch was anderes bedeuten.
enum ScanMetaMarkerExtractor {

    /// Liste anerkannter Meta-Tokens (lowercased, ohne Klammern).
    /// Erweiterbar — bei Erweiterung bitte nur Tokens aufnehmen, die
    /// **eindeutig** als Annotations-Marker gelten und nicht als
    /// gewöhnliches Wort vorkommen können.
    private static let knownMarkers: Set<String> = [
        // Genus
        "m", "f", "n",
        "m/f", "m./f.",
        // Numerus
        "pl", "pl.",
        "sg", "sg.",
        "inv", "inv.",
        // Wortklasse
        "adj", "adj.",
        "adv", "adv.",
        "prep", "prep.",
        "conj", "conj.",
        "interj", "interj.",
        // Register / Stil
        "fam", "fam.",
        "vulg", "vulg.",
        "fig", "fig.",
        "fml", "fml.",
        "litt", "litt."
    ]

    struct ExtractionResult: Equatable {
        let cleanedText: String
        /// Normalisierter Marker (lowercased, ohne Punkt) — z. B. `"m"`,
        /// `"f"`, `"pl"`. `nil`, wenn kein Marker gefunden wurde.
        let normalizedMarker: String?
    }

    /// Extrahiert Marker aus einem Text. Gibt das Ergebnis-Pair
    /// zurück. Bei mehreren möglichen Markern (sollte in der Praxis
    /// nicht vorkommen) gewinnt der erste gefundene.
    static func extract(from text: String) -> ExtractionResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ExtractionResult(cleanedText: trimmed, normalizedMarker: nil)
        }

        // 1. Trailing-Match: „le voyage (m)" → core „le voyage" + marker „m"
        if let match = trailingParentheticalMatch(in: trimmed) {
            return match
        }

        // 2. Leading-Match: „(m) le voyage" → core „le voyage" + marker „m"
        // Selten, aber kommt bei manchen Lehrwerken vor.
        if let match = leadingParentheticalMatch(in: trimmed) {
            return match
        }

        // 3. Bare-Trailing-Match: „ici adv" → core „ici" + marker „adv".
        //
        // **2026-06-09** — Viele Lehrwerke drucken die Wortart OHNE
        // Klammern direkt hinter die Vokabel. Ohne diesen Fall landete
        // das Kürzel als Teil des Wortes in der Lernliste („ici adv",
        // „depuis adv") — der Schüler hätte es mitgelernt.
        if let match = bareTrailingMarkerMatch(in: trimmed) {
            return match
        }

        // 3. Kein Match → Original durchreichen.
        return ExtractionResult(cleanedText: trimmed, normalizedMarker: nil)
    }

    // MARK: - Internal helpers

    /// Kürzel, die auch OHNE Klammern sicher als Marker gelten dürfen.
    ///
    /// Bewusst eine engere Liste als `knownMarkers`: Einbuchstabige
    /// Marker („m", „f", „n") bleiben draußen, weil ein alleinstehendes
    /// „m" hinter einer Vokabel zu leicht etwas anderes sein kann. Die
    /// hier gelisteten Kürzel sind im Französischen keine eigenen
    /// Wörter, ein Fehlgriff ist damit praktisch ausgeschlossen.
    private static let bareTrailingMarkers: Set<String> = [
        "adj", "adj.",
        "adv", "adv.",
        "prep", "prep.",
        "conj", "conj.",
        "interj", "interj.",
        "pl", "pl.",
        "sg", "sg.",
        "inv", "inv.",
        "fam", "fam.",
        "fig", "fig."
    ]

    private static func bareTrailingMarkerMatch(in text: String) -> ExtractionResult? {
        let parts = text.split(separator: " ").map(String.init)
        // Mindestens ein Wort muss übrig bleiben — „adv" allein ist
        // keine Vokabel mit Marker, sondern nur ein Kürzel.
        guard parts.count >= 2, let last = parts.last else { return nil }

        let candidate = last.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard bareTrailingMarkers.contains(candidate) else { return nil }

        let core = parts.dropLast().joined(separator: " ")
        guard !core.isEmpty else { return nil }

        return ExtractionResult(
            cleanedText: core,
            normalizedMarker: normalize(marker: candidate)
        )
    }

    private static func trailingParentheticalMatch(in text: String) -> ExtractionResult? {
        guard text.hasSuffix(")"), let openIdx = text.lastIndex(of: "(") else {
            return nil
        }
        let inside = text[text.index(after: openIdx)..<text.index(before: text.endIndex)]
        let candidate = inside.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard knownMarkers.contains(candidate) else { return nil }

        // Alles vor der Klammer (mit trailing-Whitespace abschneiden).
        let coreEnd = text.index(before: openIdx)
        guard coreEnd > text.startIndex else { return nil }
        let core = String(text[..<openIdx]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return nil }

        return ExtractionResult(
            cleanedText: core,
            normalizedMarker: normalize(marker: candidate)
        )
    }

    private static func leadingParentheticalMatch(in text: String) -> ExtractionResult? {
        guard text.hasPrefix("(") else { return nil }
        guard let closeIdx = text.firstIndex(of: ")") else { return nil }
        let inside = text[text.index(after: text.startIndex)..<closeIdx]
        let candidate = inside.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard knownMarkers.contains(candidate) else { return nil }

        let coreStart = text.index(after: closeIdx)
        let core = String(text[coreStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !core.isEmpty else { return nil }

        return ExtractionResult(
            cleanedText: core,
            normalizedMarker: normalize(marker: candidate)
        )
    }

    /// Normalisiert Marker auf eine kanonische Form (ohne Punkt,
    /// lowercased), damit Caller einen stabilen Schlüssel haben.
    private static func normalize(marker raw: String) -> String {
        let withoutDot = raw.replacingOccurrences(of: ".", with: "")
        return withoutDot.lowercased()
    }
}
