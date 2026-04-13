import Foundation

struct VocabularyItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var french: String
    var german: String
    var sourcePhonetic: String? = nil
    var targetPhonetic: String? = nil
    var cardType: CardType
    var level: VocabularyLevel? = nil
    var sourceLanguage: StudyLanguage = .french
    var wordClass: String? = nil

    init(
        id: UUID = UUID(),
        french: String,
        german: String,
        sourcePhonetic: String? = nil,
        targetPhonetic: String? = nil,
        cardType: CardType,
        level: VocabularyLevel? = nil,
        sourceLanguage: StudyLanguage = .french,
        wordClass: String? = nil
    ) {
        self.id = id
        self.french = sourceDisplayText(french, sourceLanguage: sourceLanguage)
        self.german = germanDisplayText(german, cardType: cardType, sourceHint: self.french)
        self.sourcePhonetic = sourcePhonetic
        self.targetPhonetic = targetPhonetic
        self.cardType = cardType
        self.level = level
        self.sourceLanguage = sourceLanguage
        self.wordClass = wordClass
    }

    /// Raw init that skips text processing — for pre-processed data (GPT translations)
    init(
        rawFrench french: String,
        rawGerman german: String,
        cardType: CardType,
        level: VocabularyLevel? = nil,
        sourceLanguage: StudyLanguage = .french,
        wordClass: String? = nil
    ) {
        self.id = UUID()
        self.french = french
        self.german = german
        self.sourcePhonetic = nil
        self.targetPhonetic = nil
        self.cardType = cardType
        self.level = level
        self.sourceLanguage = sourceLanguage
        self.wordClass = wordClass
    }

    init(
        bootstrappedFrench french: String,
        bootstrappedGerman german: String,
        cardType: CardType,
        level: VocabularyLevel? = nil,
        sourceLanguage: StudyLanguage = .french
    ) {
        self.id = UUID()
        self.french = sourceDisplayText(french, sourceLanguage: sourceLanguage)
        self.german = bootstrappedGermanText(german, cardType: cardType, sourceHint: self.french)
        self.sourcePhonetic = nil
        self.targetPhonetic = nil
        self.cardType = cardType
        self.level = level
        self.sourceLanguage = sourceLanguage
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case french
        case german
        case sourcePhonetic
        case targetPhonetic
        case cardType
        case level
        case sourceLanguage
        case wordClass
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        french = try container.decode(String.self, forKey: .french)
        german = try container.decode(String.self, forKey: .german)
        sourcePhonetic = try container.decodeIfPresent(String.self, forKey: .sourcePhonetic)
        targetPhonetic = try container.decodeIfPresent(String.self, forKey: .targetPhonetic)
        cardType = try container.decode(CardType.self, forKey: .cardType)
        level = try container.decodeIfPresent(VocabularyLevel.self, forKey: .level)
        sourceLanguage = try container.decodeIfPresent(StudyLanguage.self, forKey: .sourceLanguage) ?? .french
        wordClass = try container.decodeIfPresent(String.self, forKey: .wordClass)
    }

    /// Resolved word class — uses stored value or falls back to StandardVocabularyLoader lookup
    var resolvedWordClass: String? {
        wordClass ?? StandardVocabularyLoader.wordClass(for: french)
    }

    func card(for direction: Direction) -> FlashCard {
        let studyFrench = frenchStudyCardDisplayText(
            french,
            matchingGerman: german,
            cardType: cardType,
            sourceLanguage: sourceLanguage
        )
        let studyGerman = germanStudyCardDisplayText(
            german,
            matchingFrench: french,
            cardType: cardType
        )
        let synchronizedPair = synchronizedPairTerminalSentencePunctuation(
            source: studyFrench,
            target: studyGerman,
            sourceLanguage: sourceLanguage,
            cardType: cardType
        )

        switch direction {
        case .frenchToGerman:
            return FlashCard(
                prompt: synchronizedPair.source,
                answer: synchronizedPair.target,
                promptLanguageCode: "fr-FR",
                answerLanguageCode: "de-DE",
                category: cardType.categoryName,
                wordClass: resolvedWordClass
            )
        case .germanToFrench:
            return FlashCard(
                prompt: synchronizedPair.target,
                answer: synchronizedPair.source,
                promptLanguageCode: "de-DE",
                answerLanguageCode: "fr-FR",
                category: cardType.categoryName,
                wordClass: resolvedWordClass
            )
        case .englishToGerman:
            return FlashCard(
                prompt: synchronizedPair.source,
                answer: synchronizedPair.target,
                promptLanguageCode: "en-US",
                answerLanguageCode: "de-DE",
                category: cardType.categoryName,
                wordClass: resolvedWordClass
            )
        case .germanToEnglish:
            return FlashCard(
                prompt: synchronizedPair.target,
                answer: synchronizedPair.source,
                promptLanguageCode: "de-DE",
                answerLanguageCode: "en-US",
                category: cardType.categoryName,
                wordClass: resolvedWordClass
            )
        }
    }
}

struct VocabularyList: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var items: [VocabularyItem]
    var isBuiltIn: Bool
    var collectionPreset: ListCollectionPreset
    var isAggregateVocabulary: Bool

    init(
        id: UUID = UUID(),
        name: String,
        items: [VocabularyItem],
        isBuiltIn: Bool = false,
        collectionPreset: ListCollectionPreset = .other,
        isAggregateVocabulary: Bool = false
    ) {
        self.id = id
        self.name = name
        self.items = items
        self.isBuiltIn = isBuiltIn
        self.collectionPreset = collectionPreset
        self.isAggregateVocabulary = isAggregateVocabulary
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case items
        case isBuiltIn
        case collectionPreset
        case isAggregateVocabulary
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        items = try container.decodeIfPresent([VocabularyItem].self, forKey: .items) ?? []
        isBuiltIn = try container.decodeIfPresent(Bool.self, forKey: .isBuiltIn) ?? false
        collectionPreset = try container.decodeIfPresent(ListCollectionPreset.self, forKey: .collectionPreset) ?? .other
        isAggregateVocabulary = try container.decodeIfPresent(Bool.self, forKey: .isAggregateVocabulary) ?? false
    }
}
