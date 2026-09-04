import Foundation

protocol ScanAIClient {
    var isAvailable: Bool { get }
    func analyze(_ payload: ScanAIRequestPayload) async throws -> ScanAIResponsePayload
}

struct UnavailableScanAIClient: ScanAIClient {
    var isAvailable: Bool { false }

    func analyze(_ payload: ScanAIRequestPayload) async throws -> ScanAIResponsePayload {
        throw ScanAIProviderError.unavailable
    }
}

enum ScanAIProviderError: Error {
    case unavailable
    case invalidImage
    case invalidEndpoint
    case invalidResponse
    case timedOut
    /// **Backend-Proxy (Phase 1.5)** — Tageslimit des Scan-Vision-Proxy
    /// erreicht (HTTP 429, `scan_daily_limit_exceeded`). Eigener Case,
    /// damit die UI eine klare Limit-Meldung zeigen kann statt eines
    /// generischen HTTP-Fehlers.
    case rateLimitExceeded
    case httpFailure(Int, String)
}
