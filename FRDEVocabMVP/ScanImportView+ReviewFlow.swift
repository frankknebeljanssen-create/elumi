import SwiftUI
import UIKit

extension ScanImportView {
    var visiblePreviewPairs: [ImportPreviewPair] {
        scanPreviewAssessor.visiblePreviewPairs(
            from: previewPairs,
            sourceLanguage: scanSourceLanguage
        )
    }

    var isEditingReviewField: Bool {
        focusedReviewField != nil
    }

    func reviewFieldScrollID(for focus: ScanReviewFieldFocus) -> String {
        switch focus {
        case .source(let id):
            return "scan-review-source-\(id.uuidString)"
        case .target(let id):
            return "scan-review-target-\(id.uuidString)"
        }
    }

    func reviewFieldScrollAnchor(for focus: ScanReviewFieldFocus) -> UnitPoint {
        switch focus {
        case .source:
            return .top
        case .target:
            return scanKeyboardInset > 0 ? .center : .top
        }
    }

    var scanKeyboardBottomPadding: CGFloat {
        guard scanKeyboardInset > 0 else { return 0 }
        return scanKeyboardInset + AppTheme.Spacing.md
    }

    func updateScanKeyboardInset(from notification: Notification) {
        guard
            let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
        else {
            return
        }

        let screenHeight = UIScreen.main.bounds.height
        let overlap = max(0, screenHeight - frame.minY - windowSafeAreaBottomInset)
        withAnimation(.easeInOut(duration: 0.22)) {
            scanKeyboardInset = overlap
        }
    }

    var windowSafeAreaBottomInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets.bottom ?? 0
    }

    func ensureSuggestedListName() {
        session.ensureSuggestedListName(
            fallbackListName: listStore?.suggestedListName(from: "Scan") ?? "Scan"
        )
    }

    func refreshPreviewPairsFromImportText() {
        previewPairs = scanPreviewTextBridge.previewPairs(from: importText)
    }

    func bindingValue(for id: UUID) -> ImportPreviewPair? {
        previewPairs.first(where: { $0.id == id })
    }

    func previewAssessment(for pair: ImportPreviewPair) -> ImportPreviewAssessment {
        scanPreviewAssessor.assessment(
            for: pair,
            sourceLanguage: scanSourceLanguage
        )
    }

    func updatePreviewPair(_ id: UUID, update: (inout ImportPreviewPair) -> Void) {
        guard let index = previewPairs.firstIndex(where: { $0.id == id }) else { return }
        update(&previewPairs[index])
        previewPairs[index] = normalizedPreviewPair(previewPairs[index])
    }

    func updatePreviewPairForEditing(_ id: UUID, update: (inout ImportPreviewPair) -> Void) {
        guard let index = previewPairs.firstIndex(where: { $0.id == id }) else { return }
        update(&previewPairs[index])
        hasPendingPreviewEdits = true
    }

    func schedulePreviewEditCommit(delay: TimeInterval = 0.18) {
        previewEditSyncWorkItem?.cancel()
        hasPendingPreviewEdits = true

        let workItem = DispatchWorkItem {
            commitPreviewEditsAndSyncImportText()
        }

        previewEditSyncWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func commitPreviewEditsAndSyncImportText() {
        previewEditSyncWorkItem?.cancel()
        previewEditSyncWorkItem = nil
        guard hasPendingPreviewEdits else { return }
        previewPairs = previewPairs.map { normalizedPreviewPair($0) }
        syncImportTextFromPreview()
        hasPendingPreviewEdits = false
    }

    func syncImportTextFromPreview() {
        isSyncingPreviewToText = true
        importText = scanPreviewTextBridge.importText(from: previewPairs)
    }

    func returnToScanSetup() {
        guard !isRecognizingImage else { return }

        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
        session.returnToSetup()
    }
}
