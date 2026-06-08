import UIKit
import Vision

/// Baut die Scan-Analyse-Engine. **Seit Phase 1.6 ist Anthropic der
/// einzige Scan-Provider** — der Vokabel-Scan läuft über den
/// Claude-Vision-Client gegen den Backend-Proxy (`scan-vision-proxy`).
/// Der frühere Zweit-Provider samt lokalem Schlüssel ist vollständig
/// entfernt; das geteilte Antwort-Schema bleibt erhalten.
struct ScanAnalysisFactory {
    typealias OCRAnalyzer = ([OCRLineBox], ScanMode?) -> ScanAnalysisResult
    typealias OCRLineExtractor = (UIImage, StudyLanguage, Bool, VNRequestTextRecognitionLevel, Bool, Int) -> [OCRLineBox]
    typealias FallbackImagePreparer = (UIImage, CGFloat) -> UIImage?
    typealias ImageDownscaler = (UIImage, CGFloat) -> UIImage?
    typealias AIClientProvider = () -> any ScanAIClient

    let aiClientProvider: AIClientProvider

    init(
        aiClientProvider: @escaping AIClientProvider = {
            // Vokabel-Scan läuft seit Phase 1.5 ausschließlich über den
            // Backend-Proxy — der Claude-Scan-Client ist immer verfügbar
            // (kein lokaler Schlüssel nötig). Der frühere Zweit-Provider-
            // Fallback wurde dadurch zu totem Code und ist in Phase 1.6
            // entfernt; Anthropic ist jetzt der einzige Scan-Provider.
            // `fromEnvironment()` liefert nie nil; der `??`-Zweig ist nur
            // ein defensiver Default, der nie greift.
            ClaudeHaikuScanAIClient.fromEnvironment() ?? ClaudeHaikuScanAIClient()
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
