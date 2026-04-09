import Foundation
import UIKit

struct AIScanProvider: ScanProvider {
    let client: ScanAIClient
    let maxUploadLongEdge: CGFloat = 680
    let retryUploadLongEdge: CGFloat = 512

    func analyze(request: ScanRequest, context: ScanProviderContext?) async -> ScanProviderResult {
        let start = CFAbsoluteTimeGetCurrent()
        guard client.isAvailable else {
            logDebug("ai_unavailable")
            return unavailableResult(for: request, context: context)
        }

        // Phase 1: Try text-only if OCR context has enough lines (much faster, no image upload)
        let ocrBoxCount = context?.primaryResult?.recognizedBoxes.count ?? 0
        let isTextOnlyClient = client is OpenAIResponsesScanAIClient
        print("📡 [Scan] text-only check: ocrBoxes=\(ocrBoxCount) isCorrectClient=\(isTextOnlyClient) context=\(context != nil)")
        if ocrBoxCount >= 3,
           let textOnlyClient = client as? OpenAIResponsesScanAIClient {
            let textOnlyPayload = makePayload(
                from: request,
                context: context,
                maxLongEdge: maxUploadLongEdge,
                compressionQuality: 0.45,
                compactContext: false
            )
            if let textOnlyPayload {
                do {
                    let response = try await textOnlyClient.analyzeTextOnly(textOnlyPayload)
                    logTiming("ai_text_only", start: start)
                    let result = mapResponse(response, context: context)
                    if result.entries.filter({ $0.reviewMetadata.isImportable }).count >= max(2, ocrBoxCount / 3) {
                        print("📡 [Scan] ✅ text-only sufficient: \(result.entries.count) entries")
                        return result
                    }
                    print("📡 [Scan] ⚠️ text-only insufficient (\(result.entries.count) entries), falling back to image")
                } catch {
                    print("📡 [Scan] ⚠️ text-only failed: \(error.localizedDescription), falling back to image")
                }
            }
        }

        // Phase 2: Full image+text request (fallback or primary when no OCR context)
        guard let payload = makePayload(
            from: request,
            context: context,
            maxLongEdge: maxUploadLongEdge,
            compressionQuality: 0.45,
            compactContext: false
        ) else {
            logDebug("ai_invalid_payload")
            return failureResult(
                for: request,
                context: context,
                warning: "ai_invalid_image_payload",
                importMessage: "Die KI-Analyse konnte aus diesem Bild noch nicht erstellt werden."
            )
        }

        do {
            let response = try await client.analyze(payload)
            logTiming("ai_primary", start: start)
            return mapResponse(response, context: context)
        } catch {
            if shouldRetry(after: error),
               let retryPayload = makePayload(
                    from: request,
                    context: context,
                    maxLongEdge: retryUploadLongEdge,
                    compressionQuality: 0.50,
                    compactContext: true
               ) {
                let retryStart = CFAbsoluteTimeGetCurrent()
                do {
                    let retryResponse = try await client.analyze(retryPayload)
                    logTiming("ai_retry", start: retryStart)
                    return mapResponse(retryResponse, context: context)
                } catch {
                    logTiming("ai_retry_failed", start: retryStart)
                    return failureResult(
                        for: request,
                        context: context,
                        warning: warningCode(for: error),
                        importMessage: userFacingFailureMessage(for: error)
                    )
                }
            }

            logTiming("ai_primary_failed", start: start)
            return failureResult(
                for: request,
                context: context,
                warning: warningCode(for: error),
                importMessage: userFacingFailureMessage(for: error)
            )
        }
    }
}
