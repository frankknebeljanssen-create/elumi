import Foundation

extension OpenAIResponsesScanAIClient {
    static let responseSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "required": [
            "document_type",
            "mode",
            "source_language",
            "entries",
            "warnings",
            "summary",
            "import_message",
            "confidence",
            "used_column_pairing",
            "recognized_line_count"
        ],
        "properties": [
            "document_type": [
                "type": "string",
                "enum": ScanDocumentType.allCases.map(\.rawValue)
            ],
            "mode": [
                "type": "string",
                "enum": [ScanMode.list.rawValue, ScanMode.text.rawValue]
            ],
            "source_language": [
                "type": "string",
                "enum": ["Französisch", "Englisch"]
            ],
            "entries": [
                "type": "array",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "required": [
                        "source",
                        "target",
                        "card_type",
                        "source_phonetic",
                        "target_phonetic",
                        "confidence",
                        "learning_category",
                        "note",
                        "is_importable",
                        "notes"
                    ],
                    "properties": [
                        "source": ["type": "string"],
                        "target": ["type": "string"],
                        "card_type": [
                            "type": "string",
                            "enum": [CardType.words.rawValue, CardType.phrases.rawValue]
                        ],
                        "source_phonetic": ["type": "string"],
                        "target_phonetic": ["type": "string"],
                        "confidence": ["type": "number"],
                        "learning_category": [
                            "type": ["string", "null"],
                            "enum": ScanLearningCategory.allCases.map(\.rawValue) + [NSNull()]
                        ],
                        "note": [
                            "type": ["string", "null"]
                        ],
                        "is_importable": ["type": "boolean"],
                        "notes": [
                            "type": "array",
                            "items": ["type": "string"]
                        ]
                    ]
                ]
            ],
            "warnings": [
                "type": "array",
                "items": ["type": "string"]
            ],
            "summary": ["type": "string"],
            "import_message": ["type": "string"],
            "confidence": ["type": "number"],
            "used_column_pairing": ["type": "boolean"],
            "recognized_line_count": ["type": "integer"]
        ]
    ]
}
