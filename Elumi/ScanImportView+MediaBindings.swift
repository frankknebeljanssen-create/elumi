import SwiftUI
import UIKit

extension ScanImportView {
    var selectedImage: UIImage? {
        get { session.selectedImage }
        nonmutating set { session.selectedImage = newValue }
    }

    var showingCamera: Bool {
        get { session.showingCamera }
        nonmutating set { session.showingCamera = newValue }
    }

    var showingPhotoLibrary: Bool {
        get { session.showingPhotoLibrary }
        nonmutating set { session.showingPhotoLibrary = newValue }
    }

    var selectedScanInputMethod: ScanInputMethod? {
        get { session.selectedScanInputMethod }
        nonmutating set { session.selectedScanInputMethod = newValue }
    }

    var showingImagePreview: Bool {
        get { session.showingImagePreview }
        nonmutating set { session.showingImagePreview = newValue }
    }

    var showingScanPreparation: Bool {
        get { session.showingScanPreparation }
        nonmutating set { session.showingScanPreparation = newValue }
    }

    var showingAdditionalScanOptions: Bool {
        get { session.showingAdditionalScanOptions }
        nonmutating set { session.showingAdditionalScanOptions = newValue }
    }

    var originalScanImage: UIImage? {
        get { session.originalScanImage }
        nonmutating set { session.originalScanImage = newValue }
    }

    var preparedScanImage: UIImage? {
        get { session.preparedScanImage }
        nonmutating set { session.preparedScanImage = newValue }
    }

    var usePreparedScanImage: Bool {
        get { session.usePreparedScanImage }
        nonmutating set { session.usePreparedScanImage = newValue }
    }

    var selectedImageSourcePath: String? {
        get { session.selectedImageSourcePath }
        nonmutating set { session.selectedImageSourcePath = newValue }
    }
}
