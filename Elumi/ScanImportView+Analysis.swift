import SwiftUI
import Vision
import VisionKit
import UIKit

extension ScanImportView {
    func analyzeRecognizedScan(
        from lineBoxes: [OCRLineBox],
        preferredMode: ScanMode?
    ) -> ScanAnalysisResult {
        scanOCRAnalyzer.analyze(from: lineBoxes, preferredMode: preferredMode)
    }

    func applyRecognizedScanAnalysis(_ analysis: ScanAnalysisResult, appending: Bool) {
        let applicationState = ScanStateCoordinator.makeAnalysisApplicationState(
            from: analysis,
            existingPreviewPairs: previewPairs,
            appending: appending,
            currentImportText: importText,
            deduplicatePreviewPairs: { deduplicatedPreviewPairs($0) },
            prepareFreeTextPreviewPairs: { previewPairs, recognizedLines, sourceLanguage in
                freeTextPostProcessor.prepare(
                    seedEntries: previewPairs,
                    recognizedLines: recognizedLines,
                    sourceLanguage: sourceLanguage
                )
            },
            freeTextReviewSummary: { previewPairs, fallback in
                freeTextPostProcessor.reviewSummary(from: previewPairs, fallback: fallback)
            },
            importTextFromPreviewPairs: { previewPairs in
                scanPreviewTextBridge.importText(from: previewPairs)
            }
        )
        session.applyAnalysisApplicationState(applicationState)
    }

    func makeScanAnalysisEngine() -> ScanAnalysisEngine {
        ScanAnalysisFactory().makeEngine(
            analyzeRecognizedScan: { lineBoxes, preferredMode in
                analyzeRecognizedScan(from: lineBoxes, preferredMode: preferredMode)
            },
            extractLineBoxes: { image, sourceLanguage, includeGermanTargetLanguage, recognitionLevel, usesLanguageCorrection, customWordsLimit in
                extractOCRLineBoxes(
                    from: image,
                    sourceLanguage: sourceLanguage,
                    includeGermanTargetLanguage: includeGermanTargetLanguage,
                    recognitionLevel: recognitionLevel,
                    usesLanguageCorrection: usesLanguageCorrection,
                    customWordsLimit: customWordsLimit
                )
            },
            prepareFallbackImage: { image, maxLongEdge in
                fallbackPreparedImageForOCR(from: image, maxLongEdge: maxLongEdge)
            },
            downscaleImageForOCR: { image, maxLongEdge in
                downscaledImageForOCR(image, maxLongEdge: maxLongEdge)
            },
            maxFallbackLongEdge: Self.maxFallbackOCRLongEdge
        )
    }
}
