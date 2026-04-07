import Foundation
import UIKit

struct ScanOCRImagePreprocessor {
    func prepareImageForOCR(
        from image: UIImage,
        maxLongEdge: CGFloat,
        completion: @escaping (UIImage) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let start = CFAbsoluteTimeGetCurrent()
            let preparedImage = autoreleasepool { () -> UIImage in
                let baseImage = downscaledImage(image, maxLongEdge: maxLongEdge) ?? image
                let marginTrimmed = trimmedScanMargins(from: baseImage) ?? baseImage
                return downscaledImage(marginTrimmed, maxLongEdge: maxLongEdge) ?? marginTrimmed
            }
            logTiming("prepare_fast", start: start)

            DispatchQueue.main.async {
                completion(preparedImage)
            }
        }
    }

    func fallbackPreparedImageForOCR(
        from image: UIImage,
        maxLongEdge: CGFloat
    ) -> UIImage? {
        let start = CFAbsoluteTimeGetCurrent()
        let preparedImage = autoreleasepool { () -> UIImage? in
            let workingLongEdge = max(maxLongEdge, 960)
            let baseImage = downscaledImage(image, maxLongEdge: workingLongEdge) ?? image
            let perspectiveCorrected =
                perspectiveCorrectedDocumentImage(from: baseImage) ??
                autoCroppedDocumentImage(from: baseImage) ??
                baseImage
            let marginTrimmed = trimmedScanMargins(from: perspectiveCorrected) ?? perspectiveCorrected
            let prepared = enhancedOCRImage(from: marginTrimmed) ?? softlyEnhancedOCRImage(from: marginTrimmed) ?? marginTrimmed
            return downscaledImage(prepared, maxLongEdge: maxLongEdge) ?? prepared
        }
        logTiming("prepare_fallback", start: start)
        return preparedImage
    }

    func normalizedImageForProcessing(
        _ image: UIImage,
        maxLongEdge: CGFloat = 1800
    ) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)
        let scaleFactor = longEdge > maxLongEdge && longEdge > 0 ? maxLongEdge / longEdge : 1
        let targetSize = CGSize(
            width: max(1, floor(size.width * scaleFactor)),
            height: max(1, floor(size.height * scaleFactor))
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func downscaledImage(_ image: UIImage, maxLongEdge: CGFloat = 2200) -> UIImage? {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge, longEdge > 0 else { return nil }

        let scale = maxLongEdge / longEdge
        let targetSize = CGSize(
            width: max(1, floor(size.width * scale)),
            height: max(1, floor(size.height * scale))
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    func logTiming(_ label: String, start: CFAbsoluteTime) {
        #if DEBUG
        let elapsedMS = Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded())
        NSLog("[ScanTiming] %@: %dms", label, elapsedMS)
        #endif
    }
}
