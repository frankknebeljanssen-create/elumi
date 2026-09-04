import Foundation

extension ScanSessionController {
    func updateProviderDebugInfo(
        result: ScanProviderResult,
        aiConfigured: Bool,
        durationMS: Int
    ) {
        lastScanAIConfigured = aiConfigured
        lastScanWarnings = result.warnings
        lastScanImportDebugMessage = result.importMessage
        lastScanDurationMS = durationMS
    }

    func updateEvalReport(for result: ScanProviderResult) {
        guard let selectedImageSourcePath else {
            scanEvalSuiteReport = nil
            return
        }

        let matchingFixtures = ScanEvaluationFixtures.matchingFixtures(forImagePath: selectedImageSourcePath)
        guard !matchingFixtures.isEmpty else {
            scanEvalSuiteReport = nil
            return
        }

        scanEvalSuiteReport = ScanEvaluationHarness.evaluate(
            result,
            matchingFixtureImagePath: selectedImageSourcePath
        )
    }
}
