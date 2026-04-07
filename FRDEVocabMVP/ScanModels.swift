import Foundation

struct ScanAIContextSnapshot {
    let documentType: ScanDocumentType
    let mode: ScanMode
    let sourceLanguageCode: String
    let confidence: Double
    let recognizedLines: [String]
    let entries: [ScanAIContextEntry]
}

struct ScanAIRequestPayload {
    let preferredMode: ScanMode?
    let sourceLanguageCode: String
    let imageJPEGData: Data
    let ocrContext: ScanAIContextSnapshot?
}

struct ScanAIResponseEntry {
    let source: String
    let target: String
    let cardType: CardType
    let sourcePhonetic: String?
    let targetPhonetic: String?
    let confidence: Double
    let reviewMetadata: ScanEntryReviewMetadata
    let notes: [String]
}

struct ScanAIResponsePayload {
    let documentType: ScanDocumentType
    let mode: ScanMode
    let sourceLanguage: StudyLanguage
    let entries: [ScanAIResponseEntry]
    let warnings: [String]
    let summary: String
    let importMessage: String
    let confidence: Double
    let usedColumnPairing: Bool
    let recognizedLineCount: Int
}
