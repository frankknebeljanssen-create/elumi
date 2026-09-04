import Foundation

func frenchHeadGenderOverride(for text: String) -> LexiconNounGender? {
    let bare = strippingLeadingFrenchArticle(from: text)
    guard !bare.isEmpty else { return nil }

    if let exact = frenchNounGenderHeadOverrides[bare] {
        return exact
    }

    return frenchNounGenderHeadOverrides.first { key, _ in
        bare.hasSuffix(key)
    }?.value
}

func germanHeadGenderOverride(for text: String) -> LexiconNounGender? {
    let bare = strippingLeadingGermanArticle(from: text)
    guard !bare.isEmpty else { return nil }

    if let exact = germanNounGenderHeadOverrides[bare] {
        return exact
    }

    return germanNounGenderHeadOverrides.first { key, _ in
        bare.hasSuffix(key)
    }?.value
}

func frenchGenderInfo(for text: String, cardType: CardType) -> LexiconGenderInfo? {
    guard cardType == .words else { return nil }

    if let article = leadingFrenchArticle(in: text) {
        switch article {
        case "le", "un", "du", "au":
            return LexiconGenderInfo(gender: .masculine, article: article, isHeuristic: false)
        case "la", "une", "de la", "a la":
            return LexiconGenderInfo(gender: .feminine, article: article, isHeuristic: false)
        case "les", "des", "aux":
            return LexiconGenderInfo(gender: .plural, article: article, isHeuristic: false)
        default:
            break
        }
    }

    let bare = strippingLeadingFrenchArticle(from: text)
    guard !bare.isEmpty else { return nil }

    // **2026-06-09** — Monatsnamen und Eigennamen stehen artikellos.
    // Muss VOR den Endungs-Heuristiken greifen: „septembre" endet sonst
    // auf eine als feminin gewertete Endung und bekäme „la" davor.
    guard !isArticlelessFrenchNoun(bare) else { return nil }

    if strongFrenchFeminineSuffixes.contains(where: { bare.hasSuffix($0) }) {
        return LexiconGenderInfo(gender: .feminine, article: suggestedFrenchArticle(for: .feminine), isHeuristic: true)
    }

    if strongFrenchMasculineSuffixes.contains(where: { bare.hasSuffix($0) }) {
        return LexiconGenderInfo(gender: .masculine, article: suggestedFrenchArticle(for: .masculine), isHeuristic: true)
    }

    if let headOverride = frenchHeadGenderOverride(for: text) {
        return LexiconGenderInfo(gender: headOverride, article: suggestedFrenchArticle(for: headOverride), isHeuristic: true)
    }

    return nil
}

func germanGenderInfo(for text: String, cardType: CardType) -> LexiconGenderInfo? {
    guard cardType == .words else { return nil }

    if let article = leadingGermanArticle(in: text) {
        switch article {
        case "der", "den", "dem", "des", "einen":
            return LexiconGenderInfo(gender: .masculine, article: article, isHeuristic: false)
        case "die", "eine", "einer":
            return LexiconGenderInfo(gender: .feminine, article: article, isHeuristic: false)
        case "das":
            return LexiconGenderInfo(gender: .neuter, article: article, isHeuristic: false)
        default:
            break
        }
    }

    let bare = strippingLeadingGermanArticle(from: text)
    guard !bare.isEmpty else { return nil }

    if strongGermanFeminineSuffixes.contains(where: { bare.hasSuffix($0) }) {
        return LexiconGenderInfo(gender: .feminine, article: suggestedGermanArticle(for: .feminine), isHeuristic: true)
    }

    if strongGermanNeuterSuffixes.contains(where: { bare.hasSuffix($0) }) {
        return LexiconGenderInfo(gender: .neuter, article: suggestedGermanArticle(for: .neuter), isHeuristic: true)
    }

    if strongGermanMasculineSuffixes.contains(where: { bare.hasSuffix($0) }) {
        return LexiconGenderInfo(gender: .masculine, article: suggestedGermanArticle(for: .masculine), isHeuristic: true)
    }

    if let headOverride = germanHeadGenderOverride(for: text) {
        return LexiconGenderInfo(gender: headOverride, article: suggestedGermanArticle(for: headOverride), isHeuristic: true)
    }

    return nil
}
