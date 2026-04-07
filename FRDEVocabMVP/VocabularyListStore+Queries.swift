import Foundation

extension VocabularyListStore {
    func practiceList(with id: UUID?) -> VocabularyList? {
        guard let id else { return practiceLists.first }

        if id == Self.allCustomVocabularyListID {
            return allCustomVocabularyList
        }

        return sortedCustomLists.first(where: { $0.id == id })
    }

    func builtInItems(for level: VocabularyLevel, language: StudyLanguage) -> [VocabularyItem] {
        builtInList.items.filter {
            ($0.level?.rank ?? Int.max) <= level.rank && $0.sourceLanguage == language
        }
    }

    func dictionaryList(
        for learningLevel: DictionaryLearningLevel,
        language: StudyLanguage
    ) -> VocabularyList? {
        makeDictionaryVocabularyList(for: learningLevel, language: language)
    }

    func customList(with id: UUID?) -> VocabularyList? {
        guard let id else { return customLists.first }
        return customLists.first(where: { $0.id == id })
    }

    func suggestedListName(from baseName: String) -> String {
        uniqueListName(from: baseName)
    }

    func cards(for direction: Direction, type: CardType) -> [FlashCard] {
        selectedList.items
            .filter { $0.cardType == type }
            .map { $0.card(for: direction) }
    }
}
