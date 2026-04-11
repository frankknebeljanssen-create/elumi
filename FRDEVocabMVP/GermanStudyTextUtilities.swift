import Foundation

func shouldDisplayStudyArticles(
    french: String,
    german: String,
    cardType: CardType
) -> Bool {
    guard cardType == .words else { return false }

    // Non-nouns (verbs, adjectives, adverbs) never get articles
    let strippedFrench = strippingLeadingFrenchArticle(from: french)
    if StandardVocabularyLoader.isNonNoun(strippedFrench) { return false }

    let frenchWordCount = normalizedLookupWords(strippedFrench).count
    let germanWordCount = normalizedLookupWords(strippingLeadingGermanArticle(from: german)).count
    guard frenchWordCount == 1, germanWordCount == 1 else { return false }

    let normalizedGerman = normalizedLookupText(strippingLeadingGermanArticle(from: german))
    let hasGermanNounEvidence =
        startsWithGermanArticle(german) ||
        germanGenderInfo(for: german, cardType: cardType) != nil ||
        (!normalizedGerman.isEmpty && DataStore.likelyGermanNounSet.contains(normalizedGerman))

    let hasFrenchNounEvidence =
        leadingFrenchArticle(in: french) != nil ||
        hasFrenchNounHint(french, cardType: cardType)

    return hasFrenchNounEvidence || hasGermanNounEvidence
}

func exactKnowledgePoolGenderInfo(
    french: String,
    german: String,
    cardType: CardType
) -> (french: LexiconGenderInfo?, german: LexiconGenderInfo?)? {
    let sourceKey = normalizedLookupText(strippingLeadingFrenchArticle(from: french))
    let targetKey = normalizedLookupText(strippingLeadingGermanArticle(from: german))
    guard !sourceKey.isEmpty, !targetKey.isEmpty else { return nil }

    if let record = OfflineFrenchGermanKnowledgePool.translatedRecords.first(where: {
        $0.cardType == cardType &&
        normalizedLookupText(strippingLeadingFrenchArticle(from: $0.sourceTerm)) == sourceKey &&
        normalizedLookupText(strippingLeadingGermanArticle(from: $0.targetTerm)) == targetKey
    }) {
        return (
            french: exactFrenchGenderInfo(gender: record.sourceGender, article: record.sourceArticle),
            german: exactGermanGenderInfo(gender: record.targetGender, article: record.targetLeadingArticle)
        )
    }

    return SupplementalFreeDictLexicon.exactGenderInfo(sourceTerm: french, targetTerm: german)
}

func frenchStudyCardDisplayText(
    _ text: String,
    matchingGerman german: String,
    cardType: CardType,
    sourceLanguage: StudyLanguage
) -> String {
    let displayed = sourceDisplayText(text, sourceLanguage: sourceLanguage)
    guard sourceLanguage == .french else { return displayed }
    // Non-nouns never get articles
    if StandardVocabularyLoader.isNonNoun(displayed) { return displayed }
    guard shouldDisplayStudyArticles(french: displayed, german: german, cardType: cardType) else { return displayed }
    let exactGender = exactKnowledgePoolGenderInfo(french: displayed, german: german, cardType: cardType)?.french
    guard leadingFrenchArticle(in: displayed) == nil,
          let article = preferredLexiconGenderInfo(
            exactGender,
            frenchGenderInfo(for: displayed, cardType: cardType)
          )?.article,
          !article.isEmpty else {
        return displayed
    }

    return "\(article) \(displayed)"
}

func germanStudyCardDisplayText(
    _ text: String,
    matchingFrench french: String,
    cardType: CardType
) -> String {
    let displayed = germanDisplayText(text, cardType: cardType, sourceHint: french)
    guard shouldDisplayStudyArticles(french: french, german: displayed, cardType: cardType) else { return displayed }
    let exactGender = exactKnowledgePoolGenderInfo(french: french, german: displayed, cardType: cardType)?.german
    guard leadingGermanArticle(in: displayed) == nil,
          let article = preferredLexiconGenderInfo(
            exactGender,
            germanGenderInfo(for: displayed, cardType: cardType)
          )?.article,
          !article.isEmpty else {
        return displayed
    }

    return "\(article) \(displayed)"
}

func listCollectionSummary(for list: VocabularyList) -> String {
    if list.id == dictionaryVocabularyListID {
        return "Wörterbuch"
    }

    if list.isBuiltIn {
        switch list.collectionPreset {
        case .standardLevel: return "Wortschatz nach Niveau"
        case .standardTopic: return "Wortschatz nach Thema"
        default: return "Standardpaket"
        }
    }

    if list.isAggregateVocabulary {
        return "Alle eigenen Listen"
    }

    return list.collectionPreset.displayPath
}

func countLabel(_ count: Int, singular: String, plural: String) -> String {
    "\(count) \(count == 1 ? singular : plural)"
}

func flashcardListDisplayName(_ list: VocabularyList) -> String {
    if list.id == dictionaryVocabularyListID {
        return "Wörterbuch"
    }

    if list.isAggregateVocabulary {
        return list.isBuiltIn ? "Komplettes Wörterbuch" : "Eigener Wortschatz"
    }

    return list.name
}
