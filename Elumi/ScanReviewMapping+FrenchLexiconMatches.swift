import Foundation

// **Codeaudit 2026-09-03, Stufe 3 (Punkt 23)** — Rumpf nach
// `FrenchLexiconRepair` gezogen; hier bleibt nur die Weiterleitung.
extension ScanReviewMapper {
    static func bestFrenchLexiconMatch(
        forSource source: String
    ) -> (sourceTerm: String, suggestions: [String], distance: Double)? {
        FrenchLexiconRepair.bestMatch(forSource: source)
    }

    static func bestTrimmedFrenchLexiconMatch(
        forSource source: String
    ) -> (sourceTerm: String, suggestions: [String], distance: Double)? {
        FrenchLexiconRepair.bestTrimmedMatch(forSource: source)
    }

    static func shouldForceFrenchLexiconReplacement(
        sourceText: String,
        targetText: String,
        sourceMatch: (sourceTerm: String, suggestions: [String], distance: Double)
    ) -> Bool {
        FrenchLexiconRepair.shouldForceReplacement(
            sourceText: sourceText,
            targetText: targetText,
            sourceMatch: sourceMatch,
            sourceWasTrimmed: false
        )
    }

    static func bestReverseFrenchLexiconMatch(
        forGermanTarget target: String,
        cardType: CardType
    ) -> (sourceTerm: String, targetTerm: String, distance: Double)? {
        FrenchLexiconRepair.bestReverseMatch(forGermanTarget: target, cardType: cardType)
    }

    static func shouldForceReverseFrenchLexiconReplacement(
        sourceText: String,
        targetText: String,
        reverseMatch: (sourceTerm: String, targetTerm: String, distance: Double)
    ) -> Bool {
        FrenchLexiconRepair.shouldForceReverseReplacement(
            sourceText: sourceText,
            targetText: targetText,
            reverseMatch: reverseMatch
        )
    }
}
