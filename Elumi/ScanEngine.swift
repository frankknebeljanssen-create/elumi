import Foundation

final class ScanAnalysisEngine {
    let preflightProvider: ScanProvider?
    let primaryProvider: ScanProvider
    let fallbackProviders: [ScanProvider]

    typealias ProgressHandler = @Sendable (ScanRuntimeStage) async -> Void

    init(
        preflightProvider: ScanProvider? = nil,
        primaryProvider: ScanProvider,
        fallbackProviders: [ScanProvider] = []
    ) {
        self.preflightProvider = preflightProvider
        self.primaryProvider = primaryProvider
        self.fallbackProviders = fallbackProviders
    }
}
