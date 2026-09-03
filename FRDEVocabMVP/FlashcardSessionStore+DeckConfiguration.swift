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
        // **V1b Lernjahr-Filter (2026-04-28)** — Defense-in-Depth:
        // Auch wenn die Caller (FlashcardsSetupController über
        // availableStackLists / scopedFlashcardLaunchLists) bereits
        // gefilterte Listen liefern, applizieren wir den Filter hier
        // nochmal als Choke-Point. So kann auch ein neuer Caller, der
        // den Setup-Cascade umgeht, niemals ungefilterte Items in den
        // Builder schicken.
        let lernjahrMax = VocabularyListSelectionResolver.currentLernjahrMax()
        let filteredList = list.map { source in
            VocabularyList(
                id: source.id,
                name: source.name,
                items: VocabularyListSelectionResolver.effectiveItems(
                    for: source,
                    lernjahrMax: lernjahrMax
                ),
                isBuiltIn: source.isBuiltIn,
                collectionPreset: source.collectionPreset,
                isAggregateVocabulary: source.isAggregateVocabulary
            )
        }
        customDeck = FlashcardDeckBuilder.buildDeck(
            from: filteredList,
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
        // **V1b Lernjahr-Filter (2026-04-28)** — siehe Single-List-
        // Overload oben. Defense-in-Depth: Filter auf jede Liste
        // einzeln applizieren, BEVOR der Builder durch die Liste
        // iteriert. Hierarchische Listen werden auf Y_max gesliced;
        // flache Listen unverändert weitergegeben.
        let lernjahrMax = VocabularyListSelectionResolver.currentLernjahrMax()
        let filteredLists = lists.map { source in
            VocabularyList(
                id: source.id,
                name: source.name,
                items: VocabularyListSelectionResolver.effectiveItems(
                    for: source,
                    lernjahrMax: lernjahrMax
                ),
                isBuiltIn: source.isBuiltIn,
                collectionPreset: source.collectionPreset,
                isAggregateVocabulary: source.isAggregateVocabulary
            )
        }
        customDeck = FlashcardDeckBuilder.buildDeck(
            from: filteredLists,
            language: language,
            preferredCardType: preferredCardType,
            maxCardCount: maxCardCount,
            urgency: Self.learningUrgency
        )
        ensureValidSession()
    }

    /// **2026-08-05** — Dringlichkeit einer Vokabel für die Teilmengen-
    /// Auswahl (User-Report: „zwei Wörter aus der Lernliste wurden bei
    /// Karteikarten gar nicht abgefragt"). Kleinerer Wert = kommt
    /// zuerst dran. Greift nur, wenn NICHT der ganze Stapel geübt wird
    /// — bei „alle Karten" ist ohnehin jede Vokabel dabei.
    ///
    /// Reihenfolge bewusst so: Was noch nie abgefragt wurde, hat die
    /// höchste Priorität — genau diese Wörter fielen vorher durchs
    /// Zufalls-Raster und tauchten dadurch nie im Lernstatus auf. Danach
    /// das, was nachweislich wackelt, und zuletzt das, was schon sitzt.
    static func learningUrgency(for item: VocabularyItem) -> Int {
        let key = ItemLearningStatusStore.canonicalKey(
            french: item.french,
            german: item.german,
            cardType: item.cardType
        )
        guard let status = ItemLearningStatusStore.shared.statuses[key] else {
            return 0  // noch nie abgefragt
        }
        switch status.status {
        case .needsWork: return 1
        case .sparse:    return 2
        case .learning:  return 3
        case .strong:    return 4
        }
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
