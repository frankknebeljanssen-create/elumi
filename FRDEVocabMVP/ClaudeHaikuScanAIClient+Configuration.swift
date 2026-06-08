import Foundation

extension ClaudeHaikuScanAIClient {
    /// Konstruiert den Scan-Client für den Backend-Proxy. Kein lokaler
    /// Schlüssel mehr nötig — die Auth läuft serverseitig. Das Modell
    /// kann optional via Env/Plist (`ANTHROPIC_SCAN_MODEL`) überschrieben
    /// werden; Default ist Haiku. Liefert nie `nil` (Optional-Signatur
    /// bleibt nur für Aufruf-Kompatibilität erhalten).
    static func fromEnvironment() -> ClaudeHaikuScanAIClient? {
        let environment = ProcessInfo.processInfo.environment
        let bundledInfo = Bundle.main.infoDictionary
        let bundledConfig = OpenAIResponsesScanAIClient.bundledOpenAIConfig()

        let model = OpenAIResponsesScanAIClient.resolvedConfigValue(
            environment["ANTHROPIC_SCAN_MODEL"],
            fallback: bundledInfo?["ANTHROPIC_SCAN_MODEL"] as? String,
            extraFallback: bundledConfig?["ANTHROPIC_SCAN_MODEL"] as? String
        ) ?? "claude-haiku-4-5-20251001"

        return ClaudeHaikuScanAIClient(model: model)
    }
}
