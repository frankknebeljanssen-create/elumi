import SwiftUI

extension ScanImportView {
    var listNameBinding: Binding<String> {
        Binding(
            get: { listName },
            set: { listName = $0 }
        )
    }

    var selectedCollectionPresetBinding: Binding<ListCollectionPreset> {
        Binding(
            get: { selectedCollectionPreset },
            set: { selectedCollectionPreset = $0 }
        )
    }

    var showingCameraBinding: Binding<Bool> {
        Binding(
            get: { showingCamera },
            set: { showingCamera = $0 }
        )
    }

    var showingPhotoLibraryBinding: Binding<Bool> {
        Binding(
            get: { showingPhotoLibrary },
            set: { showingPhotoLibrary = $0 }
        )
    }

    var showingImagePreviewBinding: Binding<Bool> {
        Binding(
            get: { showingImagePreview },
            set: { showingImagePreview = $0 }
        )
    }

    var showingScanPreparationBinding: Binding<Bool> {
        Binding(
            get: { showingScanPreparation },
            set: { showingScanPreparation = $0 }
        )
    }

    var showingAdditionalScanOptionsBinding: Binding<Bool> {
        Binding(
            get: { showingAdditionalScanOptions },
            set: { showingAdditionalScanOptions = $0 }
        )
    }

    var isShowingScanAIInfoAlertBinding: Binding<Bool> {
        Binding(
            get: { isShowingScanAIInfoAlert },
            set: { isShowingScanAIInfoAlert = $0 }
        )
    }
}
