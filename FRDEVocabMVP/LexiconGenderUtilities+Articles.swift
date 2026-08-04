import Foundation

func leadingFrenchArticle(in text: String) -> String? {
    let normalized = normalizedLookupText(text)

    // Detect l' elision: "l'ordonnance" → article is "l'"
    let lowerTrimmed = normalized.lowercased()
    if lowerTrimmed.hasPrefix("l'") || lowerTrimmed.hasPrefix("l\u{2019}") {
        return "l'"
    }

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

// MARK: - Französische Artikel als eigene Wortart

/// **2026-06-09** — Der geschlossene Satz französischer Artikel, fest
/// hinterlegt statt geraten.
///
/// Grund (User-Bugreport): Die Wortart-Analyse kennt gar keine Kategorie
/// „Artikel". Einzeln gescannte Artikel landeten deshalb in der jeweils
/// nächstbesten Schublade — `le` als Pronomen, `la` als Adverb, `l'` nur
/// als „Wort". Artikel sind aber eine geschlossene, vollständig
/// aufzählbare Klasse: Es gibt genau diese und keine weiteren, also gibt
/// es hier nichts zu erkennen, nur nachzuschlagen.
///
/// Der Wert ist die kanonische deutsche Beschreibung — Artikel lassen
/// sich nicht wie Vokabeln „übersetzen" (`le` heißt nicht schlicht
/// „der"), deshalb steht die Funktion dabei.
let frenchArticleDescriptions: [String: String] = [
    "le":    "der (bestimmter Artikel, männlich)",
    "la":    "die (bestimmter Artikel, weiblich)",
    "l'":    "der/die (bestimmter Artikel vor Vokal)",
    "l’":    "der/die (bestimmter Artikel vor Vokal)",
    "les":   "die (bestimmter Artikel, Plural)",
    "un":    "ein (unbestimmter Artikel, männlich)",
    "une":   "eine (unbestimmter Artikel, weiblich)",
    "des":   "unbestimmter Artikel im Plural",
    "du":    "Teilungsartikel, männlich",
    "de la": "Teilungsartikel, weiblich",
    "de l'": "Teilungsartikel vor Vokal",
    "de l’": "Teilungsartikel vor Vokal",
    "au":    "zusammengezogen aus à + le",
    "aux":   "zusammengezogen aus à + les"
]

/// Ist der Eintrag ein französischer Artikel? Erwartet den reinen
/// Eintragstext; Groß-/Kleinschreibung und umgebende Leerzeichen sind
/// egal.
func isFrenchArticleEntry(_ text: String) -> Bool {
    frenchArticleDescription(for: text) != nil
}

/// Kanonische deutsche Beschreibung eines französischen Artikels —
/// `nil`, wenn der Text kein Artikel ist.
func frenchArticleDescription(for text: String) -> String? {
    let key = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    return frenchArticleDescriptions[key]
}
