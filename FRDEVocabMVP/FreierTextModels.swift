import Foundation
import UIKit

/// Identifiable-Wrapper um das zur Analyse anstehende `UIImage`. Wird
/// genutzt, damit `.fullScreenCover(item:)` eine stabile Identität pro
/// Präsentation erkennt — ohne den Wrapper würde ein plain `UIImage?`
/// zusammen mit dem `if let`-Pattern im Content-Closure zu Remounts
/// führen (View wird bei jedem Parent-Re-Render neu aufgebaut, `.task`
/// cancelled die laufende Claude-Request). Mit dem Wrapper hält SwiftUI
/// die Präsentation stabil, bis der Wrapper-Wert zu `nil` wird.
struct FreierTextPendingImage: Identifiable {
    let id = UUID()
    let image: UIImage
    /// Woher kommt das Bild — Kamera oder Galerie? Wird an die
    /// Processing-View durchgereicht, damit die Stage-Anzeige
    /// mode-spezifisch formuliert ist („KI analysiert dein Foto" vs.
    /// „…dein Bild"). `nil` fällt auf den neutralen Default-Text.
    var inputMethod: ScanInputMethod? = nil
}

/// MVP-Datenmodell für die „Freier Text"-Analyse via Claude Vision.
///
/// Bewusst eigenständig — **kein** Reuse des Vokabel-Scan-Schemas
/// (`OpenAIScanSchemaResponse` / `ScanAIResponsePayload`). Der Scan-Flow
/// liefert Paare „Quelle → Ziel" zum Importieren; hier geht es um eine
/// **lexikalische Analyse** eines Freitextes: Wortart-gruppierte Lemmata
/// mit Übersetzung, Genus (nur Nomen) und Fremdwort-Flag.
///
/// Die Trennung vermeidet Zwangsmappings und hält den neuen Feature-Flow
/// so schlank wie spezifiziert (MVP: nur anzeigen, kein Speichern, kein
/// Training, kein Detail-Screen).
struct FreeTextResult: Codable, Equatable {
    /// Erkannte Sprache als menschenlesbarer Name, z. B. „Französisch",
    /// „Englisch", „Deutsch". Claude liefert das Feld in der Modell-
    /// Response; wir zeigen es 1:1 im Header-Label der Result-View an.
    let language: String

    /// Der komplette vom Bild extrahierte Originaltext, so wie Claude
    /// ihn liest (inkl. Satzzeichen, in Lesereihenfolge). Die Result-
    /// View zeigt das als „Originaltext"-Block — hilfreich, damit der
    /// Nutzer vergleichen kann, was die KI gelesen hat.
    let originalText: String

    /// Deutsche Komplett-Übersetzung des `originalText`. Keine wort-
    /// wörtliche Übersetzung der Wortliste, sondern eine flüssige
    /// Fassung des ganzen Textes — Vorform späterer Vokabel-Sätze.
    let translation: String

    let nomen: [NounEntry]
    let verben: [VerbEntry]
    let adjektive: [GenericEntry]
    let adverbien: [GenericEntry]
    let pronomen: [GenericEntry]
    let praepositionen: [GenericEntry]
    let konjunktionen: [GenericEntry]
    let sonstige: [GenericEntry]

    /// `true` wenn mindestens eine Kategorie Einträge hat. Treiber für
    /// die Empty-State-Logik in `FreierTextResultView` (selten, aber
    /// z. B. bei reinem Bildmaterial ohne Text möglich).
    var hasAnyEntries: Bool {
        !nomen.isEmpty
            || !verben.isEmpty
            || !adjektive.isEmpty
            || !adverbien.isEmpty
            || !pronomen.isEmpty
            || !praepositionen.isEmpty
            || !konjunktionen.isEmpty
            || !sonstige.isEmpty
    }

