import Foundation
import UIKit

struct ScanAnalysisApplicationState {
    let detectedScanMode: ScanMode
    let scanSourceLanguage: StudyLanguage
    let lastAnalysisPath: ScanAnalysisPath
    let previewPairs: [ImportPreviewPair]
    let reviewSummary: String
    let importMessage: String
    let importText: String
    let shouldSyncImportTextFromPreview: Bool
    let reviewScrollTriggerDelta: Int
    let toastMessage: String
}

struct ScanResetState {
    let importText: String
    let previewPairs: [ImportPreviewPair]
    let selectedImage: UIImage?
    let lastRecognizedBoxes: [OCRLineBox]
    let originalScanImage: UIImage?
    let preparedScanImage: UIImage?
    let usePreparedScanImage: Bool
    let importMessage: String
    let reviewSummary: String
    let listName: String
}

struct ScanReturnToSetupState {
    let shouldAppendNextScan: Bool
    let showingAdditionalScanOptions: Bool
    let showingImagePreview: Bool
    let showingScanPreparation: Bool
    let previewPairPendingDeletion: ImportPreviewPair?
    let resetState: ScanResetState
}

enum ScanStateCoordinator {
    static let defaultReviewSummary = "Wähle zuerst, ob du eine Vokabelliste oder freien Text scannen willst."

    static func makeAnalysisApplicationState(
        from analysis: ScanAnalysisResult,
        existingPreviewPairs: [ImportPreviewPair],
        appending: Bool,
        currentImportText: String,
        deduplicatePreviewPairs: ([ImportPreviewPair]) -> [ImportPreviewPair],
        prepareFreeTextPreviewPairs: ([ImportPreviewPair], [String], StudyLanguage) -> [ImportPreviewPair],
        freeTextReviewSummary: ([ImportPreviewPair], String) -> String,
        importTextFromPreviewPairs: ([ImportPreviewPair]) -> String
    ) -> ScanAnalysisApplicationState {
        let preparedApplication = ScanReviewMapper.makePreparedAnalysisApplication(
            from: analysis,
            existingPreviewPairs: existingPreviewPairs,
            appending: appending,
            deduplicatePreviewPairs: deduplicatePreviewPairs,
            prepareFreeTextPreviewPairs: prepareFreeTextPreviewPairs,
            freeTextReviewSummary: freeTextReviewSummary
        )

        let preparedPreviewPairs = preparedApplication.preparedPreviewPairs
        let mergedPreviewPairs = preparedApplication.mergedPreviewPairs
        let hasRecognizedEntries = !mergedPreviewPairs.isEmpty

        let importText = hasRecognizedEntries
            ? importTextFromPreviewPairs(mergedPreviewPairs)
            : (appending ? currentImportText : "")

        let importMessage = hasRecognizedEntries
            ? (appending
                ? "\(analysis.importMessage) Die neuen Einträge wurden ergänzt."
                : analysis.importMessage)
            : analysis.importMessage

        let toastMessage: String
        if !hasRecognizedEntries {
            toastMessage = "Analyse abgeschlossen"
        } else if appending {
            toastMessage = "Analyse abgeschlossen: \(preparedPreviewPairs.count) weitere Einträge erkannt"
        } else {
            toastMessage = "Analyse abgeschlossen: \(preparedPreviewPairs.count) Einträge erkannt"
        }

        return ScanAnalysisApplicationState(
            detectedScanMode: analysis.mode,
            scanSourceLanguage: analysis.sourceLanguage,
            lastAnalysisPath: analysis.analysisPath,
            previewPairs: mergedPreviewPairs,
            reviewSummary: preparedApplication.reviewSummary,
            importMessage: importMessage,
            importText: importText,
            shouldSyncImportTextFromPreview: hasRecognizedEntries,
            reviewScrollTriggerDelta: hasRecognizedEntries ? 1 : 0,
            toastMessage: toastMessage
        )
    }

    static func makeResetState(
        activeScanMode: ScanMode,
        keepingListName: Bool,
        currentListName: String,
        fallbackListName: String
    ) -> ScanResetState {
        ScanResetState(
            importText: "",
            previewPairs: [],
            selectedImage: nil,
            lastRecognizedBoxes: [],
            originalScanImage: nil,
            preparedScanImage: nil,
            usePreparedScanImage: true,
            importMessage: activeScanMode.introMessage,
            reviewSummary: defaultReviewSummary,
            listName: keepingListName ? currentListName : fallbackListName
        )
    }

    static func makeReturnToSetupState(
        activeScanMode: ScanMode,
        currentListName: String
    ) -> ScanReturnToSetupState {
        ScanReturnToSetupState(
            shouldAppendNextScan: false,
            showingAdditionalScanOptions: false,
            showingImagePreview: false,
            showingScanPreparation: false,
            previewPairPendingDeletion: nil,
            resetState: makeResetState(
                activeScanMode: activeScanMode,
                keepingListName: true,
                currentListName: currentListName,
                fallbackListName: currentListName
            )
        )
    }
}
