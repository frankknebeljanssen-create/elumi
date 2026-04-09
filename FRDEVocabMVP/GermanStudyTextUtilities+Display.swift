import Foundation
import SwiftUI

func germanDisplayText(_ text: String, cardType: CardType, sourceHint: String? = nil) -> String {
    let cleaned = cleanedQuizDisplayText(text)
    guard !cleaned.isEmpty else { return cleaned }

    // Non-nouns (verbs, adjectives, adverbs, etc.): always lowercase
    if cardType == .words, let hint = sourceHint, StandardVocabularyLoader.isNonNoun(hint) {
        return cleaned.lowercased()
    }

    // Always capitalize German nouns in multi-word text
    let wordCount = cleaned.split(separator: " ").count
    let isPhrase = cardType == .phrases || wordCount >= 3

    if isPhrase {
        let capitalized = capitalizingGermanNounsInPhrase(cleaned)
        let preserved = preservingTerminalSentencePunctuation(
            from: text,
            in: capitalized,
            style: .neutral,
            cardType: cardType
        )
        if detectedTerminalSentencePunctuation(from: preserved) != nil {
            return preserved
        }
        if let inferred = inferredGermanTerminalSentencePunctuation(preserved, cardType: cardType) {
            return applyingTerminalSentencePunctuation(inferred, to: preserved, style: .neutral)
        }
        return preserved
    }

    let isNonNoun = sourceHint.map { StandardVocabularyLoader.isNonNoun($0) } ?? false
    let shouldCapitalizeLeadingWord = !isNonNoun

    let separators = CharacterSet(charactersIn: "/|;")
    let segments = cleaned.components(separatedBy: separators)
    if segments.count > 1 {
        let separatorScalars = cleaned.unicodeScalars.filter { separators.contains($0) }.map(String.init)
        var rebuilt = ""

        for (index, segment) in segments.enumerated() {
            rebuilt += normalizedGermanWordSegment(
                segment,
                forceLeadingWordCapitalization: shouldCapitalizeLeadingWord
            )
            if index < separatorScalars.count {
                rebuilt += " \(separatorScalars[index]) "
            }
        }

        return rebuilt
            .replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return normalizedGermanWordSegment(
        cleaned,
        forceLeadingWordCapitalization: shouldCapitalizeLeadingWord
    )
}

func formattedGermanLexiconDisplayText(
    _ text: String,
    cardType: CardType,
    germanGender: LexiconGenderInfo? = nil,
    frenchGender: LexiconGenderInfo? = nil,
    sourceHint: String? = nil
) -> String {
    let displayed = germanDisplayText(text, cardType: cardType, sourceHint: sourceHint)
    guard cardType == .words else { return displayed }

    // Non-nouns stay lowercase — germanDisplayText already handled this
    if let hint = sourceHint, StandardVocabularyLoader.isNonNoun(hint) {
        return displayed
    }

    let normalized = normalizedLookupText(displayed)
    guard !normalized.isEmpty else { return displayed }
    let wordCount = normalized.split(separator: " ").count
    let effectiveGermanGender = germanGender ?? germanGenderInfo(for: displayed, cardType: cardType)
    let hasFrenchNounHint =
        frenchGender != nil ||
        hasFrenchNounHint(sourceHint ?? "", cardType: cardType)

    let shouldCapitalizeAsNoun =
        effectiveGermanGender != nil ||
        hasFrenchNounHint ||
        startsWithGermanArticle(displayed) ||
        (wordCount == 1 && DataStore.likelyGermanNounSet.contains(normalized))

    if shouldCapitalizeAsNoun {
        return stronglyCapitalizedGermanQuizWordText(displayed)
    }

    if wordCount == 1 {
        return lowercasingFirstGermanLetter(in: displayed)
    }

    guard !germanLexiconLowercaseExceptions.contains(normalized) else { return displayed }
    return displayed
}

func bootstrappedGermanText(_ text: String, cardType: CardType, sourceHint: String? = nil) -> String {
    let cleaned = cleanedQuizDisplayText(text)
    guard !cleaned.isEmpty else { return cleaned }

    if cardType == .phrases {
        return uppercasingFirstGermanLetter(in: cleaned)
    }

    return normalizedGermanWordSegment(
        cleaned,
        forceLeadingWordCapitalization: true
    )
}

func capitalizingGermanNounsInPhrase(_ text: String) -> String {
    let tokens = text.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
    guard !tokens.isEmpty else { return text }

    var rebuilt: [String] = []

    for index in tokens.indices {
        let token = tokens[index]
        let normalizedToken = normalizedLookupText(token)
        guard !normalizedToken.isEmpty else {
            rebuilt.append(token)
            continue
        }

        let previousNormalized = index > 0 ? normalizedLookupText(tokens[index - 1]) : ""
        let afterTrigger = germanNounTriggerWords.contains(previousNormalized) || germanHabenForms.contains(previousNormalized)
        let isKnownNoun = DataStore.likelyGermanNounSet.contains(normalizedToken)
        // Capitalize after articles/triggers (always) or if it's a known noun
        let shouldCapitalize = afterTrigger || isKnownNoun

        rebuilt.append(shouldCapitalize ? uppercasingFirstGermanLetter(in: token) : token)
    }

    return rebuilt.joined(separator: " ")
}

func looksLikeGermanDisplayText(_ text: String) -> Bool {
    let tokens = normalizedLookupText(text).split(separator: " ").map(String.init)
    guard !tokens.isEmpty else { return false }

    let germanMatches = tokens.filter { DataStore.germanLexiconWordSet.contains($0) }.count
    let ratio = Double(germanMatches) / Double(tokens.count)

    return startsWithGermanArticle(text) || ratio >= 0.45
}

func quizVisibleText(
    _ text: String,
    languageCode: String,
    category: String,
    sourceHint: String? = nil
) -> String {
    let cleaned = cleanedQuizDisplayText(text)

    // French: always lowercase
    guard languageCode == "de-DE" else { return cleaned.lowercased() }

    // German phrases: capitalize first letter only
    if category == CardType.phrases.categoryName {
        return uppercasingFirstGermanLetter(in: cleaned)
    }

    // German words: apply noun/verb/article casing rules
    return quizGermanWordCasing(cleaned, sourceHint: sourceHint)
}

/// German quiz casing: only nouns uppercase, everything else lowercase
private func quizGermanWordCasing(_ text: String, sourceHint: String?) -> String {
    let hint = sourceHint ?? ""
    let isNoun = StandardVocabularyLoader.isNoun(hint) || TrainingSessionController.hasFrenchArticle(hint) || startsWithGermanArticle(text)

    if isNoun {
        // Noun: article lowercase, noun uppercase
        let parts = text.components(separatedBy: "/")
        return parts.map { part in
            part.split(separator: " ").map { token in
                let lower = String(token).lowercased()
                if germanArticleHints.contains(lower) {
                    return lower
                }
                return uppercasingFirstGermanLetter(in: String(token))
            }.joined(separator: " ")
        }.joined(separator: " / ")
    }

    // Everything else (verbs, adjectives, etc.): all lowercase
    return text.lowercased()
}

func visibleQuizPromptText(_ text: String, category: String) -> String {
    // Casing is already applied during candidate creation in quizVisibleText()
    // Just clean display artifacts, don't re-capitalize
    return cleanedQuizDisplayText(text)
}

func visibleQuizAnswerText(_ text: String, category: String) -> String {
    // Casing is already applied during candidate creation in quizVisibleText()
    return cleanedQuizDisplayText(text)
}

func canonicalGermanQuizText(
    prompt: String,
    promptLanguageCode: String,
    answer: String,
    category: String,
    sourceHint: String? = nil
) -> String {
    let cleanedAnswer = cleanedQuizDisplayText(answer)
    guard !cleanedAnswer.isEmpty else { return cleanedAnswer }
    let cardType: CardType = category == CardType.words.categoryName ? .words : .phrases

    return germanDisplayText(
        cleanedAnswer,
        cardType: cardType,
        sourceHint: sourceHint ?? prompt
    )
}

func looksLikeGermanNounList(_ text: String) -> Bool {
    let cleaned = cleanedQuizDisplayText(text)
    guard !cleaned.isEmpty else { return false }

    let normalized = normalizedLookupText(cleaned)
    guard !normalized.isEmpty else { return false }

    let separators = CharacterSet(charactersIn: "/|,;")
    let segments = cleaned.components(separatedBy: separators)
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }

    guard !segments.isEmpty, segments.count <= 4 else { return false }

    return segments.allSatisfy { segment in
        let words = normalizedLookupText(segment).split(separator: " ").map(String.init)
        guard !words.isEmpty, words.count <= 2 else { return false }
        return !segment.contains("(") && !segment.contains(")")
    }
}

