import Foundation
import SwiftUI
import UIKit

@MainActor
final class ScanSessionController: ObservableObject {
    @Published var importText = ""
    @Published var scanSourceLanguage: StudyLanguage = .french
    @Published var importType: CardType = .words
    @Published var selectedCollectionPreset: ListCollectionPreset = .schoolbook
    @Published var listName = ""
    @Published var importMessage = ScanMode.list.introMessage
    @Published var previewPairs: [ImportPreviewPair] = []
    @Published var selectedImage: UIImage?
    @Published var showingCamera = false
    @Published var showingPhotoLibrary = false
    @Published var selectedScanInputMethod: ScanInputMethod?
    @Published var isRecognizingImage = false
    @Published var isSyncingPreviewToText = false
    @Published var showingImagePreview = false
    @Published var showingScanPreparation = false
    @Published var showingAdditionalScanOptions = false
    @Published var scanToastMessage = ""
    @Published var isShowingScanToast = false
    @Published var scanToastIsWarning = false
    @Published var scanAIInfoMessage = ""
    @Published var isShowingScanAIInfoAlert = false
    @Published var scanProgressStep = 0
    @Published var scanRuntimeStage: ScanRuntimeStage = .idle
    @Published var shouldAppendNextScan = false
    @Published var pendingBatchImages: [UIImage] = []
    @Published var batchCurrentIndex = 0
    @Published var batchTotalCount = 0
    @Published var originalScanImage: UIImage?
    @Published var preparedScanImage: UIImage?
    @Published var usePreparedScanImage = true
    @Published var selectedImageSourcePath: String?
    @Published var previewPairPendingDeletion: ImportPreviewPair?
    @Published var detectedScanMode: ScanMode = .list
    @Published var scanModeOverride: ScanMode? = .list
    @Published var lastRecognizedBoxes: [OCRLineBox] = []
    @Published var lastAnalysisPath: ScanAnalysisPath = .ocrOnly
    @Published var lastScanWarnings: [String] = []
    @Published var lastScanDurationMS: Int?
    @Published var lastScanAIConfigured = false
    @Published var lastScanImportDebugMessage = ""
    @Published var scanEvalSuiteReport: ScanEvalSuiteReport?
    @Published var reviewSummary = ScanStateCoordinator.defaultReviewSummary
    @Published var reviewScrollTrigger = 0
    @Published var hasPendingPreviewEdits = false

    private var scanToastDismissWorkItem: DispatchWorkItem?
    private var scanProgressTimer: Timer?

    deinit {
        scanToastDismissWorkItem?.cancel()
        scanProgressTimer?.invalidate()
    }

    var activeScanMode: ScanMode {
        scanModeOverride ?? detectedScanMode
    }

    var hasActiveScanDraft: Bool {
        selectedImage != nil ||
        !lastRecognizedBoxes.isEmpty ||
        !importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !previewPairs.isEmpty
    }

    func showToast(
        _ message: String,
        isWarning: Bool = false,
        delay: TimeInterval = 0
    ) {
        scanToastDismissWorkItem?.cancel()

        let presentWorkItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.scanToastMessage = message
            self.scanToastIsWarning = isWarning

            withAnimation(.easeInOut(duration: 0.22)) {
                self.isShowingScanToast = true
            }

            let dismissWorkItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                withAnimation(.easeInOut(duration: 0.22)) {
                    self.isShowingScanToast = false
                }
            }
            self.scanToastDismissWorkItem = dismissWorkItem
            DispatchQueue.main.asyncAfter(
                deadline: .now() + (isWarning ? 3.2 : 1.8),
                execute: dismissWorkItem
            )
        }

        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: presentWorkItem)
        } else {
            presentWorkItem.perform()
        }
    }

    func presentScanAIInfo(_ message: String) {
        scanAIInfoMessage = message
        isShowingScanAIInfoAlert = true
    }

    func startProgressFeedback() {
        scanProgressTimer?.invalidate()
        scanProgressStep = 0
        scanProgressTimer = Timer.scheduledTimer(withTimeInterval: 0.42, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.scanProgressStep = (self.scanProgressStep + 1) % 3
            }
        }
    }

    func stopProgressFeedback() {
        scanProgressTimer?.invalidate()
        scanProgressTimer = nil
        scanProgressStep = 0
        scanRuntimeStage = .idle
    }

    func clearScanDiagnostics() {
        lastScanWarnings = []
        lastScanDurationMS = nil
        lastScanAIConfigured = false
        lastScanImportDebugMessage = ""
        scanEvalSuiteReport = nil
    }
}
