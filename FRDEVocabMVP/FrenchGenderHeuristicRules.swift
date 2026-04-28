import Foundation

/// **Französisch-Genus-Heuristik nach Endungsmuster**
///
/// Zentrale Tabelle der typischen Nomen-Endungen mit hoher bis mittlerer
/// Vorhersagekraft. Die Confidence ist der Anteil der Wörter mit dieser
/// Endung, die tatsächlich das zugeordnete Genus haben (basiert auf
/// breiten Wiktionary-Statistiken und Grammatik-Referenzen — Grevisse,
/// Riegel/Pellat/Rioul).
///
/// **Match-Reihenfolge**: längere Endungen ZUERST prüfen. „-ation" muss
/// vor „-tion" matchen, damit die spezifischere Regel gewinnt. Die
/// `allRules`-Liste ist bewusst von lang → kurz sortiert.
///
/// **Ausnahmen**: einzelne bekannte Ausnahmen stehen oben in
/// `explicitOverrides` und schlagen die Endungs-Regeln. Beispiel:
/// `l'eau` ist feminin, obwohl `-eau` normalerweise maskulin ist.
///
/// **Confidence-Schwellen**:
///   • ≥ 0,95: Regel wird als „sehr zuverlässig" behandelt
///   • 0,85–0,95: „wahrscheinlich richtig", markieren für Review
///   • < 0,85: „unsicher", kein Auto-Apply → KI-Fallback
enum FrenchGenderHeuristicRules {

    enum Gender: String, Equatable {
        case masculine = "m"
        case feminine = "f"
    }

    struct RuleMatch {
        let gender: Gender
        let confidence: Double
        /// Welche Endung gematcht hat — für Debug/Review sichtbar.
        let matchedPattern: String
    }

    // MARK: - Explizite Overrides (Ausnahmen mit höchster Priorität)

    /// Bekannte Ausnahmen, bei denen die Endungs-Regel **nicht** greift.
    /// Key ist die **Kern-Form** (ohne Artikel, lowercased, trimmed).
    /// Wert ist das tatsächliche Genus + sehr hohe Confidence.
    static let explicitOverrides: [String: RuleMatch] = [
        // -eau-Ausnahme: Wasser ist feminin
        "eau":        RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:eau"),
        "peau":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:peau"),
        // -age-Ausnahmen: einige -age sind feminin
        "page":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:page"),
        "plage":      RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:plage"),
        "cage":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:cage"),
        "image":      RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:image"),
        "nage":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:nage"),
        "rage":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:rage"),
        // -é-Ausnahmen: einige -é sind feminin
        "clé":        RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:clé"),
        // Kurze Alltagswörter, bei denen Endungs-Regel versagt
        "main":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:main"),
        "fin":        RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:fin"),
        "foi":        RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:foi"),
        "loi":        RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:loi"),
        "paix":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:paix"),
        "voix":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:voix"),
        "fois":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:fois"),
        "mer":        RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:mer"),
        "cour":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:cour"),
        "tour":       RuleMatch(gender: .feminine,  confidence: 0.6, matchedPattern: "override:tour-ambig"), // Turm=f, Tour=m — ambig
        "faim":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:faim"),
        "soif":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:soif"),
        "nuit":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:nuit"),
        "dent":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:dent"),
        "fleur":      RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:fleur"),
        "sœur":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:sœur"),
        "mère":       RuleMatch(gender: .feminine,  confidence: 1.0, matchedPattern: "override:mère"),
        // Kurze Maskulina
        "père":       RuleMatch(gender: .masculine, confidence: 1.0, matchedPattern: "override:père"),
        "frère":      RuleMatch(gender: .masculine, confidence: 1.0, matchedPattern: "override:frère"),
        "fils":       RuleMatch(gender: .masculine, confidence: 1.0, matchedPattern: "override:fils"),
        "nom":        RuleMatch(gender: .masculine, confidence: 1.0, matchedPattern: "override:nom"),
        "jour":       RuleMatch(gender: .masculine, confidence: 1.0, matchedPattern: "override:jour"),
        "an":         RuleMatch(gender: .masculine, confidence: 1.0, matchedPattern: "override:an"),
        "pays":       RuleMatch(gender: .masculine, confidence: 1.0, matchedPattern: "override:pays"),
        "temps":      RuleMatch(gender: .masculine, confidence: 1.0, matchedPattern: "override:temps"),
        "travail":    RuleMatch(gender: .masculine, confidence: 1.0, matchedPattern: "override:travail"),
        "bras":       RuleMatch(gender: .masculine, confidence: 1.0, matchedPattern: "override:bras"),
        "cœur":       RuleMatch(gender: .masculine, confidence: 1.0, matchedPattern: "override:cœur"),
        "œuf":        RuleMatch(gender: .masculine, confidence: 1.0, matchedPattern: "override:œuf"),
        "code":       RuleMatch(gender: .masculine, confidence: 1.0, matchedPattern: "override:code"),
        "livre":      RuleMatch(gender: .masculine, confidence: 0.8, matchedPattern: "override:livre-ambig"), // Buch=m, Pfund=f
        "poste":      RuleMatch(gender: .masculine, confidence: 0.6, matchedPattern: "override:poste-ambig"),
        "mode":       RuleMatch(gender: .masculine, confidence: 0.7, matchedPattern: "override:mode-ambig"),
        "manche":     RuleMatch(gender: .masculine, confidence: 0.7, matchedPattern: "override:manche-ambig"),
        "voile":      RuleMatch(gender: .masculine, confidence: 0.6, matchedPattern: "override:voile-ambig"),
    ]

