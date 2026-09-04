import Foundation

/// Sortiert deutsche Übersetzungsvorschläge danach, wie gut ihre
/// Satzzeichen zum französischen Quelltext passen — „Wie geht's?" soll
/// eine Frage als Vorschlag bekommen, keine Aussage.
///
/// **Codeaudit 2026-09-03, Stufe 2** — diese Logik stand zweimal
/// zeichengleich im Projekt: als private Methoden auf
/// `ScanImportNormalizer` (+GermanTarget.swift) und als Methoden auf
/// `ScanVocabularyPairRepair` (hier). Einziger Unterschied war das
/// Schlüsselwort `private`; beide Typen bekommen dieselben beiden
/// Closures aus derselben View (`ScanImportView+RepairDependencies`),
/// das Ergebnis konnte also nie abweichen. Jetzt lebt die Regel einmal
/// hier, beide Aufrufer delegieren.
///
/// Die Punktuations-Quellen kommen als Parameter herein, damit dieser
/// Typ nichts über die beiden Dependency-Container wissen muss.
enum GermanSuggestionPrioritizer {

    /// - Parameters:
    ///   - detectedTerminalPunctuation: Liest das tatsächlich vorhandene
    ///     Satzendzeichen aus einem Text.
    ///   - inferredGermanTerminalPunctuation: Leitet das erwartete
    ///     Satzendzeichen aus Textform und Kartentyp ab.
    static func prioritized(
        _ suggestions: [String],
        forSource source: String,
        cardType: CardType,
        detectedTerminalPunctuation: (String) -> String?,
        inferredGermanTerminalPunctuation: (String, CardType?) -> String?
    ) -> [String] {
        guard suggestions.count > 1 else { return suggestions }
        guard let sourcePunctuation = detectedTerminalPunctuation(source) else {
            return suggestions
        }

        return suggestions.sorted { lhs, rhs in
            let lhsScore = punctuationScore(
                lhs,
                matching: sourcePunctuation,
                cardType: cardType,
                detectedTerminalPunctuation: detectedTerminalPunctuation,
                inferredGermanTerminalPunctuation: inferredGermanTerminalPunctuation
            )
            let rhsScore = punctuationScore(
                rhs,
                matching: sourcePunctuation,
                cardType: cardType,
                detectedTerminalPunctuation: detectedTerminalPunctuation,
                inferredGermanTerminalPunctuation: inferredGermanTerminalPunctuation
            )

            if lhsScore == rhsScore {
                return lhs.count < rhs.count
            }
            return lhsScore > rhsScore
        }
    }

    /// 6 = Satzzeichen steht wirklich im Vorschlag, 5 = es lässt sich
    /// ableiten, 1 = falsches, aber immerhin ein Satzzeichen, 0 = keines.
    static func punctuationScore(
        _ suggestion: String,
        matching sourcePunctuation: String,
        cardType: CardType,
        detectedTerminalPunctuation: (String) -> String?,
        inferredGermanTerminalPunctuation: (String, CardType?) -> String?
    ) -> Int {
        let detectedSuggestionPunctuation = detectedTerminalPunctuation(suggestion)
        let inferredSuggestionPunctuation = inferredGermanTerminalPunctuation(suggestion, cardType)

        if sourcePunctuation.contains("?") {
            if detectedSuggestionPunctuation?.contains("?") == true { return 6 }
            if inferredSuggestionPunctuation?.contains("?") == true { return 5 }
            if detectedSuggestionPunctuation?.contains(".") == true { return 1 }
            return 0
        }

        if sourcePunctuation.contains("!") {
            if detectedSuggestionPunctuation?.contains("!") == true { return 6 }
            if inferredSuggestionPunctuation?.contains("!") == true { return 5 }
            if detectedSuggestionPunctuation?.contains("?") == true { return 1 }
            return 0
        }

        if sourcePunctuation.contains(".") {
            if detectedSuggestionPunctuation?.contains(".") == true { return 6 }
            if inferredSuggestionPunctuation?.contains(".") == true { return 5 }
            if detectedSuggestionPunctuation?.contains("?") == true { return 1 }
            return 0
        }

        return 0
    }
}

extension ScanVocabularyPairRepair {
    func prioritizedGermanSuggestions(
        _ suggestions: [String],
        forSource source: String,
        cardType: CardType
    ) -> [String] {
        GermanSuggestionPrioritizer.prioritized(
            suggestions,
            forSource: source,
            cardType: cardType,
            detectedTerminalPunctuation: dependencies.detectedTerminalSentencePunctuation,
            inferredGermanTerminalPunctuation: dependencies.inferredGermanTerminalSentencePunctuation
        )
    }
}
