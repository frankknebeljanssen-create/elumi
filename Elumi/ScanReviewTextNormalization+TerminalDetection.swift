import Foundation

private func terminalSentencePunctuationProbeText(_ text: String) -> String {
    var probe = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !probe.isEmpty else { return probe }

    let trailingPatterns = [
        #"\s*(?:\[[^\[\]]+\]|\/[^\/]+\/|\([^\(\)]+\))\s*$"#,
        #"\s*(?:(?:adj|adv|inv|fam|form|fig|ugs|hist|no\s*pl|pl)\.?\s*)+\s*$"#
    ]

    var didChange = true
    while didChange {
        didChange = false
        for pattern in trailingPatterns {
            let updated = probe.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.regularExpression]
            )
            if updated != probe {
                probe = updated.trimmingCharacters(in: .whitespacesAndNewlines)
                didChange = true
            }
        }
    }

    return probe
}

func detectedTerminalSentencePunctuation(from text: String) -> String? {
    let probe = terminalSentencePunctuationProbeText(text)
    guard let range = probe.range(
        of: #"(?:\?\!|\!\?|[.!?…])\s*$"#,
        options: .regularExpression
    ) else {
        return nil
    }

    let punctuation = probe[range].trimmingCharacters(in: .whitespacesAndNewlines)
    return punctuation.isEmpty ? nil : punctuation
}

func strippingTerminalSentencePunctuation(from text: String) -> String {
    text
        .replacingOccurrences(
            of: #"\s*(?:\?\!|\!\?|[.!?…])$"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func shouldKeepTerminalSentencePunctuation(
    from original: String,
    cleaned: String,
    cardType: CardType? = nil
) -> Bool {
    guard let punctuation = detectedTerminalSentencePunctuation(from: original) else { return false }
    let normalizedWords = normalizedLookupWords(cleaned)

    if punctuation.contains("?") || punctuation.contains("!") {
        return !normalizedWords.isEmpty
    }

    if cardType == .phrases {
        return !normalizedWords.isEmpty
    }

    return normalizedWords.count > 1
}

func applyingTerminalSentencePunctuation(
    _ punctuation: String,
    to text: String,
    style: SentenceTerminalPunctuationStyle
) -> String {
    let base = strippingTerminalSentencePunctuation(from: text)
    guard !base.isEmpty else { return base }

    switch style {
    case .french:
        if punctuation.contains("?") || punctuation.contains("!") {
            return base + " " + punctuation
        }
        return base + punctuation
    case .neutral:
        return base + punctuation
    }
}

func preservingTerminalSentencePunctuation(
    from original: String,
    in text: String,
    style: SentenceTerminalPunctuationStyle,
    cardType: CardType? = nil
) -> String {
    let base = strippingTerminalSentencePunctuation(from: text)
    guard !base.isEmpty else { return base }
    guard shouldKeepTerminalSentencePunctuation(from: original, cleaned: base, cardType: cardType),
          let punctuation = detectedTerminalSentencePunctuation(from: original) else {
        return base
    }
    return applyingTerminalSentencePunctuation(punctuation, to: base, style: style)
}
