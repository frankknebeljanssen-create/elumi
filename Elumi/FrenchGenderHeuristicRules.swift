import Foundation

/// **Genus-Typ für die Französisch-Genus-Pipeline.**
///
/// Bis 2026-08-07 enthielt dieser Typ zusätzlich eine Endungs-Heuristik
/// (`predict(for:)`), die bei fehlendem `gender_fr` aus einer Tabelle
/// typischer Nomen-Endungen riet (z. B. „endet auf -e → feminin" bei nur
/// 62 % Confidence). Sie ist entfernt, weil der User kein Raten will und
/// die Datengrundlage jetzt vollständig ist: alle ~17.200 Nomen im
/// Master-Lexikon haben ein echtes `gender_fr` aus der DB, mit Ausnahme
/// der bewusst artikellosen Nomen (Monate, Eigennamen — siehe
/// `isArticlelessFrenchNoun` in `LexiconGenderUtilities+Constants.swift`),
/// die ohnehin nie ein Genus brauchen.
///
/// Der `Gender`-Typ selbst bleibt bestehen — er ist der gemeinsame Werttyp
/// für `gender_fr`-Werte aus der DB (siehe `FrenchGenderResolver.swift`,
/// `StandardVocabularyLoader.swift`).
enum FrenchGenderHeuristicRules {
    enum Gender: String, Equatable {
        case masculine = "m"
        case feminine = "f"
    }
}