    /// `true`, wenn entweder Originaltext oder Übersetzung nicht leer —
    /// auch wenn die Wortlisten leer sind, wollen wir den Text zeigen.
    /// Steuert Empty-State zusammen mit `hasAnyEntries`.
    var hasAnyTextBlock: Bool {
        !originalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Gesamtzahl aller erkannten Lemmata — für Wortzahl-Badge im Header.
    var totalEntryCount: Int {
        nomen.count + verben.count + adjektive.count + adverbien.count
            + pronomen.count + praepositionen.count + konjunktionen.count
            + sonstige.count
    }
}

/// Nomen-Eintrag mit optionalem Genus. `gender` ist optional, weil nicht
/// alle Sprachen ein Genus haben (z. B. Englisch) und Claude in dem Fall
/// `null` liefert.
struct NounEntry: Codable, Equatable, Identifiable {
    /// Stabile UUID für `ForEach` in der Result-View. Nicht aus JSON — die
    /// API liefert keine ID, wir generieren beim Decode lokal.
    var id: UUID = UUID()
    let word: String
    let translation: String
    /// „der" / „die" / „das" bzw. lokalsprachliche Entsprechung. Falls
    /// nicht anwendbar oder nicht bestimmbar: `nil`.
    let gender: String?
    /// `true`, wenn das Wort in der erkannten Sprache als Fremdwort gilt.
    /// JSON-Key: `is_foreign` (siehe `.convertFromSnakeCase` im Decoder).
    let isForeign: Bool

    private enum CodingKeys: String, CodingKey {
        case word, translation, gender, isForeign
    }

    // MARK: - Artikel + Nomen Display

    /// Bekannte Artikel-Prefixe. Claude liefert `word` oft schon MIT
    /// Artikel ("la maison", "der Hund"). Wenn der Artikel aber fehlt
    /// und `gender` gesetzt ist, fügen wir ihn für die Anzeige hinzu.
    private static let knownArticles: Set<String> = [
        "le", "la", "l'", "les", "un", "une", "des",       // Französisch
        "der", "die", "das", "ein", "eine",                  // Deutsch
        "the", "a", "an",                                    // Englisch
        "el", "los", "las", "una",                           // Spanisch
        "il", "lo", "i", "gli"                               // Italienisch
    ]

    /// `true`, wenn `word` bereits mit einem bekannten Artikel beginnt.
    /// Case-insensitive, damit "Le chat" genauso erkannt wird wie "le chat".
    var wordHasArticle: Bool {
        let lower = word.lowercased()
        // Sonderfall: l' (Elision) — Präfix-Match reicht
        if lower.hasPrefix("l'") || lower.hasPrefix("l\u{2019}") { return true }
        let firstToken = lower.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
        return Self.knownArticles.contains(firstToken)
    }

    /// Französische Vokale für Elision-Erkennung (le/la → l' vor Vokal).
    /// `h` NICHT enthalten — h aspiré ("le héros") vs. h muet ("l'hôtel")
    /// ist ohne Lexikon nicht sicher bestimmbar �� lieber kein l' bei h.
    private static let frenchVowels = CharacterSet(charactersIn: "aeiouyàâéèêëïîôùûüAEIOUYÀÂÉÈÊËÏÎÔÙÛÜ")

    /// Anzeige-Label für die Result-View:
    ///
    /// **Entscheidungslogik** (Reihenfolge wichtig):
    /// 1. Wenn `word` schon einen Artikel hat → unverändert zurückgeben.
    /// 2. Wenn `gender` gesetzt → Artikel automatisch generieren:
    ///    - `gender` ist bereits ein Artikel-String ("le", "la", "der"…)
    ///      → direkt verwenden.
    ///    - Französisch vor Vokal: le/la → l' (Elision).
    ///    - `gender` = "l'" → direkt anhängen (ohne Leerzeichen).
    /// 3. Kein `gender` → nur `word` (keine falschen Artikel).
    var displayLabel: String {
        if wordHasArticle { return word }

        guard let article = gender?.trimmingCharacters(in: .whitespacesAndNewlines),
              !article.isEmpty else { return word }

        // l' / l' — Elision schon im gender-Feld kodiert → direkt anhängen
        if article == "l'" || article == "l\u{2019}" {
            return "\(article)\(word)"
        }

        // Französische Elision: le/la → l' vor Vokal
        if article == "le" || article == "la" {
            if let first = word.unicodeScalars.first,
               Self.frenchVowels.contains(first) {
                return "l'\(word)"
            }
        }

        return "\(article) \(word)"
    }
}

/// Verb-Eintrag. Claude soll Infinitiv-Lemma liefern (Grundform). Kein
/// Feld für Konjugationsform — MVP-Fokus ist Anzeige, nicht Grammatik-
/// Analyse.
struct VerbEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    let word: String
    let translation: String
    let isForeign: Bool

    private enum CodingKeys: String, CodingKey {
        case word, translation, isForeign
    }
}

