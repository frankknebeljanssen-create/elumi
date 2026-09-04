import Foundation
import SwiftUI

let appDirectionKey = "FRDEVocabMVP.flashcardDirection.v1"
let dictionaryVocabularyListID = UUID(uuidString: "F6D43F89-8E03-4D56-86F9-08B8334A06C1")!

struct SampleVocabularyListSeed {
    let name: String
    let collectionPreset: ListCollectionPreset
    let items: [VocabularyItem]
}

private func makeSampleVocabularyItem(french: String, german: String) -> VocabularyItem {
    VocabularyItem(
        french: french,
        german: german,
        cardType: .words,
        level: .intermediate,
        sourceLanguage: .french
    )
}

let sampleVocabularyListSeeds: [SampleVocabularyListSeed] = [
    SampleVocabularyListSeed(
        name: "Buch Unite 1",
        collectionPreset: .schoolbook,
        items: [
            makeSampleVocabularyItem(french: "marché", german: "markt"),
            makeSampleVocabularyItem(french: "pharmacie", german: "apotheke"),
            makeSampleVocabularyItem(french: "hôpital", german: "krankenhaus"),
            makeSampleVocabularyItem(french: "aéroport", german: "flughafen"),
            makeSampleVocabularyItem(french: "billet", german: "ticket"),
            makeSampleVocabularyItem(french: "valise", german: "koffer"),
            makeSampleVocabularyItem(french: "voyage", german: "reise"),
            makeSampleVocabularyItem(french: "vacances", german: "urlaub"),
            makeSampleVocabularyItem(french: "question", german: "frage"),
            makeSampleVocabularyItem(french: "réponse", german: "antwort"),
            makeSampleVocabularyItem(french: "bibliothèque", german: "bibliothek"),
            makeSampleVocabularyItem(french: "boulangerie", german: "bäckerei"),
            makeSampleVocabularyItem(french: "quartier", german: "viertel"),
            makeSampleVocabularyItem(french: "carrefour", german: "kreuzung"),
            makeSampleVocabularyItem(french: "ordonnance", german: "rezept")
        ]
    ),
    SampleVocabularyListSeed(
        name: "Vokabelheft April",
        collectionPreset: .vocabularyNotebook,
        items: [
            makeSampleVocabularyItem(french: "médicament", german: "medikament"),
            makeSampleVocabularyItem(french: "facture", german: "rechnung"),
            makeSampleVocabularyItem(french: "colis", german: "paket"),
            makeSampleVocabularyItem(french: "abonnement", german: "abonnement"),
            makeSampleVocabularyItem(french: "chargeur", german: "ladegerät"),
            makeSampleVocabularyItem(french: "batterie", german: "batterie"),
            makeSampleVocabularyItem(french: "écran", german: "bildschirm"),
            makeSampleVocabularyItem(french: "clavier", german: "tastatur"),
            makeSampleVocabularyItem(french: "imprimante", german: "drucker"),
            makeSampleVocabularyItem(french: "randonnée", german: "wanderung"),
            makeSampleVocabularyItem(french: "cascade", german: "wasserfall"),
            makeSampleVocabularyItem(french: "falaise", german: "klippe"),
            makeSampleVocabularyItem(french: "frontière", german: "grenze"),
            makeSampleVocabularyItem(french: "itinéraire", german: "route"),
            makeSampleVocabularyItem(french: "bagage", german: "gepäck"),
            makeSampleVocabularyItem(french: "train", german: "zug"),
            makeSampleVocabularyItem(french: "métro", german: "u bahn"),
            makeSampleVocabularyItem(french: "plage", german: "strand"),
            makeSampleVocabularyItem(french: "montagne", german: "berg"),
            makeSampleVocabularyItem(french: "forêt", german: "wald"),
            makeSampleVocabularyItem(french: "rivière", german: "fluss"),
            makeSampleVocabularyItem(french: "journal", german: "zeitung"),
            makeSampleVocabularyItem(french: "histoire", german: "geschichte"),
            makeSampleVocabularyItem(french: "bureau", german: "büro"),
            makeSampleVocabularyItem(french: "ordinateur", german: "computer"),
            makeSampleVocabularyItem(french: "téléphone", german: "telefon"),
            makeSampleVocabularyItem(french: "réunion", german: "meeting"),
            makeSampleVocabularyItem(french: "voisin", german: "nachbar"),
            makeSampleVocabularyItem(french: "cuisine", german: "küche"),
            makeSampleVocabularyItem(french: "météo", german: "wetter")
        ]
    )
]

private struct DictionaryVocabularyListCacheKey: Hashable {
    let learningLevel: DictionaryLearningLevel
    let language: StudyLanguage
}

private enum DictionaryVocabularyListCache {
    private static let lock = NSLock()
    private static var storage: [DictionaryVocabularyListCacheKey: VocabularyList?] = [:]

    static func list(
        for learningLevel: DictionaryLearningLevel,
        language: StudyLanguage
    ) -> VocabularyList? {
        let key = DictionaryVocabularyListCacheKey(
            learningLevel: learningLevel,
            language: language
        )

        lock.lock()
        if let cached = storage[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let items = DataStore.dictionaryItems(for: learningLevel, language: language)
        let list = items.isEmpty ? nil : VocabularyList(
            id: dictionaryVocabularyListID,
            name: "Wörterbuch",
            items: items,
            isBuiltIn: false,
            collectionPreset: .other
        )

        lock.lock()
        storage[key] = list
        lock.unlock()
        return list
    }
}

func makeDictionaryVocabularyList(
    for learningLevel: DictionaryLearningLevel,
    language: StudyLanguage
) -> VocabularyList? {
    DictionaryVocabularyListCache.list(for: learningLevel, language: language)
}
