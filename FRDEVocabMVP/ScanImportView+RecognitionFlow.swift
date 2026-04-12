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

    func handleSelectedImages(_ images: [UIImage]) {
        guard !images.isEmpty else {
            shouldAppendNextScan = false
            return
        }

        if images.count == 1 {
            handleSelectedImage(images[0])
            return
        }

        // Multi-select: queue batch, generate thumbnails, process first image normally
        session.pendingBatchImages = Array(images.dropFirst())
        session.batchTotalCount = images.count
        session.batchCurrentIndex = 1
        session.batchThumbnails = images.map { img in
            let maxEdge: CGFloat = 120
            let scale = min(maxEdge / img.size.width, maxEdge / img.size.height, 1.0)
            let newSize = CGSize(width: img.size.width * scale, height: img.size.height * scale)
            let renderer = UIGraphicsImageRenderer(size: newSize)
            return renderer.image { _ in img.draw(in: CGRect(origin: .zero, size: newSize)) }
        }
        handleSelectedImage(images[0])
    }

    func processNextBatchImage() {
        guard !session.pendingBatchImages.isEmpty else {
            session.batchTotalCount = 0
            session.batchCurrentIndex = 0
            return
        }

        let nextImage = session.pendingBatchImages.removeFirst()
        session.batchCurrentIndex = session.batchTotalCount - session.pendingBatchImages.count

        shouldAppendNextScan = true

        let selectionState = ScanImageLifecycle.makeSelectedImageState(
            from: nextImage,
            sourcePath: nil,
            maxAnalysisLongEdge: Self.maxOCRLongEdge,
            maxPreviewLongEdge: Self.maxPreviewLongEdge,
            normalizeForProcessing: { image, maxLongEdge in
                normalizedImageForProcessing(image, maxLongEdge: maxLongEdge)
            },
            downscaledForDisplay: { image, maxLongEdge in
                downscaledImageForDisplay(image, maxLongEdge: maxLongEdge)
            }
        )
        session.applySelectedImageState(selectionState)

        // Skip preparation sheet — auto-analyze
        recognizeText(from: selectionState.analysisImage)
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
                fallbackListName: listStore?.suggestedListName(from: scanDateBaseName) ?? scanDateBaseName
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
        feedbackPlayer.playScanStart()
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
                let isBatchMode = session.batchTotalCount > 1
                let hasPendingPages = !session.pendingBatchImages.isEmpty
                if !isBatchMode {
                    isRecognizingImage = false
                    feedbackPlayer.playScanDone()
                    // Show summary screen for single scan too
                    session.batchTotalCount = 1
                }
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

                    // Continue batch even if one page fails
                    if !session.pendingBatchImages.isEmpty {
                        session.showToast("Seite \(session.batchCurrentIndex) konnte nicht erkannt werden")
                        processNextBatchImage()
                    } else if session.batchTotalCount > 1 {
                        isRecognizingImage = false
                        feedbackPlayer.playScanDone()
                        session.batchCompleted = true
                    } else if let gptFallbackInfoMessage {
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

                // Continue batch if more images queued
                if !session.pendingBatchImages.isEmpty {
                    processNextBatchImage()
                } else {
                    // Analysis complete — show summary screen
                    if isBatchMode {
                        isRecognizingImage = false
                        feedbackPlayer.playScanDone()
                    }
                    session.batchCompleted = true
                }
            }
        }
    }
}
