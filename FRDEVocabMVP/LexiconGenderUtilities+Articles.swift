import Foundation

func leadingFrenchArticle(in text: String) -> String? {
    let normalized = normalizedLookupText(text)
    let words = normalized.split(separator: " ").map(String.init)
    guard !words.isEmpty else { return nil }

    if words.count >= 2 {
        let firstTwo = "\(words[0]) \(words[1])"
        if ["de la", "de l", "a la", "a l"].contains(firstTwo) {
            return firstTwo
        }
    }

    guard let first = words.first else { return nil }
    return frenchArticleHints.contains(first) ? first : nil
}

func strippingLeadingFrenchArticle(from text: String) -> String {
    let normalized = normalizedLookupText(text)
    let words = normalized.split(separator: " ").map(String.init)
    guard !words.isEmpty else { return normalized }

    if words.count >= 2 {
        let firstTwo = "\(words[0]) \(words[1])"
        if ["de la", "de l", "a la", "a l"].contains(firstTwo) {
            return words.dropFirst(2).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    if let first = words.first, frenchArticleHints.contains(first) {
        return words.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return normalized
}

func strippingLeadingGermanArticle(from text: String) -> String {
    let normalized = normalizedLookupText(text)
    let words = normalized.split(separator: " ").map(String.init)
    guard !words.isEmpty else { return normalized }

    if let first = words.first, germanArticleHints.contains(first) {
        return words.dropFirst().joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    return normalized
}

func suggestedFrenchArticle(for gender: LexiconNounGender) -> String? {
    switch gender {
    case .masculine:
        return "le"
    case .feminine:
        return "la"
    case .plural:
        return "les"
    case .neuter:
        return nil
    }
}

func suggestedGermanArticle(for gender: LexiconNounGender) -> String? {
    switch gender {
    case .masculine:
        return "der"
    case .feminine:
        return "die"
    case .neuter:
        return "das"
    case .plural:
        return "die"
    }
}

func exactFrenchGenderInfo(
    gender: LexiconNounGender?,
    article: String?
) -> LexiconGenderInfo? {
    guard let gender else { return nil }
    return LexiconGenderInfo(
        gender: gender,
        article: article ?? suggestedFrenchArticle(for: gender),
        isHeuristic: false
    )
}

func exactGermanGenderInfo(
    gender: LexiconNounGender?,
    article: String?
) -> LexiconGenderInfo? {
    guard let gender else { return nil }
    return LexiconGenderInfo(
        gender: gender,
        article: article ?? suggestedGermanArticle(for: gender),
        isHeuristic: false
    )
}

func preferredLexiconGenderInfo(
    _ primary: LexiconGenderInfo?,
    _ fallback: LexiconGenderInfo?
) -> LexiconGenderInfo? {
    switch (primary, fallback) {
    case let (primary?, fallback?):
        if primary.isHeuristic != fallback.isHeuristic {
            return primary.isHeuristic ? fallback : primary
        }
        if (primary.article == nil || primary.article?.isEmpty == true),
           let fallbackArticle = fallback.article,
           !fallbackArticle.isEmpty {
            return fallback
        }
        return primary
    case let (primary?, nil):
        return primary
    case let (nil, fallback?):
        return fallback
    case (nil, nil):
        return nil
    }
}
