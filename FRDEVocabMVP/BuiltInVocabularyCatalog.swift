import Foundation

enum BuiltInVocabularyCatalog {
    static let builtInVocabularyItems: [VocabularyItem] = StandardVocabularyLoader.vocabularyItems

    static let defaultItems: [VocabularyItem] = builtInVocabularyItems

    static func makeItems(
        _ pairs: [String],
        type: CardType,
        level: VocabularyLevel,
        sourceLanguage: StudyLanguage = .french
    ) -> [VocabularyItem] {
        pairs.compactMap { line in
            let values = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard values.count == 2 else { return nil }
            return VocabularyItem(
                bootstrappedFrench: values[0],
                bootstrappedGerman: values[1],
                cardType: type,
                level: level,
                sourceLanguage: sourceLanguage
            )
        }
    }

    static func makeFlashcardDeckCards(
        idPrefix: String,
        pairs: [String],
        sourceLanguage: StudyLanguage
    ) -> [FlashcardDeckCard] {
        pairs.enumerated().compactMap { index, line in
            let values = line.split(separator: "|", maxSplits: 1).map(String.init)
            guard values.count == 2 else { return nil }
            return FlashcardDeckCard(
                id: "\(idPrefix)-\(String(format: "%03d", index + 1))",
                french: values[0],
                german: values[1],
                sourceLanguage: sourceLanguage
            )
        }
    }

    static func normalizedLexiconWords(from lines: [String]) -> [String] {
        lines
            .flatMap { line in
                line
                    .lowercased()
                    .folding(options: .diacriticInsensitive, locale: .current)
                    .components(separatedBy: CharacterSet.alphanumerics.inverted)
            }
            .filter { !$0.isEmpty }
    }
}
