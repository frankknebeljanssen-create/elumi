import Foundation
import UIKit

struct AIScanProvider: ScanProvider {
    let client: ScanAIClient
    let maxUploadLongEdge: CGFloat = 768
    let retryUploadLongEdge: CGFloat = 560

    func analyze(request: ScanRequest, context: ScanProviderContext?) async -> ScanProviderResult {
        let start = CFAbsoluteTimeGetCurrent()
        guard client.isAvailable else {
            logDebug("ai_unavailable")
            return unavailableResult(for: request, context: context)
        }

        guard let payload = makePayload(
            from: request,
            context: context,
            maxLongEdge: maxUploadLongEdge,
            compressionQuality: 0.65,
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
                    compressionQuality: 0.65,
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
