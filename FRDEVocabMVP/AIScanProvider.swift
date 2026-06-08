import Foundation
import UIKit

struct AIScanProvider: ScanProvider {
    let client: ScanAIClient
    let fallbackClient: ScanAIClient?
    let maxUploadLongEdge: CGFloat = 2048
    let retryUploadLongEdge: CGFloat = 800

    func analyze(request: ScanRequest, context: ScanProviderContext?) async -> ScanProviderResult {
        let start = CFAbsoluteTimeGetCurrent()
        guard client.isAvailable else {
            logDebug("ai_unavailable")
            return unavailableResult(for: request, context: context)
        }

        // **Phase 1.6** — der Scan läuft ausschließlich über den Claude-
        // Vision-Client (Backend-Proxy). Der frühere OpenAI-Text-Only-
        // Fast-Path (`if !isClaudeVision { … }`) ist mit dem OpenAI-
        // Provider entfernt; die Kompression ist damit fix auf den
        // Vision-Wert gesetzt.
        let compressionQuality: CGFloat = 0.90

        // Full vision request (Claude Haiku primary, danach Sonnet-Merge).
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
            let haikuResult = mapResponse(response, context: context)
            let haikuCount = haikuResult.entries.filter({ $0.reviewMetadata.isImportable }).count
            appDebugLog("📡 [Scan] Haiku: \(haikuCount) entries")

            // ── Doppel-Analyse: Sonnet immer nachschieben, Ergebnisse mergen ──
            guard let fallbackClient else { return haikuResult }

            let sonnetStart = CFAbsoluteTimeGetCurrent()
            do {
                let sonnetResponse = try await fallbackClient.analyze(payload)
                logTiming("ai_sonnet_verify", start: sonnetStart)
                let sonnetResult = mapResponse(sonnetResponse, context: context)
                let sonnetCount = sonnetResult.entries.filter({ $0.reviewMetadata.isImportable }).count
                appDebugLog("📡 [Scan] Sonnet: \(sonnetCount) entries")

                // Merge: Sonnet als Basis, Haiku-Einträge ergänzen die Sonnet nicht hat
                let merged = mergedEntries(primary: sonnetResult, secondary: haikuResult)
                let mergedCount = merged.filter({ $0.reviewMetadata.isImportable }).count
                appDebugLog("📡 [Scan] ✅ Merged: \(mergedCount) entries (Haiku \(haikuCount) + Sonnet \(sonnetCount))")

                return ScanProviderResult(
                    documentType: sonnetResult.documentType,
                    path: sonnetResult.path,
                    mode: sonnetResult.mode,
                    sourceLanguage: sonnetResult.sourceLanguage,
                    entries: merged,
                    blocks: sonnetResult.blocks,
                    warnings: sonnetResult.warnings,
                    summary: "\(mergedCount) Vokabelpaare erkannt (Doppel-Analyse).",
                    importMessage: "\(mergedCount) Einträge bereit zum Import.",
                    confidence: max(sonnetResult.confidence, haikuResult.confidence),
                    usedColumnPairing: sonnetResult.usedColumnPairing,
                    recognizedLineCount: max(sonnetResult.recognizedLineCount, haikuResult.recognizedLineCount),
                    recognizedBoxes: context?.primaryResult?.recognizedBoxes ?? []
                )
            } catch {
                appDebugLog("📡 [Scan] ⚠️ Sonnet verify failed: \(error.localizedDescription), using Haiku only")
                return haikuResult
            }
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

    /// Merge entries from two results: primary wins on duplicates, secondary fills gaps
    func mergedEntries(primary: ScanProviderResult, secondary: ScanProviderResult) -> [ScanExtractionEntry] {
        var result = primary.entries
        let primaryKeys = Set(primary.entries.map { normalizedMergeKey($0.source, $0.target) })

        for entry in secondary.entries {
            let key = normalizedMergeKey(entry.source, entry.target)
            if !primaryKeys.contains(key) {
                result.append(entry)
            }
        }

        return result
    }

    private func normalizedMergeKey(_ source: String, _ target: String) -> String {
        let s = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let t = target.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(s)|\(t)"
    }
}
