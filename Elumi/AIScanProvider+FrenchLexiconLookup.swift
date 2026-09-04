import Foundation

// **Codeaudit 2026-09-03, Stufe 3 (Punkt 23)** — Rumpf nach
// `FrenchLexiconRepair` gezogen; hier bleibt nur die Weiterleitung.
extension AIScanProvider {
    func bestFrenchLexiconMatch(
        forSource source: String
    ) -> (sourceTerm: String, suggestions: [String], distance: Double)? {
        FrenchLexiconRepair.bestMatch(forSource: source)
    }

    func bestTrimmedFrenchLexiconMatch(
        forSource source: String
    ) -> (sourceTerm: String, suggestions: [String], distance: Double)? {
        FrenchLexiconRepair.bestTrimmedMatch(forSource: source)
    }

    func bestReverseFrenchLexiconMatch(
        forGermanTarget target: String,
        cardType: CardType
    ) -> (sourceTerm: String, targetTerm: String, distance: Double)? {
        FrenchLexiconRepair.bestReverseMatch(forGermanTarget: target, cardType: cardType)
    }
}
