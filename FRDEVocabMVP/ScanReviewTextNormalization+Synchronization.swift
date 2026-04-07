import Foundation

private func mirroredTerminalSentencePunctuation(
    from counterpart: String,
    onto source: String,
    sourceLanguage: StudyLanguage,
    cardType: CardType
) -> String {
    guard cardType == .phrases else { return source }
    guard detectedTerminalSentencePunctuation(from: source) == nil,
          let counterpartPunctuation = detectedTerminalSentencePunctuation(from: counterpart) else {
        return source
    }

    let cleanedSource = strippingTerminalSentencePunctuation(from: source)
    guard !cleanedSource.isEmpty else { return source }

    switch sourceLanguage {
    case .french:
        if counterpartPunctuation.contains("?") {
            let shouldMirrorQuestion =
                shouldDisplayFrenchQuestionMark(original: cleanedSource, cleaned: cleanedSource) ||
                shouldDisplayGermanQuestionMark(counterpart)
            if shouldMirrorQuestion {
                return applyingTerminalSentencePunctuation("?", to: cleanedSource, style: .french)
            }
        }

        if counterpartPunctuation.contains("!"),
           shouldDisplayFrenchExclamationMark(cleanedSource) {
            return applyingTerminalSentencePunctuation("!", to: cleanedSource, style: .french)
        }

        if counterpartPunctuation.contains("."),
           shouldDisplayStatementPeriod(cleanedSource, language: .french, cardType: cardType) {
            return applyingTerminalSentencePunctuation(".", to: cleanedSource, style: .french)
        }
    case .english:
        break
    }

    return source
}

private func mirroredGermanTerminalSentencePunctuation(
    from counterpart: String,
    onto target: String,
    cardType: CardType
) -> String {
    guard cardType == .phrases else { return target }
    guard detectedTerminalSentencePunctuation(from: target) == nil,
          let counterpartPunctuation = detectedTerminalSentencePunctuation(from: counterpart) else {
        return target
    }

    let cleanedTarget = strippingTerminalSentencePunctuation(from: target)
    guard !cleanedTarget.isEmpty else { return target }

    if counterpartPunctuation.contains("?") {
        let shouldMirrorQuestion =
            shouldDisplayGermanQuestionMark(cleanedTarget) ||
            shouldDisplayFrenchQuestionMark(original: counterpart, cleaned: counterpart)
        if shouldMirrorQuestion {
            return applyingTerminalSentencePunctuation("?", to: cleanedTarget, style: .neutral)
        }
    }

    if counterpartPunctuation.contains("!"),
       shouldDisplayGermanExclamationMark(cleanedTarget) {
        return applyingTerminalSentencePunctuation("!", to: cleanedTarget, style: .neutral)
    }

    if counterpartPunctuation.contains("."),
       shouldDisplayGermanStatementPeriod(cleanedTarget, cardType: cardType) {
        return applyingTerminalSentencePunctuation(".", to: cleanedTarget, style: .neutral)
    }

    return target
}

func synchronizedPairTerminalSentencePunctuation(
    source: String,
    target: String,
    sourceLanguage: StudyLanguage,
    cardType: CardType
) -> (source: String, target: String) {
    guard !source.isEmpty || !target.isEmpty else { return (source, target) }

    let cleanedSource = strippingTerminalSentencePunctuation(from: source)
    let cleanedTarget = strippingTerminalSentencePunctuation(from: target)
    let explicitPunctuation =
        detectedTerminalSentencePunctuation(from: source) ??
        detectedTerminalSentencePunctuation(from: target)

    let inferredPunctuation: String? = {
        let shouldInfer = cardType == .phrases ||
            normalizedLookupWords(cleanedSource).count > 1 ||
            normalizedLookupWords(cleanedTarget).count > 1
        guard shouldInfer else { return nil }

        switch sourceLanguage {
        case .french:
            if shouldDisplayFrenchQuestionMark(original: cleanedSource, cleaned: cleanedSource) ||
                shouldDisplayGermanQuestionMark(cleanedTarget) {
                return "?"
            }
            if shouldDisplayFrenchExclamationMark(cleanedSource) ||
                shouldDisplayGermanExclamationMark(cleanedTarget) {
                return "!"
            }
            if shouldDisplayStatementPeriod(cleanedSource, language: .french, cardType: cardType) ||
                shouldDisplayGermanStatementPeriod(cleanedTarget, cardType: cardType) {
                return "."
            }
        case .english:
            if shouldDisplayGermanQuestionMark(cleanedTarget) {
                return "?"
            }
            if shouldDisplayGermanExclamationMark(cleanedTarget) {
                return "!"
            }
            if shouldDisplayGermanStatementPeriod(cleanedTarget, cardType: cardType) {
                return "."
            }
        }

        return nil
    }()

    guard let resolvedPunctuation = explicitPunctuation ?? inferredPunctuation else {
        return (source, target)
    }

    let synchronizedSource = cleanedSource.isEmpty
        ? source
        : applyingTerminalSentencePunctuation(
            resolvedPunctuation,
            to: cleanedSource,
            style: sourceLanguage == .french ? .french : .neutral
        )
    let synchronizedTarget = cleanedTarget.isEmpty
        ? target
        : applyingTerminalSentencePunctuation(
            resolvedPunctuation,
            to: cleanedTarget,
            style: .neutral
        )

    return (synchronizedSource, synchronizedTarget)
}
