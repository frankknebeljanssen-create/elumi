import SwiftUI

extension ScanImportView {
    var isRecognizingImage: Bool {
        get { session.isRecognizingImage }
        nonmutating set { session.isRecognizingImage = newValue }
    }

    var isSyncingPreviewToText: Bool {
        get { session.isSyncingPreviewToText }
        nonmutating set { session.isSyncingPreviewToText = newValue }
    }

    var scanToastMessage: String {
        get { session.scanToastMessage }
        nonmutating set { session.scanToastMessage = newValue }
    }

    var isShowingScanToast: Bool {
        get { session.isShowingScanToast }
        nonmutating set { session.isShowingScanToast = newValue }
    }

    var scanToastIsWarning: Bool {
        get { session.scanToastIsWarning }
        nonmutating set { session.scanToastIsWarning = newValue }
    }

    var scanAIInfoMessage: String {
        get { session.scanAIInfoMessage }
        nonmutating set { session.scanAIInfoMessage = newValue }
    }

    var isShowingScanAIInfoAlert: Bool {
        get { session.isShowingScanAIInfoAlert }
        nonmutating set { session.isShowingScanAIInfoAlert = newValue }
    }

    var scanProgressStep: Int {
        get { session.scanProgressStep }
        nonmutating set { session.scanProgressStep = newValue }
    }

    var scanRuntimeStage: ScanRuntimeStage {
        get { session.scanRuntimeStage }
        nonmutating set { session.scanRuntimeStage = newValue }
    }

    var lastRecognizedBoxes: [OCRLineBox] {
        get { session.lastRecognizedBoxes }
        nonmutating set { session.lastRecognizedBoxes = newValue }
    }

    var lastAnalysisPath: ScanAnalysisPath {
        get { session.lastAnalysisPath }
        nonmutating set { session.lastAnalysisPath = newValue }
    }

    var lastScanWarnings: [String] {
        get { session.lastScanWarnings }
        nonmutating set { session.lastScanWarnings = newValue }
    }

    var lastScanDurationMS: Int? {
        get { session.lastScanDurationMS }
        nonmutating set { session.lastScanDurationMS = newValue }
    }

    var lastScanAIConfigured: Bool {
        get { session.lastScanAIConfigured }
        nonmutating set { session.lastScanAIConfigured = newValue }
    }

    var lastScanImportDebugMessage: String {
        get { session.lastScanImportDebugMessage }
        nonmutating set { session.lastScanImportDebugMessage = newValue }
    }

    var scanEvalSuiteReport: ScanEvalSuiteReport? {
        get { session.scanEvalSuiteReport }
        nonmutating set { session.scanEvalSuiteReport = newValue }
    }
}
