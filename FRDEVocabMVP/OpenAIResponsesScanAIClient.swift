import Foundation

struct OpenAIResponsesScanAIClient: ScanAIClient {
    let apiKey: String
    let model: String
    let session: URLSession

    init(
        apiKey: String,
        model: String = "gpt-5-mini",
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.session = session
    }

    var isAvailable: Bool {
        !apiKey.isEmpty
    }

    func analyze(_ payload: ScanAIRequestPayload) async throws -> ScanAIResponsePayload {
        guard let url = URL(string: "https://api.openai.com/v1/responses") else {
            throw ScanAIProviderError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body = try JSONSerialization.data(withJSONObject: makeRequestBody(from: payload))
        request.httpBody = body
        let bodyKB = body.count / 1024
        print("📡 [Scan] API request: model=\(model) payload=\(bodyKB)KB timeout=\(Int(request.timeoutInterval))s")
        let apiStart = CFAbsoluteTimeGetCurrent()

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
            print("📡 [Scan] API response: \(Int((CFAbsoluteTimeGetCurrent() - apiStart) * 1000))ms")
        } catch let urlError as URLError where urlError.code == .timedOut {
            print("📡 [Scan] ❌ TIMEOUT after \(Int((CFAbsoluteTimeGetCurrent() - apiStart) * 1000))ms")
            throw ScanAIProviderError.timedOut
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScanAIProviderError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let message = parseAPIErrorMessage(from: data)
            throw ScanAIProviderError.httpFailure(httpResponse.statusCode, message)
        }

        let envelope = try JSONDecoder().decode(OpenAIResponsesEnvelope.self, from: data)
        guard let outputText = envelope.firstOutputText else {
            throw ScanAIProviderError.invalidResponse
        }

        let scanResult = try JSONDecoder().decode(OpenAIScanSchemaResponse.self, from: Data(outputText.utf8))
        return scanResult.toPayload()
    }
}
