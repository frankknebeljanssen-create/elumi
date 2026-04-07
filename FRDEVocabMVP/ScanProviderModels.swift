import Foundation
import UIKit

struct ScanRequest {
    let image: UIImage
    let preparedImage: UIImage?
    let preferredMode: ScanMode?
    let sourceLanguage: StudyLanguage
}

struct ScanProviderContext {
    let primaryResult: ScanProviderResult?
}

struct ScanExtractionEntry: Identifiable, Equatable {
    let id = UUID()
    let source: String
    let target: String
    let cardType: CardType
    let sourcePhonetic: String?
    let targetPhonetic: String?
    let confidence: Double
    let reviewMetadata: ScanEntryReviewMetadata
    let notes: [String]
}

struct ScanProviderResult {
    let documentType: ScanDocumentType
    let path: ScanAnalysisPath
    let mode: ScanMode
    let sourceLanguage: StudyLanguage
    let entries: [ScanExtractionEntry]
    let blocks: [ScanBlock]
    let warnings: [String]
    let summary: String
    let importMessage: String
    let confidence: Double
    let usedColumnPairing: Bool
    let recognizedLineCount: Int
    let recognizedBoxes: [OCRLineBox]

    var isEmpty: Bool {
        entries.isEmpty && recognizedBoxes.isEmpty
    }
}

struct ScanAIContextEntry {
    let source: String
    let target: String
    let cardType: String
    let learningCategory: String?
    let note: String?
    let isImportable: Bool
}
