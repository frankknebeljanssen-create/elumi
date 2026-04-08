import SwiftUI
import Vision
import VisionKit
import UIKit

extension ScanImportView {
    func releaseScanWorkingImages() {
        session.releaseWorkingImages()
    }

    func selectScanMode(_ mode: ScanMode) {
        guard activeScanMode != mode else { return }

        scanModeOverride = mode

        if lastRecognizedBoxes.isEmpty {
            importMessage = mode.introMessage
            reviewSummary = "Der Scan ist jetzt auf \(mode.title.lowercased()) eingestellt."
            return
        }

        reprocessLastRecognizedScan()
    }

    func reprocessLastRecognizedScan() {
        guard !lastRecognizedBoxes.isEmpty else { return }
        let analysis = analyzeRecognizedScan(
            from: lastRecognizedBoxes,
            preferredMode: scanModeOverride
        )
        applyRecognizedScanAnalysis(analysis, appending: false)
    }

    func handleSelectedImage(_ image: UIImage?, sourcePath: String? = nil) {
        guard let image else {
            shouldAppendNextScan = false
            return
        }

        if !shouldAppendNextScan {
            session.discardDraftForReplacement(
                activeScanMode: activeScanMode,
                currentListName: listName,
                fallbackListName: listStore?.suggestedListName(from: "Scan") ?? "Scan"
            )
        }

        let selectionState = ScanImageLifecycle.makeSelectedImageState(
            from: image,
            sourcePath: sourcePath,
            maxAnalysisLongEdge: Self.maxOCRLongEdge,
            maxPreviewLongEdge: Self.maxPreviewLongEdge,
            normalizeForProcessing: { image, maxLongEdge in
                normalizedImageForProcessing(image, maxLongEdge: maxLongEdge)
            },
            downscaledForDisplay: { image, maxLongEdge in
                downscaledImageForDisplay(image, maxLongEdge: maxLongEdge)
            }
        )
        ensureSuggestedListName()
        session.applySelectedImageState(selectionState)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            guard manualCropSession == nil else { return }
            showingScanPreparation = true
        }
    }

    func recognizeText(from image: UIImage) {
        isRecognizingImage = true
        startScanProgressFeedback()
        scanRuntimeStage = .ocrPreflight
        importMessage = "Text wird erkannt..."
        let appendToExistingPreview = shouldAppendNextScan
        let aiConfiguredForScan = OpenAIResponsesScanAIClient.fromEnvironment() != nil
        let scanStart = CFAbsoluteTimeGetCurrent()
        releaseScanWorkingImages()

        Task(priority: .userInitiated) {
            let analysisImage = await preparedImageForAnalysis(from: image)
            let request = ScanRequest(
                image: analysisImage,
                preparedImage: nil,
                preferredMode: scanModeOverride,
                sourceLanguage: scanSourceLanguage
            )

            let providerResult = await makeScanAnalysisEngine().analyze(request) { stage in
                await MainActor.run {
                    scanRuntimeStage = stage
                }
            }

            await MainActor.run {
                isRecognizingImage = false
                session.stopProgressFeedback()
                session.updateEvalReport(for: providerResult)
                session.updateProviderDebugInfo(
                    result: providerResult,
                    aiConfigured: aiConfiguredForScan,
                    durationMS: Int(((CFAbsoluteTimeGetCurrent() - scanStart) * 1000).rounded())
                )
                let gptFallbackInfoMessage = scanAIFallbackPopupMessage(
                    for: providerResult,
                    aiConfigured: aiConfiguredForScan
                )

                guard !providerResult.isEmpty else {
                    importMessage = providerResult.importMessage.isEmpty
                        ? "Der Text konnte aus dem Foto nicht erkannt werden."
                        : providerResult.importMessage
                    lastRecognizedBoxes = []
                    shouldAppendNextScan = false
                    if let gptFallbackInfoMessage {
                        session.presentScanAIInfo(gptFallbackInfoMessage)
                    }
                    return
                }

                lastRecognizedBoxes = providerResult.recognizedBoxes
                applyRecognizedScanAnalysis(
                    ScanReviewMapper.makeAnalysisResult(from: providerResult),
                    appending: appendToExistingPreview
                )
                shouldAppendNextScan = false
                if let gptFallbackInfoMessage {
                    session.presentScanAIInfo(gptFallbackInfoMessage)
                }
            }
        }
    }
}
