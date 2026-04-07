import Foundation

enum ScanDocumentType: String, Codable, CaseIterable {
    case vocabularyList
    case textbookTable
    case freeText
    case mixedLayout
    case poster
    case cover
    case unknown
}

enum ScanAnalysisPath: String, Codable, CaseIterable {
    case ocrOnly
    case aiAssisted
    case hybrid
}

enum ScanBlockRole: String, Codable, CaseIterable {
    case sourceColumn
    case targetColumn
    case exampleColumn
    case heading
    case body
    case decoration
    case unknown
}

struct ScanBlock: Identifiable, Equatable {
    let id = UUID()
    let role: ScanBlockRole
    let text: String
    let languageCode: String?
}

struct ScanAnalysisResult {
    let mode: ScanMode
    let sourceLanguage: StudyLanguage
    let entries: [ScanReviewEntry]
    let summary: String
    let importMessage: String
    let analysisPath: ScanAnalysisPath
    let usedColumnPairing: Bool
    let recognizedLineCount: Int
    let recognizedLines: [String]
}
