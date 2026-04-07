import Foundation

extension ScanFreeTextPostProcessor {
    func prioritizedGrammarEntries(
        _ entries: [ScanFreeTextReviewEntry]
    ) -> [ScanFreeTextReviewEntry] {
        Array(deduplicatedReviewEntries(entries).prefix(4))
    }

    func freeTextGrammarReviewEntries(
        from sentences: [String],
        sourceLanguage: StudyLanguage
    ) -> [ScanFreeTextReviewEntry] {
        guard sourceLanguage == .french else { return [] }

        var pairs: [ScanFreeTextReviewEntry] = []
        var seenPatternKeys = Set<String>()

        for sentence in sentences {
            let lowered = sentence
                .lowercased()
                .folding(options: .diacriticInsensitive, locale: .current)

            func appendPattern(
                _ key: String,
                explanation: String
            ) {
                guard seenPatternKeys.insert(key).inserted else { return }
                pairs.append(
                    ScanFreeTextReviewEntry(
                        sourceText: sentence,
                        targetText: explanation,
                        cardType: .phrases,
                        category: .grammar,
                        note: "Grammatikpunkt aus dem Text",
                        isImportable: true
                    )
                )
            }

            if lowered.contains("?") || lowered.contains("est ce que") || lowered.contains("et toi") || lowered.contains("ca va") {
                appendPattern("question", explanation: "Grammatik: Fragesatz - das Fragezeichen gehört beim Lernen immer dazu.")
            }

            if lowered.range(of: #"\b[cdjlmnst]['’]"#, options: .regularExpression) != nil || lowered.contains("qu'") {
                appendPattern("elision", explanation: "Grammatik: Apostroph/Elision vor Vokal oder stummem h.")
            }

            if lowered.range(of: #"\b(ne|n['’]).+\bpas\b"#, options: .regularExpression) != nil {
                appendPattern("negation", explanation: "Grammatik: Verneinung mit ne ... pas.")
            }

            if lowered.contains("merci de ") {
                appendPattern("merci_de", explanation: "Grammatik: merci de + Infinitiv drückt eine höfliche Aufforderung aus.")
            }

            if lowered.hasPrefix("pas de ") {
                appendPattern("pas_de", explanation: "Grammatik: pas de + Nomen bedeutet ein Verbot oder das Fehlen von etwas.")
            }

            if lowered.range(of: #"\b(me|m['’]|te|t['’]|se|s['’]|nous|vous)\b"#, options: .regularExpression) != nil {
                appendPattern("pronominal", explanation: "Grammatik: pronominale Form mit m' / t' / s' vor dem Verb.")
            }

            if lowered.contains("c'est") || lowered.contains("c’est") {
                appendPattern("cest", explanation: "Grammatik: c'est ist eine feste Wendung für „das ist / so ist es“.")
            }
        }

        return Array(pairs.prefix(4))
    }
}
