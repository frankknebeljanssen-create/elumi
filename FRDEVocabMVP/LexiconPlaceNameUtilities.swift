import Foundation

func looksLikeLexiconPhraseText(_ text: String, starterWords: Set<String>) -> Bool {
    let normalizedWords = normalizedLookupWords(text)
    guard !normalizedWords.isEmpty else { return false }

    if text.range(of: #"[.!?;:]"#, options: .regularExpression) != nil {
        return true
    }

    if normalizedWords.count >= 3 {
        return true
    }

    guard normalizedWords.count == 2, let first = normalizedWords.first else {
        return false
    }

    return starterWords.contains(first)
}

func cleanedLexiconPlaceNameToken(_ token: String) -> String {
    token.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?()[]{}\"'“”‘’"))
}

func startsWithUppercasedLetter(_ token: String) -> Bool {
    guard let firstLetter = token.first(where: \.isLetter) else { return false }
    return String(firstLetter) == String(firstLetter).uppercased()
}

func looksLikePlaceNameText(_ text: String) -> Bool {
    let tokens = text
        .split(whereSeparator: \.isWhitespace)
        .map(String.init)
        .map(cleanedLexiconPlaceNameToken(_:))
        .filter { !$0.isEmpty }

    guard tokens.count >= 3 else { return false }
    guard !tokens.contains(where: { $0.rangeOfCharacter(from: .decimalDigits) != nil }) else { return false }

    let normalizedTokens = tokens
        .map(normalizedLookupText(_:))
        .filter { !$0.isEmpty }

    let significantOriginalTokens = zip(tokens, normalizedTokens)
        .filter { !lexiconPlaceNameConnectorWords.contains($0.1) }
        .map(\.0)

    guard significantOriginalTokens.count >= 2 else { return false }
    guard significantOriginalTokens.allSatisfy(startsWithUppercasedLetter(_:)) else { return false }

    return normalizedTokens.contains(where: lexiconPlaceNameConnectorWords.contains)
}

func isLikelyPlaceNameLexiconEntry(_ entry: LexiconEntry) -> Bool {
    let source = cleanedQuizDisplayText(entry.sourceTerm)
    let target = cleanedQuizDisplayText(entry.targetTerm)

    guard !source.isEmpty, !target.isEmpty else { return false }

    let sourceLooksLikePlaceName = looksLikePlaceNameText(source)
    let targetLooksLikePlaceName = looksLikePlaceNameText(target)

    if sourceLooksLikePlaceName && targetLooksLikePlaceName {
        return true
    }

    guard sourceLooksLikePlaceName || targetLooksLikePlaceName else { return false }

    let compactSource = compactLookupKey(source)
    let compactTarget = compactLookupKey(target)
    guard !compactSource.isEmpty, !compactTarget.isEmpty else { return false }

    return compactSource == compactTarget ||
        compactSource.contains(compactTarget) ||
        compactTarget.contains(compactSource)
}

func resolvedLexiconCardType(for entry: LexiconEntry) -> CardType {
    // Respect explicit card_type from database
    if entry.cardType == .phrases {
        return .phrases
    }

    if entry.frenchGender != nil || entry.germanGender != nil {
        return .words
    }

    let sourceWordCount = normalizedLookupWords(entry.sourceTerm).count
    let targetWordCount = normalizedLookupWords(entry.targetTerm).count
    let maxWordCount = max(sourceWordCount, targetWordCount)

    if maxWordCount <= 1 {
        return .words
    }

    if looksLikeLexiconPhraseText(entry.sourceTerm, starterWords: lexiconFrenchPhraseStarterWords) {
        return .phrases
    }

    if looksLikeLexiconPhraseText(entry.targetTerm, starterWords: lexiconGermanPhraseStarterWords) {
        return .phrases
    }

    if maxWordCount == 2 {
        let germanWords = normalizedLookupWords(entry.targetTerm)
        if let firstGermanWord = germanWords.first,
           germanArticleHints.contains(firstGermanWord) {
            return .words
        }

        let startsWithGermanPhraseStarter = germanWords.first.map { lexiconGermanPhraseStarterWords.contains($0) } ?? false
        if startsWithGermanPhraseStarter {
            return .phrases
        }
    }

    return entry.cardType
}

func looksLikeFrenchNounSource(_ text: String) -> Bool {
    let normalized = normalizedLookupText(text)
    guard !normalized.isEmpty else { return false }

    let words = normalized.split(separator: " ").map(String.init)
    guard let first = words.first else { return false }

    if frenchArticleHints.contains(first) {
        return true
    }

    if words.count >= 2 {
        let firstTwo = "\(words[0]) \(words[1])"
        return frenchArticleHints.contains(firstTwo)
    }

    return false
}

func hasFrenchNounHint(_ text: String, cardType: CardType) -> Bool {
    looksLikeFrenchNounSource(text) || frenchGenderInfo(for: text, cardType: cardType) != nil
}

