import Foundation
import UIKit
import Vision

protocol ScanProvider {
    func analyze(request: ScanRequest, context: ScanProviderContext?) async -> ScanProviderResult
}

struct ClosureScanProvider: ScanProvider {
    let handler: (ScanRequest, ScanProviderContext?) async -> ScanProviderResult

    func analyze(request: ScanRequest, context: ScanProviderContext?) async -> ScanProviderResult {
        await handler(request, context)
    }
}

struct OCRScanProvider: ScanProvider {
    typealias ResultAnalyzer = ([OCRLineBox], ScanMode?) -> ScanProviderResult
    typealias LineExtractor = (UIImage, StudyLanguage, Bool, VNRequestTextRecognitionLevel, Bool, Int) -> [OCRLineBox]
    typealias FallbackImagePreparer = (UIImage, CGFloat) -> UIImage?
    typealias ImageDownscaler = (UIImage, CGFloat) -> UIImage?

    let analyzeRecognizedScan: ResultAnalyzer
    let extractLineBoxes: LineExtractor
    let prepareFallbackImage: FallbackImagePreparer
    let downscaleImageForOCR: ImageDownscaler
    let maxFallbackLongEdge: CGFloat
}

struct OCRPassSpec {
    let id: String
    let image: UIImage
    let recognitionLevel: VNRequestTextRecognitionLevel
    let usesLanguageCorrection: Bool
    let customWordsLimit: Int
}
