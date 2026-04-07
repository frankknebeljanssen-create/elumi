import SwiftUI
import UIKit

extension ScanImportView {
    func prepareImageForOCR(from image: UIImage, completion: @escaping (UIImage) -> Void) {
        scanOCRImagePreprocessor.prepareImageForOCR(
            from: image,
            maxLongEdge: Self.maxOCRLongEdge,
            completion: completion
        )
    }

    func preparedImageForAnalysis(from image: UIImage) async -> UIImage {
        await ScanImageLifecycle.preparedAnalysisImage(
            from: image,
            cachedPreparedImage: preparedScanImage,
            prepareImage: prepareImageForOCR(from:completion:)
        )
    }

    func normalizedImageForProcessing(
        _ image: UIImage,
        maxLongEdge: CGFloat = 1800
    ) -> UIImage {
        scanOCRImagePreprocessor.normalizedImageForProcessing(
            image,
            maxLongEdge: maxLongEdge
        )
    }

    func downscaledImageForOCR(_ image: UIImage, maxLongEdge: CGFloat = 2200) -> UIImage? {
        scanOCRImagePreprocessor.downscaledImage(
            image,
            maxLongEdge: maxLongEdge
        )
    }

    func downscaledImageForDisplay(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage? {
        downscaledImageForOCR(image, maxLongEdge: maxLongEdge)
    }

    func softlyEnhancedOCRImage(from image: UIImage) -> UIImage? {
        scanOCRImagePreprocessor.softlyEnhancedOCRImage(from: image)
    }

    func fallbackPreparedImageForOCR(from image: UIImage, maxLongEdge: CGFloat) -> UIImage? {
        scanOCRImagePreprocessor.fallbackPreparedImageForOCR(
            from: image,
            maxLongEdge: maxLongEdge
        )
    }

    func sanitizedLine(_ line: String) -> String {
        scanOCRTextSanitizer.sanitizedLine(line)
    }

    func extractedDisplayTerm(from text: String) -> String {
        scanOCRTermExtractor.extractedDisplayTerm(
            from: text,
            sourceLanguage: scanSourceLanguage
        )
    }

    func extractedTermComponents(from text: String) -> (display: String, phonetic: String?) {
        let components = scanOCRTermExtractor.extractedTermComponents(
            from: text,
            sourceLanguage: scanSourceLanguage
        )
        return (components.display, components.phonetic)
    }

    func isLikelyPhoneticSegment(_ segment: String) -> Bool {
        scanOCRTermExtractor.isLikelyPhoneticSegment(
            segment,
            sourceLanguage: scanSourceLanguage
        )
    }

    func isStandalonePedagogicalMarker(_ text: String) -> Bool {
        scanOCRTermExtractor.isStandalonePedagogicalMarker(text)
    }

    func strippingPedagogicalUsageNotes(from text: String) -> String {
        scanOCRTermExtractor.strippingPedagogicalUsageNotes(from: text)
    }
}
