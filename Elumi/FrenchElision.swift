import Foundation

/// Ob vor einem Wort der Artikel elidiert wird — „l'école", aber
/// „le hibou".
///
/// **Codeaudit 2026-09-03, Stufe 3 (Punkt 22)** — diese Regel stand
/// zweimal im Projekt, mit unterschiedlichem Ergebnis:
///
///   • `FrenchSpokenArticle.elidesArticle(before:)` kannte die
///     Ausnahmeliste für aspiriertes „h" und sprach korrekt „le hibou".
///   • `ArticleModeClassifier.startsWithVowelOrHMuet(_:)` prüfte nur
///     den Anfangsbuchstaben gegen eine Zeichenmenge und fragte
///     deshalb „l'hibou" ab.
///
/// Zwei Module widersprachen sich also bei identischem Wort: Das Kind
/// hörte „le hibou" und musste „l'" antworten. Betroffen waren 72
/// Nomen, davon 23 mit Lern-Niveau.
///
/// Jetzt gibt es eine Regel. Beide Aufrufer delegieren hierher.
enum FrenchElision {

    /// Gebräuchliche Wörter mit aspiriertem „h" — hier bleibt der volle
    /// Artikel stehen. Bewusst kurz gehalten: die Liste deckt den
    /// Schulwortschatz ab, nicht das gesamte Lexikon.
    static let aspiratedHWords: Set<String> = [
        "hamster", "handball", "hangar", "haricot", "hasard", "haut",
        "hauteur", "heros", "hibou", "hierarchie", "hockey", "hollande",
        "homard", "honte", "hoquet", "hors", "houx", "hublot", "huit",
        "hurlement"
    ]

    /// `true`, wenn der Artikel vor `phrase` zu „l'" verkürzt wird.
    ///
    /// Maßgeblich ist immer das **erste** Wort: „le meilleur ami" bleibt
    /// unelidiert, obwohl „ami" mit Vokal beginnt — der Artikel steht ja
    /// direkt vor „meilleur".
    ///
    /// **Kein „y"**: Französisch elidiert nicht vor halbvokalischem „y"
    /// — es heißt „le yaourt" und „le yoga". Der Klassifizierer hat „y"
    /// bisher als Vokal geführt und deshalb bei diesen Einträgen „l'"
    /// erwartet; mit der gemeinsamen Regel fällt das weg.
    static func elides(before phrase: String) -> Bool {
        let trimmed = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstToken = trimmed
            .split(whereSeparator: { $0.isWhitespace })
            .first
            .map(String.init) ?? trimmed

        // Diakritika falten, damit „é", „à" und „î" wie ihre
        // Grundvokale behandelt werden — „l'école", „l'île".
        let normalized = firstToken
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "fr_FR"))

        guard let first = normalized.first else { return false }
        if "aeiou".contains(first) { return true }
        guard first == "h" else { return false }
        return !aspiratedHWords.contains(normalized)
    }
}
