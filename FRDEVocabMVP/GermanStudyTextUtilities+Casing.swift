import Foundation

func stronglyCapitalizedGermanQuizWordText(_ text: String) -> String {
    let parts = text.components(separatedBy: "/")
    let rebuilt = parts.map { part in
        part
            .split(separator: " ")
            .map { token in
                let raw = String(token)
                return uppercasingFirstGermanLetter(in: raw)
            }
            .joined(separator: " ")
    }
    .joined(separator: " / ")

    return rebuilt
        .replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func startsWithGermanArticle(_ text: String) -> Bool {
    let normalized = normalizedLookupText(text)
    let words = normalized.split(separator: " ").map(String.init)
    guard let first = words.first else { return false }
    return germanArticleHints.contains(first)
}

func leadingGermanArticle(in text: String) -> String? {
    let normalized = normalizedLookupText(text)
    let words = normalized.split(separator: " ").map(String.init)
    guard let first = words.first, germanArticleHints.contains(first) else { return nil }
    return first
}

func normalizedGermanWordSegment(_ segment: String, forceLeadingWordCapitalization: Bool) -> String {
    let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return trimmed }

    if startsWithGermanArticle(trimmed) {
        return uppercasingAfterLeadingGermanArticle(trimmed)
    }

    guard forceLeadingWordCapitalization else { return trimmed }
    return uppercasingFirstGermanLetter(in: trimmed)
}

func uppercasingAfterLeadingGermanArticle(_ text: String) -> String {
    let pattern = #"(?iu)^(\s*(?:der|die|das|ein|eine|einer|einem|einen|den|dem|des|kein|keine)\s+)([a-zäöüß])"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return uppercasingFirstGermanLetter(in: text)
    }

    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          let letterRange = Range(match.range(at: 2), in: text) else {
        return uppercasingFirstGermanLetter(in: text)
    }

    let mutable = NSMutableString(string: text)
    mutable.replaceCharacters(in: match.range(at: 2), with: String(text[letterRange]).uppercased())
    return mutable as String
}

func uppercasingFirstGermanLetter(in text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: #"(?iu)^(\s*)([a-zäöüß])"#) else {
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          let letterRange = Range(match.range(at: 2), in: text) else {
        return text
    }

    let mutable = NSMutableString(string: text)
    mutable.replaceCharacters(in: match.range(at: 2), with: String(text[letterRange]).uppercased())
    return mutable as String
}

func lowercasingFirstGermanLetter(in text: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: #"(?iu)^(\s*)([A-ZÄÖÜ])"#) else {
        return text.prefix(1).lowercased() + text.dropFirst()
    }

    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    guard let match = regex.firstMatch(in: text, options: [], range: range),
          let letterRange = Range(match.range(at: 2), in: text) else {
        return text
    }

    let mutable = NSMutableString(string: text)
    mutable.replaceCharacters(in: match.range(at: 2), with: String(text[letterRange]).lowercased())
    return mutable as String
}
