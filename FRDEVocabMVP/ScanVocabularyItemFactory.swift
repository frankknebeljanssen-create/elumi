import Foundation

struct ScanVocabularyItemFactoryDependencies {
    let extractedTermComponents: (String) -> (display: String, phonetic: String?)
    let normalizedSourceImportTerm: (String) -> String
    let canonicalizedGermanTargetIfNeeded: (String, String, CardType, StudyLanguage) -> String
    let synchronizedPairTerminalSentencePunctuation: (String, String, StudyLanguage, CardType) -> (source: String, target: String)
}

struct ScanVocabularyItemFactory {
    let dependencies: ScanVocabularyItemFactoryDependencies

    func makeVocabularyItem(
        french: String,
        german: String,
        cardType: CardType,
        sourceLanguage: StudyLanguage,
        wordClass: String? = nil
    ) -> VocabularyItem? {
        let parsedFrench = dependencies.extractedTermComponents(french)
        let parsedGerman = dependencies.extractedTermComponents(german)
        let normalizedFrench = dependencies.normalizedSourceImportTerm(parsedFrench.display)
        let normalizedGerman = dependencies.canonicalizedGermanTargetIfNeeded(
            parsedGerman.display,
            normalizedFrench,
            cardType,
            sourceLanguage
        )

        guard !normalizedFrench.isEmpty, !normalizedGerman.isEmpty else { return nil }

        let synchronizedPair = dependencies.synchronizedPairTerminalSentencePunctuation(
            normalizedFrench,
            normalizedGerman,
            sourceLanguage,
            cardType
        )

        return VocabularyItem(
            french: synchronizedPair.source,
            german: synchronizedPair.target,
            sourcePhonetic: parsedFrench.phonetic,
            targetPhonetic: parsedGerman.phonetic,
            cardType: cardType,
            sourceLanguage: sourceLanguage,
            wordClass: wordClass
        )
    }
}