/// Generischer Eintrag für Adjektive, Adverbien, Pronomen,
/// Präpositionen, Konjunktionen und „Sonstige" (Interjektionen,
/// Partikeln, Zahlwörter …). Ein gemeinsamer Typ reicht — die
/// Wortklasse ergibt sich aus der Sektion im `FreeTextResult`.
struct GenericEntry: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    let word: String
    let translation: String
    let isForeign: Bool

    private enum CodingKeys: String, CodingKey {
        case word, translation, isForeign
    }
}

// MARK: - Abkürzungs-Expansion (Smart Expansion System)

extension FreeTextResult {

    /// Wendet die **deutsche Abkürzungs-Expansion** auf das gesamte
    /// Result an. Greift im FreeText-Flow, der **nicht** durch
    /// `ScanAIPostProcessor` geht (eigener Claude-Vision-Pfad).
    ///
    /// Expansion-Strategie:
    ///   • `translation` (Haupt-Übersetzungsblock) — immer deutsch,
    ///     Inline-Expansion (z. B. „Köln Hbf" → „Köln Hauptbahnhof
    ///     (Hbf)").
    ///   • `NounEntry.word` / `NounEntry.translation` — wenn der
    ///     Scan deutsch ist, steht die Abkürzung in `word`; sonst
    ///     in der `translation`. Beide Felder bekommen den Expander.
    ///   • `VerbEntry` / `GenericEntry` — analog, aber mit
    ///     `isNoun: false` (keine Artikel-Augmentation).
    ///
    /// Die Methode ist idempotent: wenn ein Feld bereits „Bahnhof
    /// (Hbf)" enthält (Klammer vorhanden), greift der Duplikat-Schutz
    /// im `GermanAbbreviationExpander`.
    func expandingAbbreviations() -> FreeTextResult {
        let isGermanSource = Self.isGermanLanguage(language)

        // Policy: FreeText-Flow nutzt `.exactAndInline` — auch
        // inline-Vorkommen in Phrasen wie „Köln Hbf" werden
        // umgeschrieben. Entspricht dem Scan-Pipeline-Verhalten bei
        // `ScanMode.text`.
        let policy: GermanAbbreviationExpander.Policy = .exactAndInline

        return FreeTextResult(
            language: language,
            originalText: originalText,  // Roh-Text bleibt unverändert — User sieht original
            translation: Self.expanded(translation, isNoun: false, policy: policy),
            nomen: nomen.map { entry in
                NounEntry(
                    id: entry.id,
                    word: Self.expanded(entry.word,
                                         isNoun: isGermanSource,  // Artikel nur wenn Source-Sprache Deutsch
                                         policy: policy),
                    translation: Self.expanded(entry.translation,
                                                 isNoun: true,   // Zielsprache ist Deutsch, Nomen → Artikel OK
                                                 policy: policy),
                    gender: entry.gender,
                    isForeign: entry.isForeign
                )
            },
            verben: verben.map { entry in
                VerbEntry(
                    id: entry.id,
                    word: Self.expanded(entry.word, isNoun: false, policy: policy),
                    translation: Self.expanded(entry.translation, isNoun: false, policy: policy),
                    isForeign: entry.isForeign
                )
            },
            adjektive: adjektive.map { Self.expandGeneric($0, isGermanSource: isGermanSource, policy: policy) },
            adverbien: adverbien.map { Self.expandGeneric($0, isGermanSource: isGermanSource, policy: policy) },
            pronomen: pronomen.map { Self.expandGeneric($0, isGermanSource: isGermanSource, policy: policy) },
            praepositionen: praepositionen.map { Self.expandGeneric($0, isGermanSource: isGermanSource, policy: policy) },
            konjunktionen: konjunktionen.map { Self.expandGeneric($0, isGermanSource: isGermanSource, policy: policy) },
            sonstige: sonstige.map { Self.expandGeneric($0, isGermanSource: isGermanSource, policy: policy) }
        )
    }

    /// Sprach-Check: ist das `language`-Feld ein Synonym für Deutsch?
    /// Claude liefert typisch „Deutsch", „German" — beide akzeptieren.
    private static func isGermanLanguage(_ label: String) -> Bool {
        let normalized = label.lowercased()
        return normalized.contains("deutsch") || normalized.contains("german")
    }

    /// Convenience-Wrapper für den Expander — verwirft nur das
    /// didChange-Flag.
    private static func expanded(
        _ text: String,
        isNoun: Bool,
        policy: GermanAbbreviationExpander.Policy
    ) -> String {
        GermanAbbreviationExpander.expand(text, isNoun: isNoun, policy: policy).normalized
    }

