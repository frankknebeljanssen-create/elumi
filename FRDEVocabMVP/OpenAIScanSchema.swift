import Foundation

struct OpenAIResponsesEnvelope: Decodable {
    let output: [OutputItem]

    var firstOutputText: String? {
        output
            .filter { $0.type == "message" }
            .flatMap(\.content)
            .first(where: { $0.type == "output_text" })?
            .text
    }

    struct OutputItem: Decodable {
        let type: String
        let content: [ContentItem]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            content = try container.decodeIfPresent([ContentItem].self, forKey: .content) ?? []
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case content
        }
    }

    struct ContentItem: Decodable {
        let type: String
        let text: String?
    }
}

struct OpenAIScanSchemaResponse: Decodable {
    let documentType: ScanDocumentType
    let mode: ScanMode
    let sourceLanguage: StudyLanguage
    let entries: [Entry]
    let warnings: [String]
    let summary: String
    let importMessage: String
    let confidence: Double
    let usedColumnPairing: Bool
    let recognizedLineCount: Int

    struct Entry: Decodable {
        let source: String
        let target: String
        let cardType: CardType
        let sourcePhonetic: String
        let targetPhonetic: String
        let confidence: Double
        let learningCategory: ScanLearningCategory?
        let note: String?
        let isImportable: Bool
        let notes: [String]

        private enum CodingKeys: String, CodingKey {
            case source
            case target
            case cardType = "card_type"
            case sourcePhonetic = "source_phonetic"
            case targetPhonetic = "target_phonetic"
            case confidence
            case learningCategory = "learning_category"
            case note
            case isImportable = "is_importable"
            case notes
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            source = try container.decode(String.self, forKey: .source)
            target = try container.decode(String.self, forKey: .target)
            cardType = try container.decode(CardType.self, forKey: .cardType)
            sourcePhonetic = try container.decode(String.self, forKey: .sourcePhonetic)
            targetPhonetic = try container.decode(String.self, forKey: .targetPhonetic)
            confidence = try container.decode(Double.self, forKey: .confidence)
            notes = try container.decodeIfPresent([String].self, forKey: .notes) ?? []

            let explicitCategory = try container.decodeIfPresent(ScanLearningCategory.self, forKey: .learningCategory)
            let explicitNote = try container.decodeIfPresent(String.self, forKey: .note)?.nilIfEmpty
            let explicitImportable = try container.decodeIfPresent(Bool.self, forKey: .isImportable)
            let resolvedMetadata = ScanEntryReviewMetadata.resolved(
                explicitCategory: explicitCategory,
                explicitNote: explicitNote,
                explicitImportable: explicitImportable,
                notes: notes
            )
            learningCategory = resolvedMetadata.learningCategory
            note = resolvedMetadata.note
            isImportable = resolvedMetadata.isImportable
        }
    }

    private enum CodingKeys: String, CodingKey {
        case documentType = "document_type"
        case mode
        case sourceLanguage = "source_language"
        case entries
        case warnings
        case summary
        case importMessage = "import_message"
        case confidence
        case usedColumnPairing = "used_column_pairing"
        case recognizedLineCount = "recognized_line_count"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        documentType = try container.decode(ScanDocumentType.self, forKey: .documentType)

        let modeRaw = try container.decode(String.self, forKey: .mode)
        mode = ScanMode(rawValue: modeRaw) ?? .list

        let sourceLanguageRaw = try container.decode(String.self, forKey: .sourceLanguage)
        sourceLanguage = StudyLanguage(rawValue: sourceLanguageRaw) ?? .french

        entries = try container.decode([Entry].self, forKey: .entries)
        warnings = try container.decode([String].self, forKey: .warnings)
        summary = try container.decode(String.self, forKey: .summary)
        importMessage = try container.decode(String.self, forKey: .importMessage)
        confidence = try container.decode(Double.self, forKey: .confidence)
        usedColumnPairing = try container.decode(Bool.self, forKey: .usedColumnPairing)
        recognizedLineCount = try container.decode(Int.self, forKey: .recognizedLineCount)
    }

    func toPayload() -> ScanAIResponsePayload {
        ScanAIResponsePayload(
            documentType: documentType,
            mode: mode,
            sourceLanguage: sourceLanguage,
            entries: entries.map {
                ScanAIResponseEntry(
                    source: $0.source,
                    target: $0.target,
                    cardType: $0.cardType,
                    sourcePhonetic: $0.sourcePhonetic.nilIfEmpty,
                    targetPhonetic: $0.targetPhonetic.nilIfEmpty,
                    confidence: $0.confidence,
                    reviewMetadata: ScanEntryReviewMetadata(
                        learningCategory: $0.learningCategory,
                        note: $0.note,
                        isImportable: $0.isImportable
                    ),
                    notes: $0.notes
                )
            },
            warnings: warnings,
            summary: summary,
            importMessage: importMessage,
            confidence: confidence,
            usedColumnPairing: usedColumnPairing,
            recognizedLineCount: recognizedLineCount
        )
    }
}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
