import Foundation

/// Lexikon-gestützte Reparatur eines eingescannten Vokabelpaars.
///
/// **Codeaudit 2026-09-03, Stufe 3 (Punkt 23)** — diese Logik stand
/// zweimal im Projekt: einmal auf `AIScanProvider` (mit `ai`-Präfix an
/// den Helfern), einmal auf `ScanReviewMapper` (mit `mapper`-Präfix).
/// Rund 290 Zeilen, dieselben Schwellen 0.34 / 0.28 / ×0.92, und beide
/// Durchläufe laufen im selben Import nacheinander über dieselben Daten.
///
/// Dass die Kopien wirklich austauschbar sind, ist nachgewiesen und
/// nicht geschätzt: Beide Helfer-Sätze delegierten bereits an
/// `LexiconTextUtility`, und ein struktureller Vergleich der Rümpfe —
/// Kommentare entfernt, Präfixe normalisiert — ergab für alle sechs
/// Funktionspaare Zeichengleichheit.
///
/// Nicht mit hineingezogen wurde die dritte Kopie in
/// `ScanVocabularyPairRepair+ReverseLexicon.swift`. Sie sieht gleich
/// aus, benutzt aber eine **andere** Normalisierung (die globale
/// `normalizedLookupText` aus `ScanReviewTextNormalization`, die „ß" zu
/// „ss" expandiert und Apostrophe entfernt). Sie zusammenzulegen wäre
/// keine Deduplizierung, sondern eine stille Verhaltensänderung.
///
/// Der Typ arbeitet bewusst auf reinen Zeichenketten statt auf den
/// Entry-Typen der beiden Aufrufer — dadurch braucht er nichts über
/// `ScanAIResponseEntry` oder `ScanReviewEntry` zu wissen.
enum FrenchLexiconRepair {

    static func bestMatch(
        forSource source: String
    ) -> (sourceTerm: String, suggestions: [String], distance: Double)? {
        let lookupKey = LexiconTextUtility.normalizedLookupText(source)
        guard !lookupKey.isEmpty else { return nil }

        if let direct = DataStore.localTranslationLookup[.french]?[lookupKey], !direct.isEmpty {
            return (
                DataStore.cachedCanonicalSourceTerm(
                    for: lookupKey,
                    sourceLanguage: .french
                ) ?? source,
                direct,
                0
            )
        }

        guard let approximate = DataStore.cachedApproximateTranslationSuggestions(
            for: lookupKey,
            sourceLanguage: .french
        ), approximate.distance <= 0.24 else {
            return nil
        }

        return (
            DataStore.cachedCanonicalSourceTerm(
                for: approximate.lookupKey,
                sourceLanguage: .french
            ) ?? source,
            approximate.suggestions,
            approximate.distance
        )
    }

    static func bestTrimmedMatch(
        forSource source: String
    ) -> (sourceTerm: String, suggestions: [String], distance: Double)? {
        let tokens = LexiconTextUtility.normalizedWords(source)
        guard tokens.count >= 2 else { return nil }

        for prefixLength in stride(from: tokens.count - 1, through: 1, by: -1) {
            let candidate = tokens.prefix(prefixLength).joined(separator: " ")
            let trailing = tokens.dropFirst(prefixLength).joined(separator: " ")
            guard trailingLooksSuspicious(trailing) else { continue }
            guard let match = bestMatch(forSource: candidate) else { continue }
            if match.distance <= 0.2 {
                return match
            }
        }

        return nil
    }

