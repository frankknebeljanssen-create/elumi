import Foundation

enum ScanEvaluationFixtures {
    private static let textbookFixturePaths = [
        "/Users/frankknebeljanssen/Downloads/IMG_3456.jpg"
    ]

    private static let posterFixturePaths = [
        "/Users/frankknebeljanssen/Downloads/IMG_3250.jpg"
    ]

    private static let textbookNoiseFragments = [
        "fam.",
        "adj. inv.",
        "adj.inv.",
        "H3110",
        "N3 ja",
        "NGme",
        "Unddu"
    ]

    private static let posterScheduleNoiseFragments = [
        "18h00",
        "11h00",
        "11h30",
        "dimanche",
        "offices dominicaux",
        "st louis",
        "en l'ile"
    ]

    static let core: [ScanEvalFixture] = [
        ScanEvalFixture(
            id: "textbook_dialogue_table",
            title: "Lehrbuch-Tabelle mit Lautschrift und Dialogspalte",
            sampleImagePaths: textbookFixturePaths,
            expectedDocumentTypes: [.textbookTable, .vocabularyList],
            expectedMode: .list,
            minimumEntryCount: 6,
            minimumImportableEntryCount: 4,
            requiredCategories: [.phrases],
            requiredSourceFragments: [],
            requiredTargetFragments: [],
            requiredExactSourceEntries: [
                "C'est parti !",
                "Salut !",
                "Tu t'appelles comment ?",
                "Et toi ?",
                "À plus !",
                "Ça va ?",
                "bof",
                "toi",
                "super",
                "Ça sonne !"
            ],
            requiredExactTargetEntries: [
                "Los geht's!",
                "Hallo! auch: Tschüss!",
                "Wie heißt du?",
                "Und du?",
                "Bis später!",
                "Na ja./Es geht so.",
                "du",
                "super, toll",
                "Es klingelt!"
            ],
            forbiddenFragments: textbookNoiseFragments,
            forbiddenExactEntries: []
        ),
        ScanEvalFixture(
            id: "poster_notice_free_text",
            title: "Plakat/Aushang als Freitext",
            sampleImagePaths: posterFixturePaths,
            expectedDocumentTypes: [.poster, .cover, .mixedLayout, .freeText],
            expectedMode: .text,
            minimumEntryCount: 4,
            minimumImportableEntryCount: 2,
            requiredCategories: [.recognizedText, .phrases, .grammar],
            requiredSourceFragments: ["Merci de", "Pas de"],
            requiredTargetFragments: [],
            requiredExactSourceEntries: [],
            requiredExactTargetEntries: [],
            forbiddenFragments: posterScheduleNoiseFragments,
            forbiddenExactEntries: []
        ),
        ScanEvalFixture(
            id: "placeholder_name_template_preservation",
            title: "Platzhalter + Name muss als Template erhalten bleiben",
            sampleImagePaths: textbookFixturePaths,
            expectedDocumentTypes: [.textbookTable, .vocabularyList],
            expectedMode: .list,
            minimumEntryCount: 1,
            minimumImportableEntryCount: 1,
            requiredCategories: [],
            requiredSourceFragments: [],
            requiredTargetFragments: [],
            requiredExactSourceEntries: ["Je m'appelle + Name"],
            requiredExactTargetEntries: ["Ich heiße + Name"],
            forbiddenFragments: ["NGme"],
            forbiddenExactEntries: ["Je m'appelle Marie", "Ich heiße Marie"]
        ),
        ScanEvalFixture(
            id: "punctuation_sync",
            title: "Satzzeichen auf beiden Seiten erhalten",
            sampleImagePaths: textbookFixturePaths,
            expectedDocumentTypes: [.textbookTable, .vocabularyList, .freeText],
            expectedMode: nil,
            minimumEntryCount: 2,
            minimumImportableEntryCount: 2,
            requiredCategories: [],
            requiredSourceFragments: [],
            requiredTargetFragments: [],
            requiredExactSourceEntries: ["Et toi ?", "C'est parti !"],
            requiredExactTargetEntries: ["Und du?", "Los geht's!"],
            forbiddenFragments: ["Unddu", "Losgeht's"],
            forbiddenExactEntries: ["Et toi", "C'est parti", "Und du", "Los geht's"]
        ),
        ScanEvalFixture(
            id: "ocr_confusable_target_cleanup",
            title: "OCR-Konfusionsmuster wie H3110 und N3 ja müssen korrigiert werden",
            sampleImagePaths: textbookFixturePaths,
            expectedDocumentTypes: [.textbookTable, .vocabularyList],
            expectedMode: .list,
            minimumEntryCount: 2,
            minimumImportableEntryCount: 2,
            requiredCategories: [],
            requiredSourceFragments: ["Salut", "bof"],
            requiredTargetFragments: [],
            requiredExactSourceEntries: [],
            requiredExactTargetEntries: ["Hallo! auch: Tschüss!", "Na ja./Es geht so.", "super, toll", "Es klingelt!"],
            forbiddenFragments: ["H3110", "N3 ja", "Es geht mir gut"],
            forbiddenExactEntries: []
        ),
        ScanEvalFixture(
            id: "word_spacing_preservation",
            title: "Wortabstände in Zielphrasen müssen erhalten bleiben",
            sampleImagePaths: textbookFixturePaths,
            expectedDocumentTypes: [.textbookTable, .vocabularyList],
            expectedMode: .list,
            minimumEntryCount: 2,
            minimumImportableEntryCount: 2,
            requiredCategories: [],
            requiredSourceFragments: ["Et toi ?", "bof"],
            requiredTargetFragments: [],
            requiredExactSourceEntries: [],
            requiredExactTargetEntries: ["Und du?", "Na ja"],
            forbiddenFragments: ["Unddu", "Naja"],
            forbiddenExactEntries: []
        ),
        ScanEvalFixture(
            id: "free_text_learning_focus",
            title: "Freitext soll Lerninhalt statt Rohrauschen liefern",
            sampleImagePaths: posterFixturePaths,
            expectedDocumentTypes: [.freeText, .poster, .mixedLayout],
            expectedMode: .text,
            minimumEntryCount: 5,
            minimumImportableEntryCount: 3,
            requiredCategories: [.recognizedText, .verbs, .phrases],
            requiredSourceFragments: [],
            requiredTargetFragments: [],
            requiredExactSourceEntries: [],
            requiredExactTargetEntries: [],
            forbiddenFragments: ["je", "tu", "et", "est"],
            forbiddenExactEntries: []
        ),
        ScanEvalFixture(
            id: "poster_schedule_noise_filter",
            title: "Poster-Zeiten und Gottesdienstplan sollen nicht als Lerninhalt landen",
            sampleImagePaths: posterFixturePaths,
            expectedDocumentTypes: [.poster, .freeText, .mixedLayout],
            expectedMode: .text,
            minimumEntryCount: 3,
            minimumImportableEntryCount: 2,
            requiredCategories: [.recognizedText, .phrases],
            requiredSourceFragments: ["Merci de respecter", "Pas de visite"],
            requiredTargetFragments: [],
            requiredExactSourceEntries: [],
            requiredExactTargetEntries: [],
            forbiddenFragments: posterScheduleNoiseFragments,
            forbiddenExactEntries: []
        ),
        ScanEvalFixture(
            id: "poster_bucket_balance",
            title: "Poster soll Kontext plus Lernkarten liefern, nicht nur Rohtext",
            sampleImagePaths: posterFixturePaths,
            expectedDocumentTypes: [.poster, .freeText, .mixedLayout],
            expectedMode: .text,
            minimumEntryCount: 4,
            minimumImportableEntryCount: 2,
            requiredCategories: [.recognizedText, .phrases, .grammar],
            requiredSourceFragments: ["Merci de", "le silence"],
            requiredTargetFragments: [],
            requiredExactSourceEntries: [],
            requiredExactTargetEntries: [],
            forbiddenFragments: [],
            forbiddenExactEntries: []
        )
    ]

    static func availableCoreFixtures(
        fileManager: FileManager = .default
    ) -> [ScanEvalFixture] {
        core.filter { fixture in
            fixture.sampleImagePaths.contains { fileManager.fileExists(atPath: $0) }
        }
    }

    static func matchingFixtures(
        forImagePath imagePath: String,
        fixtures: [ScanEvalFixture] = core
    ) -> [ScanEvalFixture] {
        let normalizedPath = normalizedPathKey(imagePath)
        let basename = ((imagePath as NSString).lastPathComponent)
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        return fixtures.filter { fixture in
            fixture.sampleImagePaths.contains { samplePath in
                let normalizedSample = normalizedPathKey(samplePath)
                if normalizedSample == normalizedPath {
                    return true
                }

                let sampleBasename = ((samplePath as NSString).lastPathComponent)
                    .folding(options: .diacriticInsensitive, locale: .current)
                    .lowercased()
                return sampleBasename == basename
            }
        }
    }

    private static func normalizedPathKey(_ path: String) -> String {
        path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
    }
}
