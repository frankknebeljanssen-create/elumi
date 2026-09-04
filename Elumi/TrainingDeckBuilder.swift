import Foundation

enum TrainingDeckBuilder {
    static func buildDeck(from items: [VocabularyItem]) -> [VocabularyItem] {
        items.shuffled()
    }

    static func shuffledRound(
        from preparedItems: [VocabularyItem],
        avoiding previousItem: VocabularyItem?
    ) -> [VocabularyItem] {
        var round = preparedItems.shuffled()
        guard let previousItem, round.count > 1 else { return round }

        if let firstCard = round.first,
           firstCard.id == previousItem.id,
           let alternativeIndex = round.firstIndex(where: { $0.id != previousItem.id }) {
            round.swapAt(0, alternativeIndex)
        }

        return round
    }
}
