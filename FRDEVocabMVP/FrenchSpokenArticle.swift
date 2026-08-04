import Foundation

/// **Artikel beim Vorsprechen französischer Nomen** (User-Spec
/// 2026-06-09).
///
/// Ein französisches Nomen ohne Artikel vorzusprechen („mai", „voiture")
/// verschenkt genau die Information, die man beim Lernen mitnehmen
/// muss — das Genus. Gesprochen wird deshalb „le mai", „la voiture",
/// „les frères".
///
/// **Scope:** nur Vokabeln (`CardType.words`) und nur die französische
/// Seite. Phrasen bleiben unangetastet — dort steht das Nomen im Satz
/// und hat seinen Artikel entweder schon oder braucht keinen.
///
/// **Nur bei sicherem Genus** (User-Entscheidung): Quelle ist entweder
/// ein bereits im Eintrag stehender Artikel oder das gepflegte
/// `gender`-Feld des Standard-Wortschatzes. Die Suffix-Heuristik aus
/// `frenchGenderInfo(for:cardType:)` wird bewusst NICHT genutzt — sie
/// liegt bei Ausnahmen wie „le musée" falsch, und ein falsch
/// vorgesprochenes Genus prägt sich genauso ein wie ein richtiges.
/// Ohne sichere Quelle wird das Wort nackt gesprochen, wie bisher.
enum FrenchSpokenArticle {

    /// Liefert den vorzusprechenden Text — mit Artikel, wenn es sich um
    /// ein französisches Nomen mit sicher bekanntem Genus handelt.
    /// Sonst unverändert `text`.
    static func spokenText(
        for text: String,
        wordClass: String?,
        languageCode: String,
        cardType: CardType
    ) -> String {
        guard cardType == .words,
              languageCode.hasPrefix("fr"),
              wordClass?.lowercased() == "noun" else {
            return text
        }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }

        // Steht der Artikel schon im Eintrag („la voiture", „les
        // frères"), ist nichts zu tun — inklusive Plural, der sich
        // ausschließlich so erkennen lässt.
        guard leadingFrenchArticle(in: trimmed) == nil else { return text }

        // Artikellose Nomen: Monatsnamen und Eigennamen stehen im
        // Französischen ohne Artikel („en mai", „Paris"). Sie sind zwar
        // maskulin, „le mai" wäre aber falsch — der Guard steht hier
        // unabhängig davon, ob die Genus-Quelle für sie je einen Wert
        // liefert.
        guard !isArticleless(trimmed) else { return text }

        guard let gender = StandardVocabularyLoader.frenchGender(for: trimmed) else {
            return text
        }

        switch gender.lowercased() {
        case "m": return "\(articlePrefix(masculine: true, before: trimmed))\(trimmed)"
        case "f": return "\(articlePrefix(masculine: false, before: trimmed))\(trimmed)"
        default:  return text
        }
    }

    /// Nomen, die im Französischen grundsätzlich ohne Artikel stehen:
    /// Monatsnamen und Eigennamen. Ein Artikel davor wäre schlicht
    /// falsches Französisch („le mai").
    private static func isArticleless(_ word: String) -> Bool {
        let normalized = word
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if monthNames.contains(normalized) { return true }
        // Eigennamen: im Lexikon durchgängig großgeschrieben („Paris",
        // „Noël"), während Gattungsnamen klein stehen.
        return word.first?.isUppercase == true
    }

    /// Die zwölf Monate in diakritik-freier Schreibweise — der Vergleich
    /// oben faltet Akzente weg („aout" trifft auch „août").
    private static let monthNames: Set<String> = [
        "janvier", "fevrier", "mars", "avril", "mai", "juin",
        "juillet", "aout", "septembre", "octobre", "novembre", "decembre"
    ]

    /// „le "/„la " — oder „l'" bei Elision. Ohne Elision spräche die
    /// TTS-Stimme „le école" wörtlich aus, was hörbar falsch ist.
    private static func articlePrefix(masculine: Bool, before word: String) -> String {
        guard elidesArticle(before: word) else {
            return masculine ? "le " : "la "
        }
        return "l'"
    }

    /// Elision vor Vokal ist im Französischen zwingend. Beim
    /// stummen „h" ebenfalls („l'homme", „l'heure") — die Ausnahmen mit
    /// aspiriertem „h" („le héros", „le hibou") sind überschaubar und
    /// unten gelistet.
    private static func elidesArticle(before word: String) -> Bool {
        let normalized = word
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))

        guard let first = normalized.first else { return false }

        if "aeiou".contains(first) { return true }

        guard first == "h" else { return false }
        return !aspiratedHWords.contains { normalized == $0 || normalized.hasPrefix("\($0) ") }
    }

    /// Gebräuchliche Wörter mit aspiriertem „h" — hier bleibt der volle
    /// Artikel stehen. Bewusst kurz gehalten: die Liste deckt den
    /// Schulwortschatz ab, nicht das gesamte Lexikon.
    private static let aspiratedHWords: Set<String> = [
        "hamster", "handball", "hangar", "haricot", "hasard", "haut",
        "hauteur", "heros", "hibou", "hierarchie", "hockey", "hollande",
        "homard", "honte", "hoquet", "hors", "houx", "hublot", "huit",
        "hurlement"
    ]
}
