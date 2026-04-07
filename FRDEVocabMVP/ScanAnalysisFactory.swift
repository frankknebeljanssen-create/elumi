import UIKit
import Vision

struct ScanAnalysisFactory {
    typealias OCRAnalyzer = ([OCRLineBox], ScanMode?) -> ScanAnalysisResult
    typealias OCRLineExtractor = (UIImage, StudyLanguage, Bool, VNRequestTextRecognitionLevel, Bool, Int) -> [OCRLineBox]
    typealias FallbackImagePreparer = (UIImage, CGFloat) -> UIImage?
    typealias ImageDownscaler = (UIImage, CGFloat) -> UIImage?
    typealias AIClientProvider = () -> any ScanAIClient

    let aiClientProvider: AIClientProvider

    init(
        aiClientProvider: @escaping AIClientProvider = {
            OpenAIResponsesScanAIClient.fromEnvironment() ?? UnavailableScanAIClient()
        }
    ) {
        self.aiClientProvider = aiClientProvider
    }

    func makeEngine(
        classifier: ScanDocumentClassifier = ScanDocumentClassifier(),
        analyzeRecognizedScan: @escaping OCRAnalyzer,
        extractLineBoxes: @escaping OCRLineExtractor,
        prepareFallbackImage: @escaping FallbackImagePreparer,
        downscaleImageForOCR: @escaping ImageDownscaler,
        maxFallbackLongEdge: CGFloat
    ) -> ScanAnalysisEngine {
        let ocrProvider = makeOCRProvider(
            classifier: classifier,
            analyzeRecognizedScan: analyzeRecognizedScan,
            extractLineBoxes: extractLineBoxes,
            prepareFallbackImage: prepareFallbackImage,
            downscaleImageForOCR: downscaleImageForOCR,
            maxFallbackLongEdge: maxFallbackLongEdge
        )

        return ScanAnalysisEngine(
            preflightProvider: ocrProvider,
            primaryProvider: makeAIProvider(),
            fallbackProviders: []
        )
    }

    private func makeAIProvider() -> ScanProvider {
        AIScanProvider(client: aiClientProvider())
    }

    private func makeOCRProvider(
        classifier: ScanDocumentClassifier,
        analyzeRecognizedScan: @escaping OCRAnalyzer,
        extractLineBoxes: @escaping OCRLineExtractor,
        prepareFallbackImage: @escaping FallbackImagePreparer,
        downscaleImageForOCR: @escaping ImageDownscaler,
        maxFallbackLongEdge: CGFloat
    ) -> ScanProvider {
        OCRScanProvider(
            analyzeRecognizedScan: { lineBoxes, preferredMode in
                ScanReviewMapper.makeProviderResult(
                    from: analyzeRecognizedScan(lineBoxes, preferredMode),
                    lineBoxes: lineBoxes,
                    classifier: classifier
                )
            },
            extractLineBoxes: extractLineBoxes,
            prepareFallbackImage: prepareFallbackImage,
            downscaleImageForOCR: downscaleImageForOCR,
            maxFallbackLongEdge: maxFallbackLongEdge
        )
    }
}