    static func shouldForceReplacement(
        sourceText: String,
        targetText: String,
        sourceMatch: (sourceTerm: String, suggestions: [String], distance: Double),
        sourceWasTrimmed: Bool
    ) -> Bool {
        guard let firstSuggestion = sourceMatch.suggestions.first, !firstSuggestion.isEmpty else {
            return false
        }

        // Don't replace if punctuation mismatch (ça va ≠ Ça va?)
        if LexiconTextUtility.hasTerminalPunctuation(sourceMatch.sourceTerm)
            != LexiconTextUtility.hasTerminalPunctuation(sourceText) { return false }

        if targetMatchesSuggestions(targetText, suggestions: sourceMatch.suggestions) {
            return false
        }

        let sourceWordCount = max(1, LexiconTextUtility.normalizedWords(sourceMatch.sourceTerm).count)
        let targetWordCount = LexiconTextUtility.normalizedWords(targetText).count
        let suggestionWordCount = max(1, LexiconTextUtility.normalizedWords(firstSuggestion).count)

        // Ein zugeschnittener Treffer hat den Verdachtstest bereits im
        // Zuschnitt bestanden (`trailingLooksSuspicious`) — er gilt hier
        // ohne weitere Prüfung.
        if sourceWasTrimmed {
            return true
        }

        if sourceMatch.distance <= 0.08 && sourceWordCount <= 2 {
            return true
        }

        if targetLooksSuspicious(
            targetText,
            canonicalSource: sourceMatch.sourceTerm,
            firstSuggestion: firstSuggestion
        ) {
            return true
        }

        if sourceWordCount == 1 && suggestionWordCount == 1 && targetWordCount >= 2 {
            return true
        }

        return false
    }

    static func bestReverseMatch(
        forGermanTarget target: String,
        cardType: CardType
    ) -> (sourceTerm: String, targetTerm: String, distance: Double)? {
        let lookupKey = LexiconTextUtility.normalizedLookupText(target)
        let compactTarget = LexiconTextUtility.compactLookupKey(target)
        guard !lookupKey.isEmpty else { return nil }

        let frenchEntries = DataStore.internalLexiconEntries.filter {
            $0.sourceLanguage == .french && $0.cardType == cardType
        }

        if let exact = frenchEntries.first(where: {
            LexiconTextUtility.normalizedLookupText($0.targetTerm) == lookupKey ||
            LexiconTextUtility.compactLookupKey($0.targetTerm) == compactTarget
        }) {
            return (exact.sourceTerm, exact.targetTerm, 0)
        }

        return frenchEntries
            .compactMap { lexiconEntry -> (sourceTerm: String, targetTerm: String, distance: Double)? in
                let candidateKey = LexiconTextUtility.normalizedLookupText(lexiconEntry.targetTerm)
                let candidateCompact = LexiconTextUtility.compactLookupKey(lexiconEntry.targetTerm)
                guard !candidateKey.isEmpty, !candidateCompact.isEmpty else { return nil }

                let sharesPrefix =
                    candidateKey.hasPrefix(String(lookupKey.prefix(2))) ||
                    lookupKey.hasPrefix(String(candidateKey.prefix(2))) ||
                    candidateCompact.hasPrefix(String(compactTarget.prefix(3))) ||
                    compactTarget.hasPrefix(String(candidateCompact.prefix(3)))

                guard sharesPrefix else { return nil }

                let distance = LexiconTextUtility.levenshtein(lookupKey, candidateKey)
                let compactDistance = LexiconTextUtility.levenshtein(compactTarget, candidateCompact)
                let maxLength = max(lookupKey.count, candidateKey.count)
                let maxCompactLength = max(compactTarget.count, candidateCompact.count)
                guard maxLength > 0, maxCompactLength > 0 else { return nil }

                let ratio = Double(distance) / Double(maxLength)
                let compactRatio = Double(compactDistance) / Double(maxCompactLength)
                let effectiveRatio = min(ratio, compactRatio * 0.92)
                guard effectiveRatio <= 0.34 || compactRatio <= 0.28 else { return nil }

                return (lexiconEntry.sourceTerm, lexiconEntry.targetTerm, effectiveRatio)
            }
            .sorted {
                if $0.distance == $1.distance {
                    return $0.targetTerm.count < $1.targetTerm.count
                }
                return $0.distance < $1.distance
            }
            .first
    }

    static func shouldForceReverseReplacement(
        sourceText: String,
        targetText: String,
        reverseMatch: (sourceTerm: String, targetTerm: String, distance: Double)
    ) -> Bool {
        if reverseMatch.distance > 0.26 {
            return false
        }

        // Short German targets (≤5 chars) are too prone to false fuzzy matches (Gelb↔Geld, Rot↔Rat)
        // Require exact reverse match for short words
        let targetLength = LexiconTextUtility.normalizedLookupText(targetText).count
        if targetLength <= 5 && reverseMatch.distance > 0.05 {
            return false
        }

        if targetMatchesSuggestions(targetText, suggestions: [reverseMatch.targetTerm]) {
            return false
        }

        let sourceMatch = bestMatch(forSource: sourceText)
        let sourceLooksWeak = sourceMatch == nil || sourceMatch?.distance ?? 1 > 0.22
        return sourceLooksWeak || targetLooksSuspicious(
            targetText,
            canonicalSource: reverseMatch.sourceTerm,
            firstSuggestion: reverseMatch.targetTerm
        )
    }

