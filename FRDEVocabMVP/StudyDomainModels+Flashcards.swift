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
        let studyFrench = frenchStudyCardDisplayText(
            french,
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
                category: "Karteikarte"
            )
        case .germanToFrench:
            return FlashCard(
                prompt: synchronizedPair.target,
                answer: synchronizedPair.source,
                promptLanguageCode: "de-DE",
                answerLanguageCode: "fr-FR",
                category: "Karteikarte"
            )
        case .englishToGerman:
            return FlashCard(
                prompt: synchronizedPair.source,
                answer: synchronizedPair.target,
                promptLanguageCode: "en-US",
                answerLanguageCode: "de-DE",
                category: "Karteikarte"
            )
        case .germanToEnglish:
            return FlashCard(
                prompt: synchronizedPair.target,
                answer: synchronizedPair.source,
                promptLanguageCode: "de-DE",
                answerLanguageCode: "en-US",
                category: "Karteikarte"
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

struct FlashcardSessionState: Codable, Equatable {
    var deckID: String
    var direction: Direction
    var remainingCardIDs: [String]
    var currentCardID: String?
    var correctCount: Int
    var wrongCount: Int
    var isCompleted: Bool
}