    /// Hilfs-Mapping für `GenericEntry` — dieselbe Logik wie NounEntry,
    /// nur ohne Gender/Artikel-Augmentation.
    private static func expandGeneric(
        _ entry: GenericEntry,
        isGermanSource: Bool,
        policy: GermanAbbreviationExpander.Policy
    ) -> GenericEntry {
        GenericEntry(
            id: entry.id,
            word: expanded(entry.word, isNoun: false, policy: policy),
            translation: expanded(entry.translation, isNoun: false, policy: policy),
            isForeign: entry.isForeign
        )
    }
}

// MARK: - Qualitätsfilter

extension FreeTextResult {

    /// Liefert eine bereinigte Kopie: OCR-Fragmente, Zahlen, URLs,
    /// Sonderzeichen-Only-Strings und zu kurze Wörter werden entfernt.
    /// Wird einmal beim Empfang des Claude-Ergebnisses angewandt — alle
    /// nachgelagerten Views und das Speichern arbeiten auf dem gefilterten
    /// Result.
    func filtered() -> FreeTextResult {
        FreeTextResult(
            language: language,
            originalText: originalText,
            translation: translation,
            nomen: nomen.filter { Self.isValidWord($0.word) },
            verben: verben.filter { Self.isValidWord($0.word) },
            adjektive: adjektive.filter { Self.isValidWord($0.word) },
            adverbien: adverbien.filter { Self.isValidWord($0.word) },
            pronomen: pronomen.filter { Self.isValidWord($0.word) },
            praepositionen: praepositionen.filter { Self.isValidWord($0.word) },
            konjunktionen: konjunktionen.filter { Self.isValidWord($0.word) },
            sonstige: sonstige.filter { Self.isValidWord($0.word) }
        )
    }

    /// Prüft, ob ein Wort die Mindestqualität für die Anzeige hat.
    /// Bewusst konservativ — lieber ein fragwürdiges Wort anzeigen
    /// als ein echtes rausfiltern.
    private static func isValidWord(_ raw: String) -> Bool {
        let word = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        // Zu kurz (einzelne Buchstaben, Fragmente)
        // Ausnahme: einige valide Kurzwörter wie "à", "y", "je"
        let stripped = word.filter { $0.isLetter }
        if stripped.count < 2 { return false }

        // Reine Zahlen (evtl. mit Trennzeichen)
        if word.allSatisfy({ $0.isNumber || $0 == "." || $0 == "," || $0 == " " }) {
            return false
        }

        // URLs
        if word.contains("://") || word.lowercased().hasPrefix("www.") {
            return false
        }

        // Reine Sonderzeichen / Interpunktion
        if word.allSatisfy({ !$0.isLetter && !$0.isNumber }) {
            return false
        }

        // Bekannte OCR-Fragmente und Artefakte
        let ocrFragments: Set<String> = [
            "l'", "l\u{2019}", "-", "/", "—", "–", "…", ".", ",",
            "'", "'", "\"", ":", ";", "!", "?", "(", ")", "[", "]"
        ]
        if ocrFragments.contains(word) { return false }

        return true
    }
}

/// Fehler-Enum für den „Freier Text"-Flow. Die Messages werden
/// **nicht direkt** in die UI geschrieben — die View zeigt die
/// user-facing Texte aus der Spezifikation („Analyse fehlgeschlagen.
/// Bitte erneut versuchen.", „Ergebnis konnte nicht vollständig
/// verarbeitet werden."), während die `errorDescription` für Debug-
/// Logs gedacht ist.
enum FreierTextError: Error, LocalizedError {
    case missingAPIKey
    case invalidImage
    case networkFailure(underlying: Error)
    case httpFailure(statusCode: Int, body: String)
    case invalidResponse
    case decodeFailure(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Scan-Dienst nicht verfügbar."
        case .invalidImage:
            return "Bild konnte nicht verarbeitet werden."
        case .networkFailure(let error):
            return "Netzwerkfehler: \(error.localizedDescription)"
        case .httpFailure(let code, let body):
            return "HTTP \(code): \(body.prefix(200))"
        case .invalidResponse:
            return "Antwort ohne verwertbaren Inhalt."
        case .decodeFailure(let error):
            return "JSON-Decode fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
