import Foundation

enum FlashcardDeckBuilder {
    static func buildDeck(
        from list: VocabularyList?,
        preferredCardType: CardType?
    ) -> FlashcardDeck? {
        guard let list else { return nil }

        let filteredItems = list.items.filter { item in
            guard let preferredCardType else { return true }
            return item.cardType == preferredCardType
        }

        let sourceLanguage = filteredItems.first?.sourceLanguage ?? list.items.first?.sourceLanguage ?? .french
        return FlashcardDeck(
            id: "custom-\(list.id.uuidString)",
            name: list.name,
            sourceLanguage: sourceLanguage,
            cards: filteredItems.map { item in
                FlashcardDeckCard(
                    id: item.id.uuidString,
                    french: item.french,
                    german: item.german,
                    sourceLanguage: item.sourceLanguage,
                    cardType: item.cardType
                )
            }
        )
    }

    static func buildDeck(
        from lists: [VocabularyList],
        language: StudyLanguage,
        preferredCardType: CardType?,
        maxCardCount: Int? = nil
    ) -> FlashcardDeck? {
        let selectedItems: [VocabularyItem]
        if let maxCardCount, maxCardCount > 0 {
            selectedItems = sampledVocabularyItems(
                from: lists,
                language: language,
                preferredCardType: preferredCardType,
                maxCardCount: maxCardCount
            )
        } else {
            selectedItems = filteredVocabularyItems(
                from: lists,
                language: language,
                preferredCardType: preferredCardType
            )
        }

        guard !selectedItems.isEmpty else { return nil }

        let limitedCards = selectedItems.map { item in
            FlashcardDeckCard(
                id: item.id.uuidString,
                french: item.french,
                german: item.german,
                sourceLanguage: item.sourceLanguage,
                cardType: item.cardType
            )
        }

        let deckName = lists.count == 1 ? lists[0].name : "Mein Stapel"
        let typeSuffix = preferredCardType?.rawValue ?? "mixed"
        let countSuffix = maxCardCount.map(String.init) ?? "all"
        let deckID = "custom-stack-\(language.shortCode.lowercased())-\(typeSuffix)-\(countSuffix)-" + lists.map { $0.id.uuidString }.sorted().joined(separator: "-")

        return FlashcardDeck(
            id: deckID,
            name: deckName,
            sourceLanguage: language,
            cards: limitedCards
        )
    }

    private static func matchingVocabularyItem(
        _ item: VocabularyItem,
        language: StudyLanguage,
        preferredCardType: CardType?
    ) -> VocabularyItem? {
        guard item.sourceLanguage == language else { return nil }
        if let preferredCardType, item.cardType != preferredCardType {
            return nil
        }
        return item
    }

    private static func filteredVocabularyItems(
        from lists: [VocabularyList],
        language: StudyLanguage,
        preferredCardType: CardType?
    ) -> [VocabularyItem] {
        lists.flatMap { list in
            list.items.compactMap { item in
                matchingVocabularyItem(item, language: language, preferredCardType: preferredCardType)
            }
        }
    }

    private static func sampledVocabularyItems(
        from lists: [VocabularyList],
        language: StudyLanguage,
        preferredCardType: CardType?,
        maxCardCount: Int
    ) -> [VocabularyItem] {
        guard maxCardCount > 0 else { return [] }

        var sample: [VocabularyItem] = []
        sample.reserveCapacity(maxCardCount)
        var seenCount = 0

        for list in lists {
            for item in list.items {
                guard let matchingItem = matchingVocabularyItem(
                    item,
                    language: language,
                    preferredCardType: preferredCardType
                ) else { continue }

                seenCount += 1
                if sample.count < maxCardCount {
                    sample.append(matchingItem)
                    continue
                }

                let replacementIndex = Int.random(in: 0..<seenCount)
                if replacementIndex < maxCardCount {
                    sample[replacementIndex] = matchingItem
                }
            }
        }

        return sample
    }
}
