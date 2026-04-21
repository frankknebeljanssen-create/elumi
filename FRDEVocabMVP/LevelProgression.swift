import Foundation

/// Emotionale Ebene über dem nackten Level-Zähler. Aus „Level 3" wird
/// „Entdecker", aus „Level 4" „Lernprofi" — der User bewegt sich nicht
/// mehr nur in einer Nummern-Progression, sondern erreicht **Titel**,
/// die seine Lernreise beschreiben.
///
/// Designprinzipien (User-Spec):
/// • **Ruhig, nicht verspielt** — keine Fantasy-Namen, keine albernen
///   Titel. Wörter wie „Starter", „Entdecker", „Lernprofi" tragen genug
///   Bedeutung, ohne auszuarten.
/// • **Zentral an einer Stelle** (hier) — Home-Board, Session-End,
///   Level-Up-Moment greifen alle auf diese Enum-Liste zu, kein Drift.
/// • **Zukunftsoffen**: spätere Levels ab 10 dürfen eigene Namen
///   bekommen, wenn produktiv gebraucht. Fallback ist immer
///   `"Level N"`.
///
/// Integration:
/// • `LevelProgression.name(forLevel: Int)` → Titel oder Fallback
/// • `LevelProgression.goalHint(currentXP:)` → „Nur noch N XP bis <Name>"
enum LevelProgression {

    /// Zentrale Namensliste. Index = Level (1-basiert). Wenn ein Level
    /// nicht in dieser Map steht → Fallback auf `"Level N"`, damit
    /// spätere Progressions-Stufen nicht ins Leere laufen.
    ///
    /// Namen in Deutsch, ohne Emojis/Punkte. Die Reihenfolge folgt
    /// einer Lern-Narrative: klein anfangen → weiter entdecken →
    /// Routine aufbauen → Expertise → Exzellenz.
    private static let names: [Int: String] = [
        1:  "Starter",
        2:  "Entdecker",
        3:  "Forscher",
        4:  "Lernprofi",
        5:  "Wortjäger",
        6:  "Sprachlotse",
        7:  "Formmeister",
        8:  "Meisterlerner",
        9:  "Virtuose",
        10: "Sprachkünstler",
    ]

    /// Liefert den Level-Titel — `"Entdecker"` bei Level 2 usw. Für
    /// Levels ohne Eintrag: `"Level N"`-Fallback. Nie `nil`, damit
    /// Call-Sites ohne Unwrap-Logik arbeiten können.
    static func name(forLevel level: Int) -> String {
        if let mapped = names[level] { return mapped }
        return "Level \(level)"
    }

    /// Erzeugt die „Auf dem Weg zu …"-Zeile für Home/Progress-Board.
    /// Format: „Auf dem Weg zu <NameDesNächstenLevels>". Wenn der User
    /// bereits im höchsten benannten Level ist → `"Ganz oben
    /// angekommen"` (zufriedener Endzustand statt „Level 11").
    static func goalContextLine(currentXP: Int) -> String {
        let current = GamificationConfig.level(forXP: currentXP)
        let next = current + 1
        let nextName = name(forLevel: next)
        // Wenn der nächste Level auch schon nur einen Zahl-Fallback
        // hat, formulieren wir den Satz neutraler — „Auf dem Weg zu
        // Level 11" wirkt technisch, deshalb der Sonderfall.
        if names[next] == nil, next > names.keys.max() ?? 0 {
            return "Ganz oben angekommen"
        }
        return "Auf dem Weg zu \(nextName)"
    }

    /// „Nur noch N XP bis <NameDesNächstenLevels>". Variant der alten
    /// `goalHint` in `HomeView`. Wenn der User bereits im höchsten
    /// benannten Level ist, gibt die Funktion `nil` zurück — die
    /// aufrufende View blendet die Zeile dann aus.
    static func xpGoalHint(currentXP: Int) -> String? {
        let current = GamificationConfig.level(forXP: currentXP)
        let nextLevel = current + 1
        let endXP = GamificationConfig.levelEndXP(for: current)
        let remaining = max(0, endXP - currentXP)
        guard remaining > 0 else { return nil }
        let title = name(forLevel: nextLevel)
        // Wenn der nächste Level ohne Namen bleibt, nutzen wir die
        // alte technische Formulierung — keine falsche emotionale
        // Verheißung.
        if names[nextLevel] == nil {
            return "Noch \(remaining) XP bis Level \(nextLevel)"
        }
        return "Nur noch \(remaining) XP bis \(title)"
    }
}
