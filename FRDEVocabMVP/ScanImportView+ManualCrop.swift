import SwiftUI
import UIKit

extension ScanImportView {
    func presentManualCrop(from image: UIImage, target: ManualCropTarget) {
        showingScanPreparation = false
        showingImagePreview = false

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            manualCropSession = ManualCropSession(image: image, target: target)
        }
    }

    func handleManualCropCancel() {
        let target = manualCropSession?.target
        manualCropSession = nil
        guard let target else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            switch target {
            case .scanPreparation:
                showingScanPreparation = true
            case .imagePreview:
                showingImagePreview = true
            }
        }
    }

    func applyManualCrop(_ croppedImage: UIImage, shouldAnalyzeImmediately: Bool) {
        let target = manualCropSession?.target
        manualCropSession = nil
        let ocrReadyCrop = normalizedImageForProcessing(
            croppedImage,
            maxLongEdge: Self.maxOCRLongEdge
        )
        selectedImage = downscaledImageForDisplay(
            ocrReadyCrop,
            maxLongEdge: Self.maxPreviewLongEdge
        ) ?? ocrReadyCrop
        guard let target else { return }

        switch target {
        case .scanPreparation:
            preparedScanImage = ocrReadyCrop
            usePreparedScanImage = true
            if shouldAnalyzeImmediately {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    recognizeText(from: ocrReadyCrop)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showingScanPreparation = true
                }
            }
        case .imagePreview:
            preparedScanImage = ocrReadyCrop
            usePreparedScanImage = true
            if shouldAnalyzeImmediately {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    recognizeText(from: ocrReadyCrop)
                }
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    showingImagePreview = true
                }
            }
        }
    }
}
