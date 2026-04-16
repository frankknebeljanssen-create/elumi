import Foundation

extension FlashcardSessionStore {
    var decks: [FlashcardDeck] {
        if let customDeck {
            return [customDeck] + DataStore.flashcardDecks
        }
        return DataStore.flashcardDecks
    }

    var selectedDeck: FlashcardDeck {
        decks.first(where: { $0.id == selectedDeckID }) ?? decks[0]
    }

    var availableDirections: [Direction] {
        Direction.directions(for: selectedDeck.sourceLanguage)
    }

    var totalCount: Int {
        selectedDeck.cards.count
    }

    var masteredCount: Int {
        session?.masteredCardCount(threshold: masteryThreshold) ?? 0
    }

    var almostMasteredCount: Int {
        session?.almostMasteredCardCount(threshold: masteryThreshold) ?? 0
    }

    var openCount: Int {
        totalCount - masteredCount - almostMasteredCount
    }

    /// Unique Karten im Stapel, die mind. 1× falsch beantwortet wurden —
    /// für die rote Markierung im Fortschrittsbalken.
    var wrongAnsweredCardCount: Int {
        session?.wrongAnsweredCardCount(threshold: masteryThreshold) ?? 0
    }

    var remainingCount: Int {
        session?.remainingCardIDs.count ?? totalCount
    }

    var wrongCount: Int {
        session?.wrongCount ?? 0
    }

    var hasActiveSession: Bool {
        guard let session else { return false }
        return session.deckID == selectedDeck.id
            && session.direction == selectedDirection
            && !session.isCompleted
            && !session.remainingCardIDs.isEmpty
    }

    var currentCard: FlashcardDeckCard? {
        guard let session, let currentCardID = session.currentCardID else { return nil }
        return selectedDeck.cards.first(where: { $0.id == currentCardID })
    }

    func configureCustomDeck(from list: VocabularyList?, preferredCardType: CardType?) {
        customDeck = FlashcardDeckBuilder.buildDeck(
            from: list,
            preferredCardType: preferredCardType
        )
        ensureValidSession()
    }

    func configureCustomDeck(
        from lists: [VocabularyList],
        language: StudyLanguage,
        preferredCardType: CardType?,
        maxCardCount: Int? = nil
    ) {
        customDeck = FlashcardDeckBuilder.buildDeck(
            from: lists,
            language: language,
            preferredCardType: preferredCardType,
            maxCardCount: maxCardCount
        )
        ensureValidSession()
    }

    func clearTransientCustomDeckState() {
        let defaultDeckID = DataStore.flashcardDecks.first?.id ?? "flashcards-1"

        if let session, isTransientCustomDeckID(session.deckID) {
            self.session = nil
        }

        customDeck = nil

        if isTransientCustomDeckID(selectedDeckID) {
            selectedDeckID = defaultDeckID
        }

        ensureValidSession()
    }
}
