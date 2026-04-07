import Foundation

func answerVariants(for normalizedText: String, answerLanguageCode: String) -> Set<String> {
    let alternatives = splitAnswerAlternatives(from: normalizedText)
    var variants = Set(alternatives.isEmpty ? [normalizedText] : alternatives)

    if answerLanguageCode == "de-DE" {
        for alternative in Array(variants) {
            variants.formUnion(germanGenderAnswerVariants(for: alternative))
        }
    }

    return Set(variants.map {
        $0.replacingOccurrences(of: #" + "#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty })
}

func splitAnswerAlternatives(from normalizedText: String) -> [String] {
    let collapsedSeparators = normalizedText
        .replacingOccurrences(of: #"\s+(?:oder|bzw)\s+"#, with: "|", options: .regularExpression)
        .replacingOccurrences(of: #"\s*\/\s*"#, with: "|", options: .regularExpression)
        .replacingOccurrences(of: #"\s*\|\s*"#, with: "|", options: .regularExpression)

    return collapsedSeparators
        .components(separatedBy: "|")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
}

func germanGenderAnswerVariants(for normalizedText: String) -> Set<String> {
    let words = normalizedText.split(separator: " ").map(String.init)
    guard let lastWord = words.last else { return [normalizedText] }

    let prefix = words.dropLast().joined(separator: " ")
    let baseWordVariants = germanGenderWordVariants(for: lastWord)

    return Set(baseWordVariants.map { variant in
        prefix.isEmpty ? variant : "\(prefix) \(variant)"
    })
}

func germanGenderWordVariants(for word: String) -> Set<String> {
    var variants: Set<String> = [word]
    guard word.count >= 4 else { return variants }

    if word.hasSuffix("in") {
        let masculineBase = String(word.dropLast(2))
        if isLikelyGermanRoleWord(masculineBase) {
            variants.insert(masculineBase)
        }
    } else if isLikelyGermanRoleWord(word) {
        variants.insert(word + "in")
    }

    return variants
}

func isLikelyGermanRoleWord(_ word: String) -> Bool {
    let roleEndings = [
        "er", "or", "ent", "ant", "ist", "oge", "nom", "eur", "iker",
        "ling", "at", "ar", "är", "et", "ot", "d", "t", "nd", "nt",
        "cht", "rt", "ld"
    ]

    return roleEndings.contains { word.hasSuffix($0) }
}
