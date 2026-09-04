import SwiftUI

extension ScanImportView {
    var importText: String {
        get { session.importText }
        nonmutating set { session.importText = newValue }
    }

    var scanSourceLanguage: StudyLanguage {
        get { session.scanSourceLanguage }
        nonmutating set { session.scanSourceLanguage = newValue }
    }

    var importType: CardType {
        get { session.importType }
        nonmutating set { session.importType = newValue }
    }

    var selectedCollectionPreset: ListCollectionPreset {
        get { session.selectedCollectionPreset }
        nonmutating set { session.selectedCollectionPreset = newValue }
    }

    var listName: String {
        get { session.listName }
        nonmutating set { session.listName = newValue }
    }

    var importMessage: String {
        get { session.importMessage }
        nonmutating set { session.importMessage = newValue }
    }

    var previewPairs: [ImportPreviewPair] {
        get { session.previewPairs }
        nonmutating set { session.previewPairs = newValue }
    }

    var detectedScanMode: ScanMode {
        get { session.detectedScanMode }
        nonmutating set { session.detectedScanMode = newValue }
    }

    var scanModeOverride: ScanMode? {
        get { session.scanModeOverride }
        nonmutating set { session.scanModeOverride = newValue }
    }
}
