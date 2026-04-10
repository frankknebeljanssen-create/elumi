import Foundation

extension ClaudeHaikuScanAIClient {
    static func fromEnvironment() -> ClaudeHaikuScanAIClient? {
        let environment = ProcessInfo.processInfo.environment
        let bundledInfo = Bundle.main.infoDictionary
        let bundledConfig = OpenAIResponsesScanAIClient.bundledOpenAIConfig()

        guard let key = OpenAIResponsesScanAIClient.resolvedConfigValue(
            environment["ANTHROPIC_API_KEY"],
            fallback: bundledInfo?["ANTHROPIC_API_KEY"] as? String,
            extraFallback: bundledConfig?["ANTHROPIC_API_KEY"] as? String
        ) else {
            return nil
        }

        let model = OpenAIResponsesScanAIClient.resolvedConfigValue(
            environment["ANTHROPIC_SCAN_MODEL"],
            fallback: bundledInfo?["ANTHROPIC_SCAN_MODEL"] as? String,
            extraFallback: bundledConfig?["ANTHROPIC_SCAN_MODEL"] as? String
        ) ?? "claude-haiku-4-5-20251001"

        return ClaudeHaikuScanAIClient(apiKey: key, model: model)
    }
}
