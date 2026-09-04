import SwiftUI
import VisionKit
import UIKit

extension ScanImportView {
    var listNameFieldBackground: Color {
        if isListNameFocused {
            return AppTheme.Colors.primary.opacity(0.16)
        }

        return AppTheme.Colors.success.opacity(isListNamePulseActive ? 0.28 : 0.18)
    }

    var listNameFieldBorder: Color {
        if isListNameFocused {
            return AppTheme.Colors.primary.opacity(0.72)
        }

        return AppTheme.Colors.success.opacity(isListNamePulseActive ? 0.88 : 0.56)
    }

    var listNameFieldIcon: String {
        isListNameFocused ? "pencil.circle.fill" : "checkmark.circle.fill"
    }

    var isCameraCaptureAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera) || VNDocumentCameraViewController.isSupported
    }

    /// Kleine Status-Headline über der großen Stage-Card — zeigt Batch-
    /// Info („Seite 2/3") oder eine generische „Scan läuft"-Zeile. Die
    /// eigentliche User-Information (Was macht die App gerade?) kommt
    /// aus `ScanRuntimeStage.displayTitle` und wird prominent darunter
    /// gerendert, nicht mehr hier.
    var scanProgressText: String {
        let dots = String(repeating: ".", count: scanProgressStep + 1)
        if session.batchTotalCount > 1 {
            return "Seite \(session.batchCurrentIndex)/\(session.batchTotalCount)\(dots)"
        }
        return "Scan läuft\(dots)"
    }

    var hasAlternatePreparedImage: Bool {
        guard let originalScanImage, let preparedScanImage else { return false }
        return ScanImageLifecycle.fingerprint(for: originalScanImage) !=
            ScanImageLifecycle.fingerprint(for: preparedScanImage)
    }

    var selectedAppDirection: Direction {
        Direction(rawValue: selectedAppDirectionRaw) ?? .frenchToGerman
    }

    var activeScanMode: ScanMode {
        scanModeOverride ?? detectedScanMode
    }

    var hasRecognizedContent: Bool {
        !previewPairs.isEmpty
    }

    var hasActiveScanDraft: Bool {
        selectedImage != nil ||
        !lastRecognizedBoxes.isEmpty ||
        !importText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !previewPairs.isEmpty
    }

    var analysisPathDebugLabel: String {
        switch lastAnalysisPath {
        case .ocrOnly:
            return "OCR"
        case .aiAssisted:
            return "GPT"
        case .hybrid:
            return "OCR + GPT"
        }
    }

    var analysisPathDebugTint: Color {
        switch lastAnalysisPath {
        case .ocrOnly:
            return AppTheme.Colors.textSecondary
        case .aiAssisted:
            return AppTheme.Colors.primary
        case .hybrid:
            return AppTheme.Colors.success
        }
    }

    var hasScanDevDebugInfo: Bool {
        #if DEBUG
        return lastScanDurationMS != nil || !lastScanWarnings.isEmpty || !lastScanImportDebugMessage.isEmpty
        #else
        return false
        #endif
    }

    var scanDurationDebugLabel: String? {
        guard let lastScanDurationMS else { return nil }
        if lastScanDurationMS >= 1000 {
            return String(format: "%.1fs", Double(lastScanDurationMS) / 1000)
        }
        return "\(lastScanDurationMS)ms"
    }

    var completePreviewPairCount: Int {
        importablePreviewPairs.filter {
            !sanitizedLine($0.french).isEmpty && !sanitizedLine($0.german).isEmpty
        }.count
    }

    var incompletePreviewPairCount: Int {
        max(importablePreviewPairs.count - completePreviewPairCount, 0)
    }

    var importablePreviewPairs: [ImportPreviewPair] {
        previewPairs.filter(\.isImportable)
    }

    var recognizedContextPreviewCount: Int {
        previewPairs.filter { $0.learningCategory == .recognizedText }.count
    }

    var previewCounterLabel: String {
        if activeScanMode == .text {
            if recognizedContextPreviewCount > 0 {
                return "\(completePreviewPairCount) Lernkarten · \(recognizedContextPreviewCount) Text"
            }
            return "\(completePreviewPairCount) Lernkarten"
        }

        return "\(completePreviewPairCount)/\(previewPairs.count) Einträge"
    }

    var freeTextCategoryCounts: [(ScanLearningCategory, Int)] {
        ScanLearningCategory.allCases.compactMap { category in
            let count = previewPairs.filter { $0.learningCategory == category }.count
            return count > 0 ? (category, count) : nil
        }
    }

    var hasScanEvalDebugReport: Bool {
        #if DEBUG
        guard let scanEvalSuiteReport else { return false }
        return !scanEvalSuiteReport.reports.isEmpty
        #else
        return false
        #endif
    }
}
