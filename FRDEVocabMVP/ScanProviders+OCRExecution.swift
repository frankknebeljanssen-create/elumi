import Foundation
import UIKit

extension OCRScanProvider {
    func analyze(request: ScanRequest, context: ScanProviderContext?) async -> ScanProviderResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let totalStart = CFAbsoluteTimeGetCurrent()
                let primaryImage = request.preparedImage ?? request.image
                var bestResult: ScanProviderResult?
                var bestScore = -Double.infinity

                let primaryPass = OCRPassSpec(
                    id: "primary-fast",
                    image: primaryImage,
                    recognitionLevel: .fast,
                    usesLanguageCorrection: false,
                    customWordsLimit: 0
                )

                func consider(
                    _ pass: OCRPassSpec,
                    lineBoxes: [OCRLineBox]
                ) -> Bool {
                    guard !lineBoxes.isEmpty else { return false }

                    let analyzedResult = analyzeRecognizedScan(lineBoxes, request.preferredMode)
                    let score = score(for: analyzedResult)
                    let providerResult = providerResult(
                        byApplying: score,
                        to: analyzedResult,
                        lineBoxes: lineBoxes
                    )
                    if score > bestScore {
                        bestScore = score
                        bestResult = providerResult
                    }

                    return shouldAcceptRecognitionResultEarly(
                        providerResult,
                        score: score,
                        passID: pass.id
                    )
                }

                var primaryStart = CFAbsoluteTimeGetCurrent()
                let primaryBoxes = autoreleasepool {
                    extractLineBoxes(
                        primaryPass.image,
                        request.sourceLanguage,
                        false,
                        primaryPass.recognitionLevel,
                        primaryPass.usesLanguageCorrection,
                        primaryPass.customWordsLimit
                    )
                }
                logTiming("ocr_primary", start: primaryStart)
                primaryStart = CFAbsoluteTimeGetCurrent()
                let acceptedPrimary = consider(primaryPass, lineBoxes: primaryBoxes)
                logTiming("ocr_primary_analyze", start: primaryStart)
                let primaryResult = bestResult
                let primaryScore = bestScore

                let shouldRunFallback = shouldRunEnhancedFallback(
                    after: primaryResult,
                    primaryBoxesCount: primaryBoxes.count,
                    score: primaryScore,
                    acceptedPrimary: acceptedPrimary
                )
                print("⏱ [Scan] ocr_primary_boxes=\(primaryBoxes.count) score=\(String(format: "%.1f", primaryScore)) accepted=\(acceptedPrimary) fallback=\(shouldRunFallback)")

                if shouldRunFallback {
                    let prepStart = CFAbsoluteTimeGetCurrent()
                    let fallbackBase = primaryImage
                    let fallbackImage =
                        prepareFallbackImage(fallbackBase, maxFallbackLongEdge) ??
                        downscaleImageForOCR(fallbackBase, maxFallbackLongEdge) ??
                        fallbackBase
                    logTiming("ocr_fallback_prep", start: prepStart)
                    let fallbackPass = OCRPassSpec(
                        id: "fallback-enhanced-fast",
                        image: fallbackImage,
                        recognitionLevel: .fast,
                        usesLanguageCorrection: false,
                        customWordsLimit: 180
                    )

                    let fallbackStart = CFAbsoluteTimeGetCurrent()
                    let fallbackBoxes = autoreleasepool {
                        extractLineBoxes(
                            fallbackPass.image,
                            request.sourceLanguage,
                            true,
                            fallbackPass.recognitionLevel,
                            fallbackPass.usesLanguageCorrection,
                            fallbackPass.customWordsLimit
                        )
                    }
                    logTiming("ocr_fallback", start: fallbackStart)
                    _ = consider(fallbackPass, lineBoxes: fallbackBoxes)
                }

                guard let bestResult else {
                    logTiming("ocr_total", start: totalStart)
                    continuation.resume(returning: emptyResult(for: request))
                    return
                }

                logTiming("ocr_total", start: totalStart)
                continuation.resume(returning: bestResult)
            }
        }
    }
}
