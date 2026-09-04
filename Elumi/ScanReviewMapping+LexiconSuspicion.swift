import Foundation

// **Codeaudit 2026-09-03, Stufe 3 (Punkt 23)** — Rumpf nach
// `FrenchLexiconRepair` gezogen; hier bleibt nur die Weiterleitung.
extension ScanReviewMapper {
    static func targetLooksSuspicious(
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

    static func targetMatchesSuggestions(_ target: String, suggestions: [String]) -> Bool {
        FrenchLexiconRepair.targetMatchesSuggestions(target, suggestions: suggestions)
    }

    static func mapperTrailingLooksSuspicious(_ trailing: String) -> Bool {
        FrenchLexiconRepair.trailingLooksSuspicious(trailing)
    }

    static func mapperLooksLikeMarkerNoise(_ text: String) -> Bool {
        FrenchLexiconRepair.looksLikeMarkerNoise(text)
    }

    static func mapperLooksLikeOCRCorruptedWordToken(_ text: String) -> Bool {
        FrenchLexiconRepair.looksLikeOCRCorruptedWordToken(text)
    }
}
