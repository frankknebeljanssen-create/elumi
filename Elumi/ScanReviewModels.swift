import Foundation

enum ScanLearningCategory: String, Codable, CaseIterable {
    case recognizedText
    case verbs
    case phrases
    case grammar

    var title: String {
        switch self {
        case .recognizedText:
            return "Text erkannt"
        case .verbs:
            return "Verben"
        case .phrases:
            return "Phrasen"
        case .grammar:
            return "Grammatik"
        }
    }

    var sortOrder: Int {
        switch self {
        case .recognizedText:
            return 0
        case .verbs:
            return 1
        case .phrases:
            return 2
        case .grammar:
            return 3
        }
    }
}

struct ScanFreeTextReviewEntry: Identifiable, Equatable {
    let id: UUID
    let sourceText: String
    let targetText: String
    let cardType: CardType
    let category: ScanLearningCategory
    let note: String?
    let isImportable: Bool

    init(
        id: UUID = UUID(),
        sourceText: String,
        targetText: String,
        cardType: CardType,
        category: ScanLearningCategory,
        note: String? = nil,
        isImportable: Bool = true
    ) {
        self.id = id
        self.sourceText = sourceText
        self.targetText = targetText
        self.cardType = cardType
        self.category = category
        self.note = note
        self.isImportable = isImportable
    }
}

struct ScanEntryReviewMetadata: Equatable {
    let learningCategory: ScanLearningCategory?
    let note: String?
    let isImportable: Bool

    init(
        learningCategory: ScanLearningCategory? = nil,
        note: String? = nil,
        isImportable: Bool = true
    ) {
        self.learningCategory = learningCategory
        self.note = note
        self.isImportable = isImportable
    }
}

extension ScanEntryReviewMetadata {
    static func resolved(
        explicitCategory: ScanLearningCategory?,
        explicitNote: String?,
        explicitImportable: Bool?,
        notes: [String],
        fallbackCardType: CardType? = nil
    ) -> ScanEntryReviewMetadata {
        ScanEntryReviewMetadata(
            learningCategory: explicitCategory ?? legacyLearningCategory(from: notes, fallbackCardType: fallbackCardType),
            note: explicitNote ?? legacyUserFacingNote(from: notes),
            isImportable: explicitImportable ?? !notes.contains("import:false")
        )
    }

    static func legacyLearningCategory(
        from notes: [String],
        fallbackCardType: CardType? = nil
    ) -> ScanLearningCategory? {
        if notes.contains("bucket:text") {
            return .recognizedText
        }
        if notes.contains("bucket:verb") || notes.contains("bucket:verbs") {
            return .verbs
        }
        if notes.contains("bucket:phrase") || notes.contains("bucket:phrases") {
            return .phrases
        }
        if notes.contains("bucket:grammar") {
            return .grammar
        }

        if fallbackCardType == .phrases {
            return .phrases
        }

        return nil
    }

    static func legacyUserFacingNote(from notes: [String]) -> String? {
        let visibleNotes = notes.filter {
            !$0.hasPrefix("bucket:") && $0 != "import:false" && !$0.hasPrefix("ai_")
        }
        guard !visibleNotes.isEmpty else { return nil }
        return visibleNotes.joined(separator: " · ")
    }
}

struct ScanReviewEntry: Identifiable, Equatable {
    let id: UUID
    let sourceText: String
    let targetText: String
    let cardType: CardType
    let reviewMetadata: ScanEntryReviewMetadata
    let wordClass: String?

    init(
        id: UUID = UUID(),
        sourceText: String,
        targetText: String,
        cardType: CardType,
        reviewMetadata: ScanEntryReviewMetadata = ScanEntryReviewMetadata(),
        wordClass: String? = nil
    ) {
        self.id = id
        self.sourceText = sourceText
        self.targetText = targetText
        self.cardType = cardType
        self.reviewMetadata = reviewMetadata
        self.wordClass = wordClass
    }

    var french: String { sourceText }
    var german: String { targetText }
    var learningCategory: ScanLearningCategory? { reviewMetadata.learningCategory }
    var note: String? { reviewMetadata.note }
    var isImportable: Bool { reviewMetadata.isImportable }
}