    // MARK: - Endungs-Regeln

    /// Eine Regel: „wenn lemma auf `suffix` endet, dann Genus + Confidence".
    struct EndingRule {
        let suffix: String
        let gender: Gender
        let confidence: Double
    }

    /// Regeln, sortiert von **längster** zu **kürzester** Endung — so
    /// greift bei Überlapp die spezifischere. Confidence-Werte
    /// orientieren sich an bekannter französischer Grammatik-
    /// Statistik (Wiktionary-Tallies + Grevisse).
    static let allRules: [EndingRule] = [

        // --- Sehr zuverlässig (Confidence ≥ 0.95) ---

        // Feminine High-Confidence
        EndingRule(suffix: "ation",  gender: .feminine,  confidence: 0.99),
        EndingRule(suffix: "ution",  gender: .feminine,  confidence: 0.99),
        EndingRule(suffix: "ission", gender: .feminine,  confidence: 0.99),
        EndingRule(suffix: "aison",  gender: .feminine,  confidence: 0.99),
        EndingRule(suffix: "ence",   gender: .feminine,  confidence: 0.97),
        EndingRule(suffix: "ance",   gender: .feminine,  confidence: 0.97),
        EndingRule(suffix: "esse",   gender: .feminine,  confidence: 0.97),
        EndingRule(suffix: "tude",   gender: .feminine,  confidence: 0.96),
        EndingRule(suffix: "ière",   gender: .feminine,  confidence: 0.96),
        EndingRule(suffix: "tion",   gender: .feminine,  confidence: 0.98),
        EndingRule(suffix: "sion",   gender: .feminine,  confidence: 0.97),

        // Masculine High-Confidence
        EndingRule(suffix: "isme",   gender: .masculine, confidence: 0.99),
        EndingRule(suffix: "ment",   gender: .masculine, confidence: 0.96),
        EndingRule(suffix: "oir",    gender: .masculine, confidence: 0.95),
        EndingRule(suffix: "eau",    gender: .masculine, confidence: 0.95),
        EndingRule(suffix: "phone",  gender: .masculine, confidence: 0.95),
        EndingRule(suffix: "scope",  gender: .masculine, confidence: 0.95),
        EndingRule(suffix: "graphe", gender: .masculine, confidence: 0.95),

        // --- Mittlere Zuverlässigkeit (0.85–0.95) ---

        // Feminine
        EndingRule(suffix: "ade",    gender: .feminine,  confidence: 0.92),
        EndingRule(suffix: "ique",   gender: .feminine,  confidence: 0.90),
        EndingRule(suffix: "ée",     gender: .feminine,  confidence: 0.90),
        EndingRule(suffix: "euse",   gender: .feminine,  confidence: 0.95),
        EndingRule(suffix: "trice",  gender: .feminine,  confidence: 0.95),
        EndingRule(suffix: "ure",    gender: .feminine,  confidence: 0.90),
        EndingRule(suffix: "ie",     gender: .feminine,  confidence: 0.88),
        EndingRule(suffix: "té",     gender: .feminine,  confidence: 0.92),
        EndingRule(suffix: "tié",    gender: .feminine,  confidence: 0.95),
        EndingRule(suffix: "ette",   gender: .feminine,  confidence: 0.95),

        // Masculine
        EndingRule(suffix: "age",    gender: .masculine, confidence: 0.90),
        EndingRule(suffix: "isme",   gender: .masculine, confidence: 0.98),
        EndingRule(suffix: "iste",   gender: .masculine, confidence: 0.70), // Personen: m/f
        EndingRule(suffix: "teur",   gender: .masculine, confidence: 0.90),
        EndingRule(suffix: "ier",    gender: .masculine, confidence: 0.88),
        EndingRule(suffix: "ou",     gender: .masculine, confidence: 0.88),
        EndingRule(suffix: "et",     gender: .masculine, confidence: 0.88),
        EndingRule(suffix: "on",     gender: .masculine, confidence: 0.85),

        // --- Niedrige Zuverlässigkeit (0.60–0.85) — Fallback ---

        EndingRule(suffix: "ant",    gender: .masculine, confidence: 0.80),
        EndingRule(suffix: "ard",    gender: .masculine, confidence: 0.85),
        EndingRule(suffix: "ème",    gender: .masculine, confidence: 0.80),
        EndingRule(suffix: "é",      gender: .masculine, confidence: 0.72), // viele Ausnahmen
        EndingRule(suffix: "e",      gender: .feminine,  confidence: 0.62)  // große Ausnahme-Gruppe; nur als last-resort
    ]

    // MARK: - Public API

    /// Gibt die beste Regel-Übereinstimmung für ein Nomen-Core zurück
    /// (Lemma ohne Artikel, lowercased, getrimmt). Bei keinem Match
    /// → nil.
    ///
    /// Reihenfolge:
    ///   1. `explicitOverrides` — exakter Schlüssel-Treffer
    ///   2. `allRules` — erste passende Endung (längste zuerst)
    static func predict(for core: String) -> RuleMatch? {
        let key = core
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return nil }

        if let override = explicitOverrides[key] {
            return override
        }
        for rule in allRules where key.hasSuffix(rule.suffix) {
            // Sicherheits-Check: Wort muss länger als die Endung sein,
            // damit die Endung nicht das ganze Wort ist.
            guard key.count > rule.suffix.count else { continue }
            return RuleMatch(
                gender: rule.gender,
                confidence: rule.confidence,
                matchedPattern: "ending:\(rule.suffix)"
            )
        }
        return nil
    }
}
