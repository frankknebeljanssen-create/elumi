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
    case httpFailure(Int, String)
}
