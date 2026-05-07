import Foundation

extension OCRScanProvider {
    func providerResult(
        byApplying score: Double,
        to result: ScanProviderResult,
        lineBoxes: [OCRLineBox]
    ) -> ScanProviderResult {
        let boundedConfidence = max(0.05, min(0.99, score / 22))

        return ScanProviderResult(
            documentType: result.documentType,
            path: result.path,
            mode: result.mode,
            sourceLanguage: result.sourceLanguage,
            entries: result.entries.map { entry in
                ScanExtractionEntry(
                    source: entry.source,
                    target: entry.target,
                    cardType: entry.cardType,
                    sourcePhonetic: entry.sourcePhonetic,
                    targetPhonetic: entry.targetPhonetic,
                    confidence: boundedConfidence,
                    reviewMetadata: entry.reviewMetadata,
                    notes: entry.notes,
                    wordClass: entry.wordClass
                )
            },
            blocks: result.blocks,
            warnings: result.warnings,
            summary: result.summary,
            importMessage: result.importMessage,
            confidence: boundedConfidence,
            usedColumnPairing: result.usedColumnPairing,
            recognizedLineCount: result.recognizedLineCount,
            recognizedBoxes: lineBoxes
        )
    }

    func emptyResult(for request: ScanRequest) -> ScanProviderResult {
        ScanProviderResult(
            documentType: .unknown,
            path: .ocrOnly,
            mode: request.preferredMode ?? .list,
            sourceLanguage: request.sourceLanguage,
            entries: [],
            blocks: [],
            warnings: ["ocr_empty_result"],
            summary: "",
            importMessage: "Der Text konnte aus dem Foto nicht erkannt werden.",
            confidence: 0,
            usedColumnPairing: false,
            recognizedLineCount: 0,
            recognizedBoxes: []
        )
    }

    func shouldAcceptRecognitionResultEarly(
        _ result: ScanProviderResult,
        score: Double,
        passID: String
    ) -> Bool {
        guard passID == "primary-fast" else { return false }

        let completeCount = result.entries.filter {
            !$0.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count

        if result.mode == .list && completeCount >= 8 {
            return true
        }

        if result.mode == .list && completeCount >= 4 && score >= 16 {
            return true
        }

        if result.mode == .list && completeCount >= 6 && score >= 22 {
            return true
        }

        if completeCount >= 6 || score >= 24 {
            return true
        }

        return false
    }

    func shouldRunEnhancedFallback(
        after primaryResult: ScanProviderResult?,
        primaryBoxesCount: Int,
        score: Double,
        acceptedPrimary: Bool
    ) -> Bool {
        guard !acceptedPrimary else { return false }
        guard primaryBoxesCount > 0 || primaryResult == nil else { return false }

        // Skip fallback if primary OCR found enough content
        guard primaryBoxesCount < 10 && score < 18 else { return false }

        guard let primaryResult else {
            return primaryBoxesCount < 6 || score < 10
        }

        switch primaryResult.documentType {
        case .vocabularyList:
            return primaryBoxesCount < 9 || score < 16 || primaryResult.confidence < 0.78
        case .freeText:
            return primaryBoxesCount < 8 || score < 15 || primaryResult.confidence < 0.76
        case .unknown:
            return primaryBoxesCount < 6 || score < 12
        case .textbookTable, .mixedLayout, .cover, .poster:
            return primaryBoxesCount < 4 || score < 8
        }
    }

    func score(for result: ScanProviderResult) -> Double {
        let completeCount = result.entries.filter {
            !$0.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        let phraseCount = result.entries.filter { $0.cardType == .phrases }.count

        return Double(completeCount) * 4.0
            + Double(result.entries.count)
            + Double(phraseCount) * 0.3
            + (result.usedColumnPairing ? 1.2 : 0)
            + Double(result.recognizedLineCount) * 0.05
    }

    func logTiming(_ label: String, start: CFAbsoluteTime) {
        let elapsedMS = Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded())
        appDebugLog("⏱ [Scan] \(label): \(elapsedMS)ms")
    }
}
