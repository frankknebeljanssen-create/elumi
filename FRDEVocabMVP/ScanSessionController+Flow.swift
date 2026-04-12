import Foundation

extension ScanSessionController {
    func ensureSuggestedListName(fallbackListName: String) {
        if listName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            listName = fallbackListName
        }
    }

    func releaseWorkingImages() {
        // Keep originalScanImage for rescan — only release the prepared cache
        preparedScanImage = nil
        usePreparedScanImage = true
    }

    func applySelectedImageState(_ state: ScanSelectedImageState) {
        showingCamera = false
        showingPhotoLibrary = false
        showingImagePreview = false
        originalScanImage = state.analysisImage
        preparedScanImage = nil
        usePreparedScanImage = false
        selectedImage = state.previewImage
        selectedImageSourcePath = state.sourcePath
        scanEvalSuiteReport = nil
        importMessage = "Bild prüfen und dann analysieren."
    }

    func prepareForRescanDisplay() {
        previewPairs = []
        importText = ""
        reviewSummary = ScanStateCoordinator.defaultReviewSummary
        importMessage = "Die Vorlage wird neu analysiert."
        lastRecognizedBoxes = []
        clearScanDiagnostics()
        previewPairPendingDeletion = nil
        showingImagePreview = false
        showingAdditionalScanOptions = false
        showingScanPreparation = false
    }

    func discardDraftForReplacement(
        activeScanMode: ScanMode,
        currentListName: String,
        fallbackListName: String
    ) {
        guard hasActiveScanDraft else { return }

        let preservedInputMethod = selectedScanInputMethod
        let resetState = ScanStateCoordinator.makeResetState(
            activeScanMode: activeScanMode,
            keepingListName: true,
            currentListName: currentListName,
            fallbackListName: fallbackListName
        )
        applyResetState(resetState)
        selectedScanInputMethod = preservedInputMethod
        selectedImageSourcePath = nil
        shouldAppendNextScan = false
        cancelBatch()
        showingAdditionalScanOptions = false
        showingScanPreparation = false
        showingImagePreview = false
    }

    func applyAnalysisApplicationState(_ state: ScanAnalysisApplicationState) {
        detectedScanMode = state.detectedScanMode
        scanSourceLanguage = state.scanSourceLanguage
        lastAnalysisPath = state.lastAnalysisPath
        previewPairs = state.previewPairs
        reviewSummary = state.reviewSummary
        hasPendingPreviewEdits = false
        if state.shouldSyncImportTextFromPreview {
            isSyncingPreviewToText = true
        }
        importText = state.importText
        reviewScrollTrigger += state.reviewScrollTriggerDelta
        importMessage = state.importMessage
        // No toast — summary screen handles the feedback
        if batchTotalCount == 0 {
            showToast(state.toastMessage)
        }
    }

    func applyResetState(_ state: ScanResetState) {
        importText = state.importText
        previewPairs = state.previewPairs
        selectedImage = state.selectedImage
        selectedImageSourcePath = nil
        lastRecognizedBoxes = state.lastRecognizedBoxes
        originalScanImage = state.originalScanImage
        preparedScanImage = state.preparedScanImage
        usePreparedScanImage = state.usePreparedScanImage
        importMessage = state.importMessage
        reviewSummary = state.reviewSummary
        listName = state.listName
        clearScanDiagnostics()
        hasPendingPreviewEdits = false
        cancelBatch()
    }

    func resetInputAfterSuccessfulImport(
        keepingListName: Bool,
        fallbackListName: String
    ) {
        let resetState = ScanStateCoordinator.makeResetState(
            activeScanMode: activeScanMode,
            keepingListName: keepingListName,
            currentListName: listName,
            fallbackListName: fallbackListName
        )
        applyResetState(resetState)
        selectedScanInputMethod = nil
    }

    var isBatchAnalysisInProgress: Bool {
        batchTotalCount > 1 && !batchCompleted && (isRecognizingImage || !pendingBatchImages.isEmpty)
    }

    func cancelBatch() {
        pendingBatchImages = []
        batchThumbnails = []
        batchTotalCount = 0
        batchCurrentIndex = 0
        batchCompleted = false
    }

    func returnToSetup() {
        stopProgressFeedback()
        let returnState = ScanStateCoordinator.makeReturnToSetupState(
            activeScanMode: activeScanMode,
            currentListName: listName
        )
        shouldAppendNextScan = returnState.shouldAppendNextScan
        showingAdditionalScanOptions = returnState.showingAdditionalScanOptions
        showingImagePreview = returnState.showingImagePreview
        showingScanPreparation = returnState.showingScanPreparation
        previewPairPendingDeletion = returnState.previewPairPendingDeletion
        selectedScanInputMethod = nil
        applyResetState(returnState.resetState)
    }
}
