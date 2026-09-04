import Foundation

/// **Abkürzungs-Normalisierung Deutsch** — erweitert bekannte Kurz-
/// formen wie „Hbf" zu verständlichen Vollformen mit Original-
/// Abkürzung in Klammern: „Bahnhof (Hbf)".
///
/// Ziel: Didaktik. Wenn der Scanner ein Stundenplan-, Fahrplan-,
/// Speisekarten- oder sonstiges Foto verarbeitet, sollen erkannte
/// Abkürzungen **nicht** 1:1 als Vokabel gelernt werden — sonst lernt
/// der User „Hbf" statt „Bahnhof". Gleichzeitig wollen wir die
/// Abkürzung nicht verschweigen (sie kommt im Alltag vor), also
/// zeigen wir beide: Vollform als primäre Lernform, Abkürzung in
/// Klammern als Kontext.
///
/// **Produktverhalten pro Modus**:
///   • `.freeText` → **immer** erweitern (Kontext-freie Szenen-Scans
///     profitieren am meisten: Bahnhofsschild, Straßenschild,
///     Adresszeile).
///   • `.vocabularyList` → **nur exakte Matches** erweitern. Wenn der
///     Lehrer eine Vokabelliste mit „Hbf" als Zielvokabel einscannt,
///     darf das nicht stillschweigend auf „Bahnhof" umgebogen werden;
///     aber Feld-Inhalte wie „Köln Hbf" im deutschen Teil werden
///     inline zu „Köln Hauptbahnhof (Hbf)" normalisiert.
///
/// Das Mapping ist **bewusst konservativ**: nur Abkürzungen, deren
/// Vollform eindeutig ist (keine Raten-Gefahr) und die im Alltag
/// regelmäßig als Abkürzung vorkommen. Single-Letter-Abkürzungen
/// (z. B. „M." für Männer) bleiben außen vor — zu ambig.
enum GermanAbbreviationExpander {

    // MARK: - Mapping

    /// Eintrag pro Abkürzung: Vollform + optionaler Artikel-Hint.
    /// `gender == nil` für Adverbien/Partikel/Abkürzungen ohne
    /// Genus (z. B. „z. B.", „usw.").
    struct Entry {
        let fullForm: String
        /// Genus für Nomen-Abkürzungen — wird vom Expander genutzt,
        /// um bei Bedarf einen Artikel vor die Vollform zu setzen
        /// („der Bahnhof (Hbf)"). Nil → kein Artikel-Augment.
        let gender: Gender?

        enum Gender {
            case masculine  // „der"
            case feminine   // „die"
            case neuter     // „das"

            var definiteArticle: String {
                switch self {
                case .masculine: return "der"
                case .feminine:  return "die"
                case .neuter:    return "das"
                }
            }
        }
    }

    /// **Abkürzungs-Map** — Erstausstattung. Leicht erweiterbar: neue
    /// Einträge einfach hier ergänzen, keine Code-Änderung an den
    /// Call-Sites nötig.
    ///
    /// Konvention für Keys: **mit originaler Interpunktion** wie im
    /// Realtext („Dr." mit Punkt, „Nr." mit Punkt). Match ist
    /// case-sensitive für das Schlüsselwort selbst („Hbf" matcht
    /// nicht „hbf" — „hbf" käme nur als OCR-Fehler vor und soll
    /// nicht versehentlich ausgerollt werden).
    static let germanAbbreviations: [String: Entry] = [
        // Verkehr / Orte
        "Hbf":  Entry(fullForm: "Hauptbahnhof", gender: .masculine),
        "Bhf":  Entry(fullForm: "Bahnhof",      gender: .masculine),
        "Str.": Entry(fullForm: "Straße",       gender: .feminine),
        "Nr.":  Entry(fullForm: "Nummer",       gender: .feminine),
        "Pl.":  Entry(fullForm: "Platz",        gender: .masculine),
        "Whg.": Entry(fullForm: "Wohnung",      gender: .feminine),

        // Titel / Personen
        "Dr.":   Entry(fullForm: "Doktor",    gender: .masculine),
        "Prof.": Entry(fullForm: "Professor", gender: .masculine),

        // Unternehmen / Organisation
        "AG":   Entry(fullForm: "Aktiengesellschaft", gender: .feminine),
        "GmbH": Entry(fullForm: "Gesellschaft mit beschränkter Haftung", gender: .feminine),
        "eV":   Entry(fullForm: "eingetragener Verein", gender: .masculine),
        "e.V.": Entry(fullForm: "eingetragener Verein", gender: .masculine),

        // Adverbien / Füllwörter (kein Artikel)
        "usw.": Entry(fullForm: "und so weiter",   gender: nil),
        "z.B.": Entry(fullForm: "zum Beispiel",    gender: nil),
        "z. B.": Entry(fullForm: "zum Beispiel",   gender: nil),
        "bzw.": Entry(fullForm: "beziehungsweise", gender: nil),
        "ca.":  Entry(fullForm: "circa",           gender: nil),
        "mind.": Entry(fullForm: "mindestens",     gender: nil),
        "max.": Entry(fullForm: "maximal",         gender: nil),
        "d.h.": Entry(fullForm: "das heißt",       gender: nil),
        "d. h.": Entry(fullForm: "das heißt",      gender: nil),
        "u.a.": Entry(fullForm: "unter anderem",   gender: nil),
        "u. a.": Entry(fullForm: "unter anderem",  gender: nil),
        "etc.": Entry(fullForm: "et cetera",       gender: nil)
    ]

    // MARK: - Expansion-API

