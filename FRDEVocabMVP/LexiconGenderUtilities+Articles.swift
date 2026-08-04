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
///
/// **2026-06-09** — Erkennt auch Ketten aus mehreren Artikeln („le l'",
/// „le la l'"). Solche Einträge entstehen beim Scannen, wenn im
/// Vokabelheft „le/la/l'" in einer Zeile steht und die Trennung
/// misslingt. Der Eintrag ist dann trotzdem ein Artikel-Eintrag und darf
/// weder ein Satzzeichen noch einen weiteren Artikel bekommen.
func isFrenchArticleEntry(_ text: String) -> Bool {
    if frenchArticleDescription(for: text) != nil { return true }
    return articleChainComponents(in: text) != nil
}

/// Zerlegt einen Text in Artikel-Bestandteile — `nil`, sobald ein
/// Bestandteil kein Artikel ist.
func articleChainComponents(in text: String) -> [String]? {
    let parts = text
        .replacingOccurrences(of: "/", with: " ")
        .split(separator: " ")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }
    guard parts.count >= 2 else { return nil }
    guard parts.allSatisfy({ frenchArticleDescriptions[$0] != nil }) else { return nil }
    return parts
}

/// Anzeigetext für einen Artikel-Eintrag. Eine Kette wie „le l'" wird zu
/// „le/la/l'" zusammengefasst — so, wie das Vokabelheft es meint, statt
/// als sinnlose Aneinanderreihung.
func normalizedFrenchArticleDisplay(_ text: String) -> String {
    guard let parts = articleChainComponents(in: text) else { return text }
    return parts.joined(separator: "/")
}

/// Kanonische deutsche Beschreibung eines französischen Artikels —
/// `nil`, wenn der Text kein Artikel ist.
func frenchArticleDescription(for text: String) -> String? {
    let key = text
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()
    return frenchArticleDescriptions[key]
}
