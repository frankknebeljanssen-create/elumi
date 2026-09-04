import Foundation

// **Codeaudit 2026-09-03, Stufe 3 (Punkt 23)** — Rumpf nach
// `FrenchLexiconRepair` gezogen; hier bleibt nur die Weiterleitung.
extension AIScanProvider {
    func shouldForceFrenchLexiconReplacement(
        _ entry: ScanAIResponseEntry,
        sourceMatch: (sourceTerm: String, suggestions: [String], distance: Double),
        sourceWasTrimmed: Bool
    ) -> Bool {
        FrenchLexiconRepair.shouldForceReplacement(
            sourceText: entry.source,
            targetText: entry.target,
            sourceMatch: sourceMatch,
            sourceWasTrimmed: sourceWasTrimmed
        )
    }

    func shouldForceReverseFrenchLexiconReplacement(
        _ entry: ScanAIResponseEntry,
        reverseMatch: (sourceTerm: String, targetTerm: String, distance: Double)
    ) -> Bool {
        FrenchLexiconRepair.shouldForceReverseReplacement(
            sourceText: entry.source,
            targetText: entry.target,
            reverseMatch: reverseMatch
        )
    }

    func targetLooksSuspicious(
        _ target: String,
        canonicalSource: String,
        firstSuggestion: String
    ) -> Bool {
        FrenchLexiconRepair.targetLooksSuspicious(
            target,
            canonicalSource: canonicalSource,
            firstSuggestion: firstSuggestion
        )
    }

    func targetMatchesSuggestions(_ target: String, suggestions: [String]) -> Bool {
        FrenchLexiconRepair.targetMatchesSuggestions(target, suggestions: suggestions)
    }

    func aiTrailingLooksSuspicious(_ trailing: String) -> Bool {
        FrenchLexiconRepair.trailingLooksSuspicious(trailing)
    }

    func aiLooksLikeMarkerNoise(_ text: String) -> Bool {
        FrenchLexiconRepair.looksLikeMarkerNoise(text)
    }

    func aiLooksLikeOCRCorruptedWordToken(_ text: String) -> Bool {
        FrenchLexiconRepair.looksLikeOCRCorruptedWordToken(text)
    }
}
