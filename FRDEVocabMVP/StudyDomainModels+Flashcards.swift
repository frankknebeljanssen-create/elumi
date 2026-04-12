import Foundation

struct FlashcardDeckCard: Identifiable, Codable, Equatable {
    let id: String
    let french: String
    let german: String
    let sourceLanguage: StudyLanguage

    init(id: String, french: String, german: String, sourceLanguage: StudyLanguage) {
        self.id = id
        self.french = french
        self.german = german
        self.sourceLanguage = sourceLanguage
    }

    func card(for direction: Direction) -> FlashCard {
        var displayFrench = french
        // Add French article only for nouns (1-2 words), not for verbs/adjectives/adverbs
        let trimmedFrench = french.trimmingCharacters(in: .whitespacesAndNewlines)
        let frenchWords = trimmedFrench.split(separator: " ")
        let wordCount = frenchWords.count
        let isNonNoun = StandardVocabularyLoader.isNonNoun(trimmedFrench)

        if sourceLanguage == .french,
           wordCount <= 2,
           !isNonNoun,
           !TrainingSessionController.hasFrenchArticle(displayFrench) {
            let article = TrainingSessionController.determineFrenchArticle(
                VocabularyItem(rawFrench: french, rawGerman: german, cardType: .words, sourceLanguage: sourceLanguage)
            )
            if !article.isEmpty {
                displayFrench = article.hasSuffix("'") ? "\(article)\(french)" : "\(article) \(french)"
            }
        }

        let studyFrench = frenchStudyCardDisplayText(
            displayFrench,
            matchingGerman: german,
            cardType: .words,
            sourceLanguage: sourceLanguage
        )
        let studyGerman = germanStudyCardDisplayText(
            german,
            matchingFrench: french,
            cardType: .words
        )
        let synchronizedPair = synchronizedPairTerminalSentencePunctuation(
            source: studyFrench,
            target: studyGerman,
            sourceLanguage: sourceLanguage,
            cardType: .words
        )

        switch direction {
        case .frenchToGerman:
            return FlashCard(
                prompt: synchronizedPair.source,
                answer: synchronizedPair.target,
                promptLanguageCode: "fr-FR",
                answerLanguageCode: "de-DE",
                category: "Karteikarte",
                wordClass: nil
            )
        case .germanToFrench:
            return FlashCard(
                prompt: synchronizedPair.target,
                answer: synchronizedPair.source,
                promptLanguageCode: "de-DE",
                answerLanguageCode: "fr-FR",
                category: "Karteikarte",
                wordClass: nil
            )
        case .englishToGerman:
            return FlashCard(
                prompt: synchronizedPair.source,
                answer: synchronizedPair.target,
                promptLanguageCode: "en-US",
                answerLanguageCode: "de-DE",
                category: "Karteikarte",
                wordClass: nil
            )
        case .germanToEnglish:
            return FlashCard(
                prompt: synchronizedPair.target,
                answer: synchronizedPair.source,
                promptLanguageCode: "de-DE",
                answerLanguageCode: "en-US",
                category: "Karteikarte",
                wordClass: nil
            )
        }
    }
}

struct FlashcardDeck: Identifiable, Equatable {
    let id: String
    let name: String
    let sourceLanguage: StudyLanguage
    let cards: [FlashcardDeckCard]
}

enum MasteryLevel: String, Codable {
    case open
    case almostMastered
    case mastered

    var label: String {
        switch self {
        case .open: return "Offen"
        case .almostMastered: return "Fast sicher"
        case .mastered: return "Sicher"
        }
    }

    var color: String {
        switch self {
        case .open: return "red"
        case .almostMastered: return "yellow"
        case .mastered: return "green"
        }
    }
}

struct CardMastery: Codable, Equatable {
    var consecutiveCorrect: Int = 0

    var level: MasteryLevel {
        if consecutiveCorrect >= 2 { return .mastered }
        if consecutiveCorrect == 1 { return .almostMastered }
        return .open
    }

    mutating func markCorrect() {
        consecutiveCorrect += 1
    }

    mutating func markWrong() {
        consecutiveCorrect = 0
    }
}

struct FlashcardSessionState: Codable, Equatable {
    var deckID: String
    var direction: Direction
    var remainingCardIDs: [String]
    var currentCardID: String?
    var correctCount: Int
    var wrongCount: Int
    var isCompleted: Bool
    var cardMastery: [String: CardMastery] = [:]

    var masteredCardCount: Int {
        cardMastery.values.filter { $0.level == .mastered }.count
    }

    var almostMasteredCardCount: Int {
        cardMastery.values.filter { $0.level == .almostMastered }.count
    }

    var openCardCount: Int {
        let totalTracked = cardMastery.count
        let allCardCount = remainingCardIDs.count + masteredCardCount
        return allCardCount - masteredCardCount - almostMasteredCardCount
    }
}
