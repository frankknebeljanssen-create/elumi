import Foundation

extension ScanAnalysisEngine {
    func shouldUsePreflightAsFinalResult(_ result: ScanProviderResult) -> Bool {
        guard !result.isEmpty else { return false }
        guard !looksLikePedagogicalTextbookLayout(result) else { return false }

        switch result.documentType {
        case .vocabularyList:
            return result.confidence >= 0.9 && result.entries.count >= 10
        case .freeText:
            return result.confidence >= 0.9 && result.entries.count >= 9
        case .textbookTable, .mixedLayout, .cover, .poster, .unknown:
            return false
        }
    }

    func shouldRunPrimaryFirstWithPreflightFallback(for request: ScanRequest) -> Bool {
        // Always run OCR first so text-only GPT path can be used (much faster)
        return false
    }

    func shouldRunPrimaryAndPreflightConcurrently(for request: ScanRequest) -> Bool {
        false
    }

    func shouldConsultPreflightAfterPrimary(
        _ primaryResult: ScanProviderResult,
        for request: ScanRequest
    ) -> Bool {
        if primaryResult.isEmpty {
            return true
        }

        let importableCount = primaryResult.entries.filter { $0.reviewMetadata.isImportable }.count
        let completeCount = primaryResult.entries.filter {
            !$0.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        let hasAIFailureWarnings = primaryResult.warnings.contains { $0.hasPrefix("ai_") }
        let difficultLayoutDocumentTypes: Set<ScanDocumentType> = [
            .textbookTable,
            .mixedLayout,
            .poster,
            .cover
        ]

        switch request.preferredMode ?? .list {
        case .list:
            if hasAIFailureWarnings {
                return false
            }
            if difficultLayoutDocumentTypes.contains(primaryResult.documentType) &&
                primaryResult.confidence >= 0.42 &&
                completeCount >= 4 &&
                importableCount >= 4 {
                return false
            }
            if primaryResult.confidence < 0.58 {
                return true
            }
            if completeCount < 5 {
                return true
            }
            return false
        case .text:
            return true
        }
    }

    func shouldAbortAfterPrimaryFailure(_ primaryResult: ScanProviderResult) -> Bool {
        primaryResult.warnings.contains { $0.hasPrefix("ai_") }
    }

    func shouldConsultPrimaryProvider(after preflightResult: ScanProviderResult) -> Bool {
        guard !preflightResult.isEmpty else { return true }
        if looksLikePedagogicalTextbookLayout(preflightResult) {
            return true
        }

        let importableCount = preflightResult.entries.filter { $0.reviewMetadata.isImportable }.count
        let completeCount = preflightResult.entries.filter {
            !$0.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        let hasMeaningfulWarnings = preflightResult.warnings.contains { !$0.hasPrefix("ai_") }

        switch preflightResult.documentType {
        case .vocabularyList:
            if preflightResult.confidence >= 0.9 &&
                importableCount >= 10 &&
                completeCount >= 10 &&
                !hasMeaningfulWarnings {
                return false
            }
            return true
        case .freeText:
            if preflightResult.confidence >= 0.9 &&
                importableCount >= 9 &&
                completeCount >= 9 &&
                !hasMeaningfulWarnings {
                return false
            }
            return true
        case .textbookTable, .mixedLayout, .cover, .poster, .unknown:
            return true
        }
    }

    func shouldConsultFallbackProviders(for primaryResult: ScanProviderResult) -> Bool {
        if primaryResult.isEmpty {
            return true
        }

        if primaryResult.confidence < 0.74 {
            return true
        }

        switch primaryResult.documentType {
        case .textbookTable, .mixedLayout, .cover, .poster, .unknown:
            return true
        case .vocabularyList, .freeText:
            return false
        }
    }

    func shouldPrefer(_ candidate: ScanProviderResult, over current: ScanProviderResult) -> Bool {
        guard !candidate.isEmpty else { return false }
        guard !current.isEmpty else { return true }

        let candidateQuality = qualityScore(for: candidate)
        let currentQuality = qualityScore(for: current)

        if candidateQuality > currentQuality + 8 {
            return true
        }

        if current.path == .ocrOnly &&
            candidate.path != .ocrOnly &&
            (looksLikePedagogicalTextbookLayout(current) || current.documentType == .textbookTable) &&
            candidate.confidence >= current.confidence - 0.12 {
            return true
        }

        if candidate.entries.count >= current.entries.count + 2 &&
            candidate.confidence >= current.confidence - 0.05 {
            return true
        }

        if candidate.confidence > current.confidence + 0.14 &&
            candidate.entries.count >= max(1, current.entries.count - 3) {
            return true
        }

        if current.documentType == .unknown &&
            candidate.documentType != .unknown &&
            candidate.confidence >= current.confidence - 0.04 {
            return true
        }

        return false
    }

    func qualityScore(for result: ScanProviderResult) -> Double {
        let importableCount = result.entries.filter { $0.reviewMetadata.isImportable }.count
        let completeCount = result.entries.filter {
            !$0.source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            !$0.target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }.count
        let warningPenalty = Double(result.warnings.filter { !$0.hasPrefix("ai_") }.count) * 1.4

        return result.confidence * 100
            + Double(importableCount) * 7
            + Double(completeCount) * 4
            + documentTypeBonus(for: result.documentType)
            - warningPenalty
    }

    func documentTypeBonus(for documentType: ScanDocumentType) -> Double {
        switch documentType {
        case .vocabularyList, .freeText:
            return 6
        case .textbookTable, .mixedLayout, .cover, .poster:
            return 3
        case .unknown:
            return 0
        }
    }

    func mergedResult(_ result: ScanProviderResult, primaryResult: ScanProviderResult) -> ScanProviderResult {
        let aiFailureWarnings = primaryResult.warnings.filter {
            $0.hasPrefix("ai_")
        }

        guard !aiFailureWarnings.isEmpty, result.path == .ocrOnly else {
            return result
        }

        let mergedImportMessage: String
        if primaryResult.importMessage.isEmpty {
            mergedImportMessage = result.importMessage
        } else if result.importMessage.isEmpty {
            mergedImportMessage = primaryResult.importMessage
        } else {
            mergedImportMessage = "\(primaryResult.importMessage) \(result.importMessage)"
        }

        return ScanProviderResult(
            documentType: result.documentType,
            path: result.path,
            mode: result.mode,
            sourceLanguage: result.sourceLanguage,
            entries: result.entries,
            blocks: result.blocks,
            warnings: Array(Set(primaryResult.warnings + result.warnings)).sorted(),
            summary: result.summary,
            importMessage: mergedImportMessage,
            confidence: result.confidence,
            usedColumnPairing: result.usedColumnPairing,
            recognizedLineCount: result.recognizedLineCount,
            recognizedBoxes: result.recognizedBoxes
        )
    }
}
