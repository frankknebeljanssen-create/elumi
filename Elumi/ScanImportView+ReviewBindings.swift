import SwiftUI

extension ScanImportView {
    var shouldAppendNextScan: Bool {
        get { session.shouldAppendNextScan }
        nonmutating set { session.shouldAppendNextScan = newValue }
    }

    var previewPairPendingDeletion: ImportPreviewPair? {
        get { session.previewPairPendingDeletion }
        nonmutating set { session.previewPairPendingDeletion = newValue }
    }

    var reviewSummary: String {
        get { session.reviewSummary }
        nonmutating set { session.reviewSummary = newValue }
    }

    var reviewScrollTrigger: Int {
        get { session.reviewScrollTrigger }
        nonmutating set { session.reviewScrollTrigger = newValue }
    }

    var hasPendingPreviewEdits: Bool {
        get { session.hasPendingPreviewEdits }
        nonmutating set { session.hasPendingPreviewEdits = newValue }
    }
}
