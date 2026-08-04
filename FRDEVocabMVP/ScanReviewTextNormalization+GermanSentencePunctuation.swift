import Foundation

func shouldDisplayGermanQuestionMark(_ cleaned: String) -> Bool {
    let normalizedWords = normalizedLookupWords(cleaned)
    guard !normalizedWords.isEmpty else { return false }

    let firstWord = normalizedWords[0]
    let firstTwoWords = normalizedWords.prefix(2).joined(separator: " ")
    let firstThreeWords = normalizedWords.prefix(3).joined(separator: " ")
    let compact = compactLookupKey(cleaned)
    let singleWordQuestionStarts: Set<String> = [
        "wie", "wo", "woher", "wohin", "warum", "wann", "wer",
        "was", "welche", "welcher", "welches", "wessen", "wem", "wen", "wieso"
    ]
    let multiWordQuestionStarts: Set<String> = [
        "wie viel", "wie lange", "wie spät", "wie heisst", "wie heißt",
        "wo ist", "wo sind", "warum ist", "wann ist", "gibt es"
    ]
    let shortQuestionPhrases: Set<String> = [
        "und du", "und ihr", "und sie", "und er", "und wir",
        "und du dann", "und ihr dann", "und sie dann"
    ]
    let compactQuestionPhrases: Set<String> = [
        "unddu", "undihr", "undsiedann", "unddudann", "undwir"
    ]
    let yesNoStarts: Set<String> = [
        "ist", "sind", "bist", "seid", "hast", "habt", "haben",
        "kann", "kannst", "können", "könnt", "will", "willst", "wollt",
        "möchte", "möchtest", "möchten", "muss", "musst", "müssen", "dürfen", "darf"
    ]

    return singleWordQuestionStarts.contains(firstWord) ||
        multiWordQuestionStarts.contains(firstTwoWords) ||
        shortQuestionPhrases.contains(firstTwoWords) ||
        shortQuestionPhrases.contains(firstThreeWords) ||
        compactQuestionPhrases.contains(compact) ||
        yesNoStarts.contains(firstWord)
}

func shouldDisplayGermanExclamationMark(_ cleaned: String) -> Bool {
    let normalizedWords = normalizedLookupWords(cleaned)
    guard !normalizedWords.isEmpty else { return false }

    let firstWord = normalizedWords[0]
    let firstTwoWords = normalizedWords.prefix(2).joined(separator: " ")
    let firstThreeWords = normalizedWords.prefix(3).joined(separator: " ")
    let compact = compactLookupKey(cleaned)
    let exclamationStarts: Set<String> = [
        "hallo", "tschüss", "danke", "super", "ach", "oh",
        "hilfe", "vorsicht", "schnell"
    ]
    let exclamationPhrases: Set<String> = [
        "los gehts", "los geht's", "bis später", "bis morgen", "auf gehts", "auf geht's"
    ]
    let compactExclamationPhrases: Set<String> = [
        "losgehts", "bisspäter", "bismorgen", "aufgehts"
    ]

    return exclamationStarts.contains(firstWord) ||
        exclamationPhrases.contains(firstTwoWords) ||
        exclamationPhrases.contains(firstThreeWords) ||
        compactExclamationPhrases.contains(compact)
}

func shouldDisplayGermanStatementPeriod(_ cleaned: String, cardType: CardType?) -> Bool {
    guard cardType == .phrases else { return false }

    // **2026-06-09** — Strukturregel statt Anfangswort-Liste, siehe
    // `SentenceStructure` und die Begründung in der französischen
    // Entsprechung.
    return SentenceStructure.containsFiniteVerb(cleaned, language: .german)
}

func inferredGermanTerminalSentencePunctuation(_ cleaned: String, cardType: CardType?) -> String? {
    if shouldDisplayGermanQuestionMark(cleaned) {
        return "?"
    }
    if shouldDisplayGermanExclamationMark(cleaned) {
        return "!"
    }
    if shouldDisplayGermanStatementPeriod(cleaned, cardType: cardType) {
        return "."
    }
    return nil
}
