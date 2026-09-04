import Foundation
import UIKit

extension AIScanProvider {
    func makePayload(
        from request: ScanRequest,
        context: ScanProviderContext?,
        maxLongEdge: CGFloat,
        compressionQuality: CGFloat,
        compactContext: Bool
    ) -> ScanAIRequestPayload? {
        let sourceImage = request.preparedImage ?? request.image
        guard let imageData = boundedJPEGData(
            from: sourceImage,
            maxLongEdge: maxLongEdge,
            compressionQuality: compressionQuality
        ) else { return nil }

        let ocrContext: ScanAIContextSnapshot? = context?.primaryResult.map { primaryResult in
            let recognizedLines = compactContext
                ? Array(primaryResult.recognizedBoxes.map(\.text).prefix(18))
                : Array(primaryResult.recognizedBoxes.map(\.text).prefix(40))
            let entries = compactContext
                ? Array(primaryResult.entries.prefix(8))
                : Array(primaryResult.entries.prefix(16))

            return ScanAIContextSnapshot(
                documentType: primaryResult.documentType,
                mode: primaryResult.mode,
                sourceLanguageCode: request.sourceLanguage.rawValue,
                confidence: primaryResult.confidence,
                recognizedLines: recognizedLines,
                entries: entries.map {
                    ScanAIContextEntry(
                        source: $0.source,
                        target: $0.target,
                        cardType: $0.cardType.rawValue,
                        learningCategory: $0.reviewMetadata.learningCategory?.rawValue,
                        note: $0.reviewMetadata.note,
                        isImportable: $0.reviewMetadata.isImportable
                    )
                }
            )
        }

        return ScanAIRequestPayload(
            preferredMode: request.preferredMode,
            sourceLanguageCode: request.sourceLanguage.rawValue,
            imageJPEGData: imageData,
            ocrContext: ocrContext
        )
    }

    func boundedJPEGData(
        from image: UIImage,
        maxLongEdge: CGFloat,
        compressionQuality: CGFloat
    ) -> Data? {
        autoreleasepool {
            let boundedImage = downscaledImageIfNeeded(image, maxLongEdge: maxLongEdge) ?? image
            return boundedImage.jpegData(compressionQuality: compressionQuality)
        }
    }

    func downscaledImageIfNeeded(
        _ image: UIImage,
        maxLongEdge: CGFloat
    ) -> UIImage? {
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

    func mapResponse(
        _ response: ScanAIResponsePayload,
        context: ScanProviderContext?
    ) -> ScanProviderResult {
        let normalizedResponse = normalizedResponsePayload(response)

        return ScanProviderResult(
            documentType: normalizedResponse.documentType,
            path: context?.primaryResult == nil ? .aiAssisted : .hybrid,
            mode: normalizedResponse.mode,
            sourceLanguage: normalizedResponse.sourceLanguage,
            entries: normalizedResponse.entries.map {
                ScanExtractionEntry(
                    source: $0.source,
                    target: $0.target,
                    cardType: $0.cardType,
                    sourcePhonetic: $0.sourcePhonetic,
                    targetPhonetic: $0.targetPhonetic,
                    confidence: $0.confidence,
                    reviewMetadata: $0.reviewMetadata,
                    notes: $0.notes,
                    wordClass: $0.wordClass
                )
            },
            blocks: [],
            warnings: normalizedResponse.warnings,
            summary: normalizedResponse.summary,
            importMessage: normalizedResponse.importMessage,
            confidence: normalizedResponse.confidence,
            usedColumnPairing: normalizedResponse.usedColumnPairing,
            recognizedLineCount: normalizedResponse.recognizedLineCount,
            recognizedBoxes: context?.primaryResult?.recognizedBoxes ?? []
        )
    }
}
