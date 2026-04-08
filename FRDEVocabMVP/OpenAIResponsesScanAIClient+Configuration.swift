import Foundation

extension OpenAIResponsesScanAIClient {
    static func fromEnvironment() -> OpenAIResponsesScanAIClient? {
        let environment = ProcessInfo.processInfo.environment
        let bundledInfo = Bundle.main.infoDictionary
        let bundledConfig = bundledOpenAIConfig()

        guard let key = resolvedConfigValue(
            environment["OPENAI_API_KEY"],
            fallback: bundledInfo?["OPENAI_API_KEY"] as? String,
            extraFallback: bundledConfig?["OPENAI_API_KEY"] as? String
        ) else {
            return nil
        }

        let model = resolvedConfigValue(
            environment["OPENAI_SCAN_MODEL"],
            fallback: bundledInfo?["OPENAI_SCAN_MODEL"] as? String,
            extraFallback: bundledConfig?["OPENAI_SCAN_MODEL"] as? String
        ) ?? "gpt-5-mini"

        return OpenAIResponsesScanAIClient(apiKey: key, model: model)
    }

    static func resolvedConfigValue(
        _ environmentValue: String?,
        fallback bundledValue: String?,
        extraFallback resourceValue: String? = nil
    ) -> String? {
        sanitizedConfigValue(environmentValue)
        ?? sanitizedConfigValue(bundledValue)
        ?? sanitizedConfigValue(resourceValue)
    }

    static func bundledOpenAIConfig() -> [String: Any]? {
        guard
            let url = Bundle.main.url(forResource: "OpenAIConfig", withExtension: "plist"),
            let data = try? Data(contentsOf: url),
            let object = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            return nil
        }

        return object
    }

    static func sanitizedConfigValue(_ rawValue: String?) -> String? {
        guard let trimmed = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        if trimmed.hasPrefix("$(") && trimmed.hasSuffix(")") {
            return nil
        }

        if trimmed == "REPLACE_WITH_OPENAI_API_KEY" ||
            trimmed == "REPLACE_WITH_OPENAI_SCAN_MODEL" ||
            trimmed.hasPrefix("YOUR_") ||
            trimmed.hasPrefix("REPLACE_") {
            return nil
        }

        return trimmed
    }
}