    /// Policy für die Erweiterung — steuert Tiefe der Änderung.
    enum Policy {
        /// Nur erweitern, wenn der gesamte Text EXAKT die Abkürzung ist.
        /// Für VocabularyList-Modus: der Lehrer kann „Hbf" bewusst als
        /// eigenständige Vokabel gewählt haben; wir ersetzen nicht
        /// stillschweigend. Aber bei mehrteiligen Strings („Köln Hbf")
        /// wird auch nichts umgebogen — „zu vorsichtig ist besser
        /// als falsch".
        case exactOnly

        /// Erweitern bei exakten Matches **und** bei inline-Vorkommen
        /// in mehrteiligen Strings. „Köln Hbf" → „Köln Hauptbahnhof (Hbf)".
        /// Für FreeText-Modus — dort ist das genau das, was der User
        /// lernen will: greifbare Alltags-Sprache.
        case exactAndInline
    }

    /// Erweitert die gegebene Zeichenkette um Abkürzungs-Vollformen
    /// gemäß Policy. Liefert die **gleiche** Zeichenkette zurück, wenn
    /// keine Abkürzung matcht — idempotent, sicher für mehrfache
    /// Anwendung (z. B. in Test-Setups).
    ///
    /// - Parameters:
    ///   - text: Roh-Text aus dem Scan (z. B. `entry.target`).
    ///   - isNoun: Hinweis vom Aufrufer, ob der Eintrag als Nomen
    ///     klassifiziert ist. Wird genutzt, um bei **exaktem Match**
    ///     einen Artikel voranzustellen („der Bahnhof (Hbf)"). Bei
    ///     Inline-Matches wird kein Artikel eingefügt (würde die Satz-
    ///     Grammatik zerschießen).
    ///   - policy: siehe `Policy`.
    /// - Returns: normalisierter Text + Flag, ob etwas geändert wurde.
    static func expand(
        _ text: String,
        isNoun: Bool,
        policy: Policy
    ) -> (normalized: String, didChange: Bool) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (text, false) }

        // **Duplikat-Schutz** (User-Spec): wenn der Text bereits
        // Klammern enthält, ist vermutlich schon eine Erweiterung
        // passiert oder es handelt sich um einen bewussten Hinweis
        // vom User/LLM. Dann NICHT nochmals anfassen — sonst
        // entsteht „Bahnhof (Hbf) (Hbf)" oder ähnliches Müll.
        if text.contains("(") {
            return (text, false)
        }

        // 1. Exakt-Match-Fall: der gesamte Target-Text ist eine
        //    einzige bekannte Abkürzung. Erweitern + optional
        //    Artikel voranstellen.
        if let entry = germanAbbreviations[trimmed] {
            let replacement = buildExactReplacement(
                entry: entry,
                abbreviation: trimmed,
                isNoun: isNoun
            )
            #if DEBUG
            appDebugLog("🔤 [AbbrevExpand] exact: \"\(trimmed)\" → \"\(replacement)\"")
            #endif
            return (replacement, true)
        }

        // 2. Inline-Match — nur wenn Policy es erlaubt.
        guard policy == .exactAndInline else {
            return (text, false)
        }

        // Wir iterieren über alle Abkürzungen und ersetzen
        // Wortgrenzen-genaue Vorkommen. Längere Keys zuerst, damit
        // „z. B." nicht von „z." gefressen wird.
        let sortedKeys = germanAbbreviations.keys.sorted { $0.count > $1.count }
        var working = text
        var changed = false
        for abbr in sortedKeys {
            guard let entry = germanAbbreviations[abbr] else { continue }
            let replacement = "\(entry.fullForm) (\(abbr))"
            let replacedWorking = replaceWordBoundary(
                in: working,
                needle: abbr,
                replacement: replacement
            )
            if replacedWorking != working {
                #if DEBUG
                appDebugLog("🔤 [AbbrevExpand] inline: \"\(abbr)\" → \"\(entry.fullForm) (\(abbr))\" in \"\(text)\"")
                #endif
                working = replacedWorking
                changed = true
            }
        }
        return (working, changed)
    }

    // MARK: - Internal

    private static func buildExactReplacement(
        entry: Entry,
        abbreviation: String,
        isNoun: Bool
    ) -> String {
        if isNoun, let article = entry.gender?.definiteArticle {
            return "\(article) \(entry.fullForm) (\(abbreviation))"
        }
        return "\(entry.fullForm) (\(abbreviation))"
    }

    /// Ersetzt alle Vorkommen von `needle` in `haystack` durch
    /// `replacement` — aber nur an **Wortgrenzen**. Verhindert,
    /// dass „Str." mitten in „Struktur" gematched wird.
    ///
    /// Implementation: Regex mit `\b` Word-Boundary. Der `needle`
    /// wird escaped, damit Sonderzeichen (Punkte, Klammern) als
    /// Literal behandelt werden.
    private static func replaceWordBoundary(
        in haystack: String,
        needle: String,
        replacement: String
    ) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: needle)
        // Word-Boundary vorne reicht; hintere Grenze ist bei Punkten
        // schon impliziert. Für punktlose Keys („Hbf") brauchen wir
        // auch hinten eine Wortgrenze.
        let endsWithPunct = needle.hasSuffix(".")
        let pattern = endsWithPunct ? "\\b\(escaped)" : "\\b\(escaped)\\b"
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(haystack.startIndex..., in: haystack)
            return regex.stringByReplacingMatches(
                in: haystack,
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: replacement)
            )
        } catch {
            return haystack
        }
    }
}
