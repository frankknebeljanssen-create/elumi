import Foundation
import UIKit

struct AIScanProvider: ScanProvider {
    let client: ScanAIClient
    let fallbackClient: ScanAIClient?
    let maxUploadLongEdge: CGFloat = 1568
    let retryUploadLongEdge: CGFloat = 800

    func analyze(request: ScanRequest, context: ScanProviderContext?) async -> ScanProviderResult {
        let start = CFAbsoluteTimeGetCurrent()
        guard client.isAvailable else {
            logDebug("ai_unavailable")
            return unavailableResult(for: request, context: context)
        }

        let isClaudeVision = client is ClaudeHaikuScanAIClient
        let compressionQuality: CGFloat = isClaudeVision ? 0.80 : 0.45

        // Claude Haiku: Skip text-only, go straight to vision
        // OpenAI: Try text-only first for speed
        if !isClaudeVision {
            let ocrBoxCount = context?.primaryResult?.recognizedBoxes.count ?? 0
            if ocrBoxCount >= 3,
               let textOnlyClient = client as? OpenAIResponsesScanAIClient {
                let textOnlyPayload = makePayload(
                    from: request,
                    context: context,
                    maxLongEdge: maxUploadLongEdge,
                    compressionQuality: compressionQuality,
                    compactContext: false
                )
                if let textOnlyPayload {
                    do {
                        let response = try await textOnlyClient.analyzeTextOnly(textOnlyPayload)
                        logTiming("ai_text_only", start: start)
                        let result = mapResponse(response, context: context)
                        let importableCount = result.entries.filter({ $0.reviewMetadata.isImportable }).count
                        if importableCount >= 3 {
                            print("📡 [Scan] ✅ text-only accepted (\(importableCount) importable)")
                            return result
                        }
                    } catch {
                        print("📡 [Scan] ⚠️ text-only failed: \(error.localizedDescription)")
                    }
                }
            }
        }

        // Full vision request (Claude Haiku: primary, OpenAI: fallback after text-only)
        guard let payload = makePayload(
            from: request,
            context: context,
            maxLongEdge: maxUploadLongEdge,
            compressionQuality: compressionQuality,
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
            let result = mapResponse(response, context: context)

            // ── Sonnet fallback bei zu wenigen Haiku-Ergebnissen ──
            let ocrBoxCount = context?.primaryResult?.recognizedBoxes.count ?? 0
            let aiEntryCount = result.entries.filter({ $0.reviewMetadata.isImportable }).count
            let haikuLineCount = result.recognizedLineCount
            // Trigger: (a) deutlich weniger als OCR-Boxen, ODER (b) OCR versagt UND Haiku meldet viel mehr Zeilen als Einträge
            let shouldFallback = (aiEntryCount < ocrBoxCount - 8 && ocrBoxCount >= 15)
                || (ocrBoxCount < 5 && haikuLineCount >= 20 && aiEntryCount < haikuLineCount / 2)
            if shouldFallback, let fallbackClient {
                print("📡 [Scan] ⚠️ Haiku insufficient (\(aiEntryCount) entries vs \(ocrBoxCount) OCR boxes, \(haikuLineCount) lines), trying Sonnet...")
                let fallbackStart = CFAbsoluteTimeGetCurrent()
                do {
                    let fallbackResponse = try await fallbackClient.analyze(payload)
                    logTiming("ai_sonnet_fallback", start: fallbackStart)
                    let fallbackResult = mapResponse(fallbackResponse, context: context)
                    let fallbackImportable = fallbackResult.entries.filter({ $0.reviewMetadata.isImportable }).count
                    if fallbackImportable > aiEntryCount {
                        print("📡 [Scan] ✅ Sonnet accepted (\(fallbackImportable) vs \(aiEntryCount))")
                        return fallbackResult
                    }
                    print("📡 [Scan] ℹ️ Sonnet same/fewer (\(fallbackImportable)), keeping Haiku")
                } catch {
                    print("📡 [Scan] ⚠️ Sonnet fallback failed: \(error.localizedDescription)")
                }
            }

            return result
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
