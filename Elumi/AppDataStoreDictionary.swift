import Foundation

enum DataStoreDictionarySupport {
    static func dictionaryItems(
        for learningLevel: DictionaryLearningLevel,
        language: StudyLanguage
    ) -> [VocabularyItem] {
        guard language == .french else { return [] }

        return dictionaryPreviewItems.filter { item in
            guard item.sourceLanguage == language else { return false }
            let itemLevel = item.level ?? .advanced
            return learningLevel.matches(itemLevel)
        }
    }

    static func prewarmDictionaryPreviewItems() {
        _ = dictionaryPreviewItems.count
    }

    static let dictionaryPreviewItems: [VocabularyItem] = makeDictionaryPreviewItems()

    private static let builtInLevelLookup: [String: VocabularyLevel] = {
        Dictionary(uniqueKeysWithValues: BuiltInVocabularyCatalog.builtInVocabularyItems.compactMap { item in
            guard let level = item.level else { return nil }
            let key = [
                normalizedLookupText(item.french),
                normalizedLookupText(item.german),
                item.cardType.rawValue
            ].joined(separator: "|")
            return key.isEmpty ? nil : (key, level)
        })
    }()

    private static let builtInSourceLevelLookup: [String: VocabularyLevel] = {
        var lookup: [String: VocabularyLevel] = [:]

        for item in BuiltInVocabularyCatalog.builtInVocabularyItems {
            guard let level = item.level else { continue }
            let key = [
                normalizedLookupText(item.french),
                item.cardType.rawValue
            ].joined(separator: "|")

            guard !key.isEmpty else { continue }

            if let existing = lookup[key] {
                if level.rank < existing.rank {
                    lookup[key] = level
                }
            } else {
                lookup[key] = level
            }
        }

        return lookup
    }()

    private static func makeDictionaryPreviewItems() -> [VocabularyItem] {
        let entries = DataStoreLexiconSupport.previewLexiconEntries(with: [], supplementLimit: 2400)
        var seen = Set<String>()
        var items: [VocabularyItem] = []

        for entry in entries {
            guard entry.sourceLanguage == .french else { continue }

            let cardType = resolvedLexiconCardType(for: entry)
            let source = sourceDisplayText(entry.sourceTerm, sourceLanguage: .french)
            let target = germanDisplayText(entry.targetTerm, cardType: cardType, sourceHint: source)

            guard !source.isEmpty, !target.isEmpty else { continue }

            let key = [
                normalizedLookupText(source),
                normalizedLookupText(target),
                cardType.rawValue
            ].joined(separator: "|")

            guard !key.isEmpty, seen.insert(key).inserted else { continue }

            items.append(
                VocabularyItem(
                    bootstrappedFrench: source,
                    bootstrappedGerman: target,
                    cardType: cardType,
                    level: inferredDictionaryLevel(
                        source: source,
                        target: target,
                        cardType: cardType
                    ),
                    sourceLanguage: .french
                )
            )
        }

        return items
    }

    private static func inferredDictionaryLevel(
        source: String,
        target: String,
        cardType: CardType
    ) -> VocabularyLevel {
        let exactKey = [
            normalizedLookupText(source),
            normalizedLookupText(target),
            cardType.rawValue
        ].joined(separator: "|")

        if let exactLevel = builtInLevelLookup[exactKey] {
            return exactLevel
        }

        let sourceKey = [
            normalizedLookupText(source),
            cardType.rawValue
        ].joined(separator: "|")

        if let sourceLevel = builtInSourceLevelLookup[sourceKey] {
            return sourceLevel
        }

        let sourceWords = cleanedQuizDisplayText(source).split(whereSeparator: \.isWhitespace).count
        let targetWords = cleanedQuizDisplayText(target).split(whereSeparator: \.isWhitespace).count
        let maxWords = max(sourceWords, targetWords)
        let maxCharacters = max(cleanedQuizDisplayText(source).count, cleanedQuizDisplayText(target).count)

        switch cardType {
        case .words:
            if maxWords <= 1 && maxCharacters <= 7 {
                return .beginner
            }
            if maxWords <= 2 && maxCharacters <= 14 {
                return .intermediate
            }
            return .advanced
        case .phrases:
            if maxWords <= 3 && maxCharacters <= 24 {
                return .beginner
            }
            if maxWords <= 6 && maxCharacters <= 48 {
                return .intermediate
            }
            return .advanced
        }
    }
}