    static func targetLooksSuspicious(
        _ target: String,
        canonicalSource: String,
        firstSuggestion: String
    ) -> Bool {
        let normalizedTarget = LexiconTextUtility.normalizedLookupText(target)
        guard !normalizedTarget.isEmpty else { return true }

        let compactTarget = LexiconTextUtility.compactLookupKey(target)
        let compactSource = LexiconTextUtility.compactLookupKey(canonicalSource)
        let targetWords = LexiconTextUtility.normalizedWords(target)
        let suggestionWords = LexiconTextUtility.normalizedWords(firstSuggestion)

        if target.rangeOfCharacter(from: .decimalDigits) != nil {
            return true
        }

        if looksLikeMarkerNoise(normalizedTarget) || looksLikeOCRCorruptedWordToken(normalizedTarget) {
            return true
        }

        if !compactSource.isEmpty && compactTarget.contains(compactSource) {
            return true
        }

        if targetWords.count >= suggestionWords.count + 2 {
            return true
        }

        return false
    }

    static func targetMatchesSuggestions(
        _ target: String,
        suggestions: [String]
    ) -> Bool {
        let normalizedTarget = LexiconTextUtility.normalizedLookupText(target)
        let compactTarget = LexiconTextUtility.compactLookupKey(target)
        guard !normalizedTarget.isEmpty else { return false }

        return suggestions.contains {
            LexiconTextUtility.normalizedLookupText($0) == normalizedTarget ||
            (!compactTarget.isEmpty && LexiconTextUtility.compactLookupKey($0) == compactTarget)
        }
    }

    static func trailingLooksSuspicious(_ trailing: String) -> Bool {
        let normalized = LexiconTextUtility.normalizedLookupText(trailing)
        guard !normalized.isEmpty else { return false }

        let tokens = normalized.split(separator: " ").map(String.init)
        let compact = normalized.replacingOccurrences(of: " ", with: "")
        let vowelCount = compact.filter { "aeiouyàâäæéèêëîïôöœùûü".contains($0) }.count
        let consonantCount = compact.filter(\.isLetter).count - vowelCount

        if tokens.allSatisfy({ looksLikeMarkerNoise($0) || looksLikeOCRCorruptedWordToken($0) }) {
            return true
        }

        if compact.range(of: #"^(?:adj|inv|fam|form|fom|fon){2,}[a-z]*$"#, options: .regularExpression) != nil {
            return true
        }

        if compact.count >= 5 && consonantCount >= 4 && vowelCount <= 1 {
            return true
        }

        return false
    }

    static func looksLikeMarkerNoise(_ text: String) -> Bool {
        let normalized = LexiconTextUtility.normalizedLookupText(text)
        guard !normalized.isEmpty else { return true }

        let exactNoise = [
            "fam", "adj", "adv", "inv", "fig", "form", "ugs", "hist", "pl",
            "adjinv", "adjinvfam", "invfam", "adjfam", "nopl",
            "fom", "fon", "fqm", "f0m", "adjinvfom", "invfom", "adjfom"
        ]

        if exactNoise.contains(normalized) {
            return true
        }

        return normalized.range(of: #"^[a-z]{1,2}$"#, options: .regularExpression) != nil
    }

    static func looksLikeOCRCorruptedWordToken(_ text: String) -> Bool {
        let normalized = LexiconTextUtility.normalizedLookupText(text)
        guard !normalized.isEmpty else { return false }

        return normalized
            .split(separator: " ")
            .map(String.init)
            .contains { token in
                let digitCount = token.filter(\.isNumber).count
                let letterCount = token.filter(\.isLetter).count

                guard digitCount >= 1, letterCount >= 1, token.count >= 2 else { return false }
                guard token.range(of: #"^[a-z0-9]+$"#, options: .regularExpression) != nil else { return false }
                if digitCount >= 2 && token.count >= 4 { return true }
                let digitRatio = Double(digitCount) / Double(token.count)
                return digitRatio >= 0.34
            }
    }
}
