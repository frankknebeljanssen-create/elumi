import Foundation

func shouldDisplayFrenchExclamationMark(_ cleaned: String) -> Bool {
    let normalizedWords = normalizedLookupWords(cleaned)
    guard !normalizedWords.isEmpty else { return false }

    let firstWord = normalizedWords[0]
    let firstTwoWords = normalizedWords.prefix(2).joined(separator: " ")
    let firstThreeWords = normalizedWords.prefix(3).joined(separator: " ")
    let compact = compactLookupKey(cleaned)
    let exclamationStarts: Set<String> = [
        "salut", "bonjour", "merci", "super", "bof", "ah", "oh",
        "bravo", "attention", "vite"
    ]
    let exclamationPhrases: Set<String> = [
        "c est parti", "à plus", "a plus", "au secours", "s il te plaît", "s il vous plaît"
    ]
    let compactExclamationPhrases: Set<String> = [
        "cestparti", "aplus", "ausecours", "silteplait", "silvousplait"
    ]

    return exclamationStarts.contains(firstWord) ||
        exclamationPhrases.contains(firstTwoWords) ||
        exclamationPhrases.contains(firstThreeWords) ||
        compactExclamationPhrases.contains(compact)
}

func shouldDisplayStatementPeriod(
    _ cleaned: String,
    language: StudyLanguage,
    cardType: CardType?
) -> Bool {
    guard cardType == .phrases else { return false }

    let normalizedWords = normalizedLookupWords(cleaned)
    guard normalizedWords.count >= 3 else { return false }

    let firstWord = normalizedWords[0]
    switch language {
    case .french:
        let statementStarts: Set<String> = [
            "je", "j", "tu", "il", "elle", "on", "nous", "vous", "ils", "elles",
            "c", "ce", "cet", "cette", "ces", "il", "elle", "on"
        ]
        return statementStarts.contains(firstWord)
    case .english:
        return false
    }
}

func inferredFrenchTerminalSentencePunctuation(_ cleaned: String, cardType: CardType?) -> String? {
    if shouldDisplayFrenchQuestionMark(original: cleaned, cleaned: cleaned) {
        return "?"
    }
    if shouldDisplayFrenchExclamationMark(cleaned) {
        return "!"
    }
    if shouldDisplayStatementPeriod(cleaned, language: .french, cardType: cardType) {
        return "."
    }
    return nil
}

func shouldDisplayFrenchQuestionMark(original: String, cleaned: String) -> Bool {
    let normalizedWords = normalizedLookupWords(cleaned)
    guard !normalizedWords.isEmpty else { return original.contains("?") }

    let singleWordQuestionStarts: Set<String> = [
        "comment", "ou", "où", "pourquoi", "quand", "combien",
        "quel", "quelle", "quels", "quelles", "qui", "que"
    ]
    let multiWordQuestionStarts: Set<String> = [
        "puis je", "pouvez vous", "est ce", "est ce que", "est ce qu",
        "ou est", "où est", "ou sont", "où sont",
        "ou habites", "où habites", "ou puis", "où puis",
        "combien de temps", "quelle heure"
    ]
    let shortQuestionPhrases: Set<String> = [
        "et toi", "et vous", "et lui", "et elle", "et eux",
        "ça va", "ca va", "et toi alors", "et vous alors"
    ]
    let compactQuestionPhrases: Set<String> = [
        "ettoi", "etvous", "etlui", "etelle", "eteux", "çava", "cava"
    ]
    let firstWord = normalizedWords[0]
    let firstTwoWords = normalizedWords.prefix(2).joined(separator: " ")
    let firstThreeWords = normalizedWords.prefix(3).joined(separator: " ")
    let compact = compactLookupKey(cleaned)

    if singleWordQuestionStarts.contains(firstWord) ||
        multiWordQuestionStarts.contains(firstTwoWords) ||
        multiWordQuestionStarts.contains(firstThreeWords) ||
        shortQuestionPhrases.contains(firstTwoWords) ||
        shortQuestionPhrases.contains(firstThreeWords) ||
        compactQuestionPhrases.contains(compact) {
        return true
    }

    let inversionPattern = #"(?iu)\b(?:est|faut|peut|doit|va|vient|habites|avez|pouvez|souhaitez)\s+(?:t\s+)?(?:il|elle|on|tu|vous|nous|je)\b"#
    if cleaned.range(of: inversionPattern, options: .regularExpression) != nil {
        return true
    }

    if original.contains("?") {
        return normalizedWords.count > 1
    }

    return false
}

func sourceDisplayText(_ text: String, sourceLanguage: StudyLanguage) -> String {
    switch sourceLanguage {
    case .french:
        let restored = restoringFrenchElisions(text)
        guard !restored.isEmpty else { return restored }
        let base = strippingTerminalSentencePunctuation(from: restored)
        guard !base.isEmpty else { return base }
        let inferredCardType: CardType? = normalizedLookupWords(base).count > 1 ? .phrases : .words

        if let punctuation = detectedTerminalSentencePunctuation(from: text), punctuation.contains("?") {
            return capitalizingSentenceStartIfTerminated(applyingTerminalSentencePunctuation(punctuation, to: base, style: .french))
        }

        if shouldDisplayFrenchQuestionMark(original: text, cleaned: restored) {
            return capitalizingSentenceStartIfTerminated(applyingTerminalSentencePunctuation("?", to: base, style: .french))
        }

        let preserved = preservingTerminalSentencePunctuation(
            from: text,
            in: base,
            style: .french,
            cardType: inferredCardType
        )
        if detectedTerminalSentencePunctuation(from: preserved) != nil {
            return capitalizingSentenceStartIfTerminated(preserved)
        }
        if let inferred = inferredFrenchTerminalSentencePunctuation(preserved, cardType: inferredCardType) {
            return capitalizingSentenceStartIfTerminated(
                applyingTerminalSentencePunctuation(inferred, to: preserved, style: .french)
            )
        }
        return preserved
    case .english:
        return cleanedQuizDisplayText(text)
    }
}
