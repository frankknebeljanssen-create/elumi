import Foundation

extension AIScanProvider {
    func warningCode(for error: Error) -> String {
        guard let providerError = error as? ScanAIProviderError else {
            return "ai_analysis_failed"
        }

        switch providerError {
        case .unavailable:
            return "ai_provider_unavailable"
        case .invalidImage:
            return "ai_invalid_image"
        case .invalidEndpoint:
            return "ai_invalid_endpoint"
        case .invalidResponse:
            return "ai_invalid_response"
        case .timedOut:
            return "ai_timeout"
        case .rateLimitExceeded:
            return "scan_daily_limit_exceeded"
        case .httpFailure(let code, _):
            return "ai_http_\(code)"
        }
    }

    func userFacingFailureMessage(for error: Error) -> String {
        guard let providerError = error as? ScanAIProviderError else {
            return "GPT ist fehlgeschlagen. Bitte nochmal versuchen."
        }

        switch providerError {
        case .unavailable:
            return "GPT ist noch nicht verbunden. Bitte nochmal versuchen."
        case .invalidImage:
            return "GPT konnte dieses Bild nicht lesen. Bitte nochmal versuchen."
        case .invalidEndpoint, .invalidResponse:
            return "GPT hat keine gültige Antwort geliefert. Bitte nochmal versuchen."
        case .timedOut:
            return "GPT hat zu lange gebraucht. Bitte nochmal versuchen."
        case .rateLimitExceeded:
            return "Tägliches Scan-Limit erreicht (100 pro Tag). Morgen wieder verfügbar."
        case .httpFailure(let code, let message):
            switch code {
            case 401:
                return "Der Scan-Dienst hat die Anfrage abgelehnt. Bitte später erneut versuchen."
            case 429:
                return "GPT-Limit erreicht. Bitte später nochmal versuchen."
            case 400:
                let sanitizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
                if sanitizedMessage.isEmpty {
                    return "GPT-Request wurde abgelehnt. Bitte nochmal versuchen."
                }
                return "GPT-Request wurde abgelehnt: \(sanitizedMessage)"
            default:
                return "GPT-Analyse fehlgeschlagen (\(code)). Bitte nochmal versuchen."
            }
        }
    }

    func shouldRetry(after error: Error) -> Bool {
        guard let providerError = error as? ScanAIProviderError else {
            return false
        }

        switch providerError {
        case .timedOut:
            return true
        case .httpFailure(let code, _):
            return code == 408 || code == 504 || code == 524
        case .rateLimitExceeded, .unavailable, .invalidImage, .invalidEndpoint, .invalidResponse:
            return false
        }
    }

    func unavailableResult(
        for request: ScanRequest,
        context: ScanProviderContext?
    ) -> ScanProviderResult {
        failureResult(
            for: request,
            context: context,
            warning: "ai_provider_unavailable",
            importMessage: "Die KI-Analyse ist gerade nicht verfügbar. Bitte nochmal versuchen."
        )
    }

    func failureResult(
        for request: ScanRequest,
        context: ScanProviderContext?,
        warning: String,
        importMessage: String
    ) -> ScanProviderResult {
        ScanProviderResult(
            documentType: context?.primaryResult?.documentType ?? .unknown,
            path: context?.primaryResult == nil ? .aiAssisted : .hybrid,
            mode: request.preferredMode ?? context?.primaryResult?.mode ?? .list,
            sourceLanguage: request.sourceLanguage,
            entries: [],
            blocks: [],
            warnings: [warning],
            summary: "",
            importMessage: importMessage,
            confidence: 0,
            usedColumnPairing: context?.primaryResult?.usedColumnPairing ?? false,
            recognizedLineCount: context?.primaryResult?.recognizedLineCount ?? 0,
            recognizedBoxes: context?.primaryResult?.recognizedBoxes ?? []
        )
    }

    func logTiming(_ label: String, start: CFAbsoluteTime) {
        #if DEBUG
        let elapsedMS = Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded())
        NSLog("[ScanTiming] %@: %dms", label, elapsedMS)
        #endif
    }

    func logDebug(_ label: String) {
        #if DEBUG
        NSLog("[ScanTiming] %@", label)
        #endif
    }
}