func quizPromptTypography(for prompt: String, category: String) -> Font {
    let cleaned = cleanedQuizDisplayText(prompt)
    let wordCount = cleaned.split(whereSeparator: \.isWhitespace).count
    let characterCount = cleaned.count

    if category == CardType.phrases.categoryName {
        if wordCount >= 6 || characterCount >= 34 {
            return AppTheme.Typography.cardTitle
        }
        if wordCount >= 4 || characterCount >= 24 {
            return AppTheme.Typography.screenTitle
        }
    }

    return AppTheme.Typography.largeTitle
}

func quizPromptLineLimit(for prompt: String, category: String) -> Int {
    let cleaned = cleanedQuizDisplayText(prompt)
    let wordCount = cleaned.split(whereSeparator: \.isWhitespace).count
    let characterCount = cleaned.count

    if category == CardType.phrases.categoryName, wordCount >= 4 || characterCount >= 24 {
        return 4
    }

    return 3
}

func quizPromptMinimumScale(for prompt: String, category: String) -> CGFloat {
    let cleaned = cleanedQuizDisplayText(prompt)
    let wordCount = cleaned.split(whereSeparator: \.isWhitespace).count
    let characterCount = cleaned.count

    if category == CardType.phrases.categoryName {
        if wordCount >= 6 || characterCount >= 34 {
            return 0.72
        }
        if wordCount >= 4 || characterCount >= 24 {
            return 0.8
        }
    }

    return 0.9
}
