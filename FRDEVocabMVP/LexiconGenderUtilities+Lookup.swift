import Foundation

func deduplicatedLookupVariants(_ candidates: [String]) -> [String] {
    var seen = Set<String>()
    return candidates
        .map(normalizedLookupText(_:))
        .filter { !$0.isEmpty }
        .filter { seen.insert($0).inserted }
}

func deduplicatedCompactLookupVariants(_ candidates: [String]) -> [String] {
    var seen = Set<String>()
    return candidates
        .map(compactLookupKey(_:))
        .filter { !$0.isEmpty }
        .filter { seen.insert($0).inserted }
}

func frenchLookupCandidates(for text: String) -> [String] {
    let canonical = sourceDisplayText(text, sourceLanguage: .french)
    let apostropheSpaces = canonical
        .replacingOccurrences(of: "’", with: " ")
        .replacingOccurrences(of: "'", with: " ")
    let apostropheRemoved = canonical
        .replacingOccurrences(of: "’", with: "")
        .replacingOccurrences(of: "'", with: "")

    return [
        text,
        cleanedQuizDisplayText(text),
        restoringFrenchElisions(text),
        canonical,
        apostropheSpaces,
        apostropheRemoved
    ]
}

func germanLookupCandidates(for text: String, cardType: CardType, sourceHint: String?) -> [String] {
    [
        text,
        cleanedQuizDisplayText(text),
        bootstrappedGermanText(text, cardType: cardType, sourceHint: sourceHint)
    ]
}

func inferredGermanNounFlag(source: String, target: String, cardType: CardType) -> Bool {
    guard cardType == .words else { return false }

    if startsWithGermanArticle(target) || looksLikeFrenchNounSource(source) {
        return true
    }

    let targetWords = normalizedLookupWords(target)
    return targetWords.count == 1 && target.count >= 3
}

func boolFlag(from rawValue: String?) -> Bool? {
    guard let rawValue else { return nil }
    let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalized.isEmpty else { return nil }

    switch normalized {
    case "1", "true", "yes", "y", "oui", "ja":
        return true
    case "0", "false", "no", "n", "non", "nein":
        return false
    default:
        return nil
    }
}

func optionalTrimmed(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func lexiconGender(from storedValue: String?) -> LexiconNounGender? {
    guard let storedValue else { return nil }
    switch storedValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "masculine", "masc", "m", "m.":
        return .masculine
    case "feminine", "fem", "f", "f.":
        return .feminine
    case "neuter", "neut", "n", "n.":
        return .neuter
    case "plural", "pl", "pl.":
        return .plural
    default:
        return nil
    }
}
