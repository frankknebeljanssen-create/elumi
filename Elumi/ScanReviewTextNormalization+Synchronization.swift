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

/// **2026-06-09** — Satzanfang groß, wenn der Text als Satz endet.
///
/// Trägt ein Eintrag ein Satzendzeichen (`.`, `?`, `!`), ist er ein
/// vollständiger Satz und beginnt groß — in beiden Sprachen: „Ich höre
/// Musik.", „J'écoute de la musique.", „Wie geht es dir?". Ein einzelnes
/// Wort oder Fragment („ausschalten", „la voiture") bekommt kein
/// Satzzeichen und bleibt dadurch klein.
///
/// Warum als eigener Schritt: `TextNormalizationEngine.normalize`
/// kapitalisiert den ersten Token zwar bereits bei vorhandenem
/// Satzendzeichen — die Anzeige-Funktionen hängen das Satzzeichen aber
/// erst NACH dem Casing-Durchlauf an. Zu diesem Zeitpunkt war der Text
/// noch satzzeichenlos, die Regel lief also ins Leere und Sätze
/// erschienen klein („ich höre Musik.").
func capitalizingSentenceStartIfTerminated(_ text: String) -> String {
    guard detectedTerminalSentencePunctuation(from: text) != nil else { return text }
    guard let first = text.first, first.isLowercase else { return text }
    return first.uppercased() + text.dropFirst()
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

    // **2026-06-09** — Artikel bekommen NIE ein Satzzeichen.
    //
    // „la" ist kein Satz, und die deutsche Erklärung („die (bestimmter
    // Artikel, weiblich)") sieht für die Satz-Erkennung nur deshalb wie
    // einer aus, weil sie mit „die" beginnt und drei Wörter hat. Das
    // Ergebnis war „la." / „die (bestimmter Artikel, weiblich)."
    // (User-Bugreport). Beide Seiten bleiben hier unangetastet.
    if sourceLanguage == .french, isFrenchArticleEntry(cleanedSource) {
        return (cleanedSource, cleanedTarget)
    }
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
