import Foundation
import UIKit

struct ScanSelectedImageState {
    let sourcePath: String?
    let analysisImage: UIImage
    let previewImage: UIImage
}

enum ScanImageLifecycle {
    static func makeSelectedImageState(
        from image: UIImage,
        sourcePath: String?,
        maxAnalysisLongEdge: CGFloat,
        maxPreviewLongEdge: CGFloat,
        normalizeForProcessing: (UIImage, CGFloat) -> UIImage,
        downscaledForDisplay: (UIImage, CGFloat) -> UIImage?
    ) -> ScanSelectedImageState {
        let analysisImage = normalizeForProcessing(image, maxAnalysisLongEdge)
        let previewImage = downscaledForDisplay(analysisImage, maxPreviewLongEdge) ?? analysisImage
        return ScanSelectedImageState(
            sourcePath: sourcePath,
            analysisImage: analysisImage,
            previewImage: previewImage
        )
    }

    @MainActor
    static func preparedAnalysisImage(
        from image: UIImage,
        cachedPreparedImage: UIImage?,
        prepareImage: @escaping @MainActor (UIImage, @escaping (UIImage) -> Void) -> Void
    ) async -> UIImage {
        let originalFingerprint = fingerprint(for: image)
        if let cachedPreparedImage,
           fingerprint(for: cachedPreparedImage) == originalFingerprint {
            return cachedPreparedImage
        }

        return await withCheckedContinuation { continuation in
            prepareImage(image) { preparedImage in
                continuation.resume(returning: preparedImage)
            }
        }
    }

    static func fingerprint(for image: UIImage) -> String {
        let size = image.size
        return "\(Int(size.width.rounded()))x\(Int(size.height.rounded()))"
    }
}
