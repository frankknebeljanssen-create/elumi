import SwiftUI
import UIKit

extension ScanImportView {
    func confirmListNameEntry() {
        listName = listName.trimmingCharacters(in: .whitespacesAndNewlines)
        isListNameFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)

        withAnimation(.easeInOut(duration: 0.12)) {
            isListNamePulseActive = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            withAnimation(.easeInOut(duration: 0.16)) {
                isListNamePulseActive = false
            }
        }
    }

    func openCameraScanner() {
        guard !isRecognizingImage else { return }
        showingAdditionalScanOptions = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            showingCamera = true
        }
    }

    func restartCurrentScan() {
        guard !isRecognizingImage else { return }
        guard let imageToAnalyze = scanPreparationPreviewImage ?? selectedImage else { return }
        shouldAppendNextScan = false
        prepareForRescanDisplay()
        recognizeText(from: imageToAnalyze)
    }

    func retryCurrentScanAfterAIAlert() {
        isShowingScanAIInfoAlert = false
        scanAIInfoMessage = ""
        restartCurrentScan()
    }

    func prepareForRescanDisplay() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        focusedReviewField = nil
        previewEditSyncWorkItem?.cancel()
        previewEditSyncWorkItem = nil
        hasPendingPreviewEdits = false
        session.prepareForRescanDisplay()
    }

    var scanPreparationPreviewImage: UIImage? {
        if usePreparedScanImage {
            return preparedScanImage ?? originalScanImage
        }
        return originalScanImage ?? preparedScanImage
    }
}
