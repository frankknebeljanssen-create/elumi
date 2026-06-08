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
            // Prefer Claude Haiku Vision (faster, single-step)
            if let claude = ClaudeHaikuScanAIClient.fromEnvironment() {
                return claude
            }
            // Fallback to OpenAI if no Anthropic key
            return OpenAIResponsesScanAIClient.fromEnvironment() ?? UnavailableScanAIClient()
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
        let primary = aiClientProvider()
        // Doppel-Analyse: nur wenn der Primary ein Claude-Scan-Client ist,
        // schieben wir einen Sonnet-Client als Fallback nach. Kein API-Key
        // mehr nötig — beide Clients routen über den Backend-Proxy.
        let fallback: ScanAIClient? = (primary as? ClaudeHaikuScanAIClient).map { _ in
            ClaudeHaikuScanAIClient(model: "claude-sonnet-4-5-20250929", maxTokens: 16384)
        }
        return AIScanProvider(client: primary, fallbackClient: fallback)
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
