import Foundation

struct DataStore {
    static let flashcardDecks: [FlashcardDeck] = BuiltInVocabularyCatalog.flashcardDecks
    static let builtInVocabularyItems: [VocabularyItem] = BuiltInVocabularyCatalog.builtInVocabularyItems
    static let defaultItems: [VocabularyItem] = BuiltInVocabularyCatalog.defaultItems

    static var ocrCustomWords: [String] {
        DataStoreLexiconWordSupport.ocrCustomWords
    }

    static var germanLexiconWordSet: Set<String> {
        DataStoreLexiconWordSupport.germanLexiconWordSet
    }

    static var likelyGermanNounSet: Set<String> {
        DataStoreLexiconWordSupport.likelyGermanNounSet
    }

    static var internalLexiconEntries: [LexiconEntry] {
        DataStoreLexiconSupport.internalLexiconEntries
    }

    static var localTranslationLookup: [StudyLanguage: [String: [String]]] {
        DataStoreTranslationSupport.localTranslationLookup
    }

    static func prewarmBuiltInLaunchData() {
        _ = builtInVocabularyItems.count
    }

    static func prewarmFlashcardLaunchData() {
        _ = flashcardDecks.count
    }

    static func prewarmLexiconLaunchData() {
        DataStoreDictionarySupport.prewarmDictionaryPreviewItems()
        DataStoreLexiconSupport.prewarmCuratedLexiconEntries()
        _ = DataStoreTranslationSupport.localTranslationLookup[.french]?.count ?? 0
        _ = DataStoreLexiconWordSupport.ocrCustomWords.count
    }

    static func lexiconWordSet(for language: StudyLanguage) -> Set<String> {
        DataStoreLexiconWordSupport.lexiconWordSet(for: language)
    }

    static func cachedCanonicalSourceTerm(for lookupKey: String, sourceLanguage: StudyLanguage) -> String? {
        DataStoreTranslationSupport.cachedCanonicalSourceTerm(for: lookupKey, sourceLanguage: sourceLanguage)
    }

    static func bestLexiconTranslation(for sourceTerm: String, sourceLanguage: StudyLanguage) -> String? {
        DataStoreTranslationSupport.bestLexiconTranslation(for: sourceTerm, sourceLanguage: sourceLanguage)
    }

    static func cachedApproximateTranslationSuggestions(
        for lookupKey: String,
        sourceLanguage: StudyLanguage
    ) -> (lookupKey: String, suggestions: [String], distance: Double)? {
        DataStoreTranslationSupport.cachedApproximateTranslationSuggestions(
            for: lookupKey,
            sourceLanguage: sourceLanguage
        )
    }

    static func mergedLexiconEntries(with customItems: [VocabularyItem]) -> [LexiconEntry] {
        DataStoreLexiconSupport.mergedLexiconEntries(with: customItems)
    }

    static func previewLexiconEntries(with customItems: [VocabularyItem], supplementLimit: Int = 2400) -> [LexiconEntry] {
        DataStoreLexiconSupport.previewLexiconEntries(with: customItems, supplementLimit: supplementLimit)
    }

    static func searchLexiconEntries(
        query: String,
        curatedEntries: [LexiconEntry],
        supplementLimit: Int = 80
    ) -> [LexiconEntry] {
        DataStoreLexiconSupport.searchLexiconEntries(
            query: query,
            curatedEntries: curatedEntries,
            supplementLimit: supplementLimit
        )
    }

    static func curatedLexiconEntries(with customItems: [VocabularyItem]) -> [LexiconEntry] {
        DataStoreLexiconSupport.curatedLexiconEntries(with: customItems)
    }

    static func dictionaryItems(
        for learningLevel: DictionaryLearningLevel,
        language: StudyLanguage
    ) -> [VocabularyItem] {
        DataStoreDictionarySupport.dictionaryItems(for: learningLevel, language: language)
    }
}
