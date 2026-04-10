import Foundation

/// Scan AI client using Claude Haiku Vision via Anthropic Messages API.
/// Single-step: image → vocabulary pairs. No OCR needed.
struct ClaudeHaikuScanAIClient: ScanAIClient {
    let apiKey: String
    let model: String
    let session: URLSession

    init(
        apiKey: String,
        model: String = "claude-haiku-4-5-20251001",
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
        guard let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            throw ScanAIProviderError.invalidEndpoint
        }

        let base64Image = payload.imageJPEGData.base64EncodedString()

        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 4096,
            "messages": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/jpeg",
                                "data": base64Image
                            ]
                        ],
                        [
                            "type": "text",
                            "text": scanPrompt
                        ]
                    ]
                ]
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = body

        let bodyKB = body.count / 1024
        print("📡 [Scan] API request [haiku-vision]: model=\(model) payload=\(bodyKB)KB timeout=30s")
        let apiStart = CFAbsoluteTimeGetCurrent()

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
            print("📡 [Scan] API response [haiku-vision]: \(Int((CFAbsoluteTimeGetCurrent() - apiStart) * 1000))ms")
        } catch let urlError as URLError where urlError.code == .timedOut {
            print("📡 [Scan] ❌ TIMEOUT [haiku-vision] after \(Int((CFAbsoluteTimeGetCurrent() - apiStart) * 1000))ms")
            throw ScanAIProviderError.timedOut
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScanAIProviderError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorText = String(data: data, encoding: .utf8) ?? "unknown"
            print("📡 [Scan] ❌ HTTP \(httpResponse.statusCode): \(errorText.prefix(200))")
            throw ScanAIProviderError.httpFailure(httpResponse.statusCode, errorText)
        }

        // Anthropic response: { "content": [{ "type": "text", "text": "..." }] }
        let envelope = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        guard let outputText = envelope.firstText else {
            throw ScanAIProviderError.invalidResponse
        }

        // Claude might wrap JSON in ```json ... ``` — strip it
        let jsonText = outputText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let scanResult = try JSONDecoder().decode(OpenAIScanSchemaResponse.self, from: Data(jsonText.utf8))
            return scanResult.toPayload()
        } catch {
            print("📡 [Scan] ❌ JSON decode failed: \(error)")
            print("📡 [Scan] Raw response (first 500 chars): \(String(jsonText.prefix(500)))")
            throw ScanAIProviderError.invalidResponse
        }
    }

    // Also support text-only for compatibility (just pass through)
    func analyzeTextOnly(_ payload: ScanAIRequestPayload) async throws -> ScanAIResponsePayload {
        // Haiku Vision doesn't need a text-only path — always use the image
        try await analyze(payload)
    }

    private var scanPrompt: String {
        """
        Du bist ein präziser Vokabel-Extraktor für Deutsch-Französisch Lernmaterial.

        Analysiere dieses Bild einer Schulbuchseite oder eines Vokabelhefts.
        EXTRAHIERE ALLE echte Vokabelpaare (Französisch ↔ Deutsch).

        COMPLETENESS ist kritisch: Extrahiere JEDES Paar, egal wie kurz.
        Auch einzelne Wörter wie "toi" = "du" oder "et" = "und" MÜSSEN enthalten sein.
        Auch Fragen wie "Tu t'appelles comment?" = "Wie heißt du?" extrahieren.

        IGNORIERE:
        - Seitenzahlen, Überschriften, Kapitelbezeichnungen
        - Lautschrift in eckigen Klammern [ʃ], [ɔ̃]
        - Grammatikregeln als Fließtext
        - Zeichnungen, Symbole

        BEACHTE:
        - Bei Nomen: Artikel miterfassen (fr: "la maison", de: "das Haus")
        - Bei Verben: Infinitiv erfassen
        - Satzzeichen bewahren: ? ! . sind bedeutungsrelevant
        - Gleiches Quellwort mit verschiedenen Übersetzungen: EINE Zeile mit " / " getrennt
        - "Ça va?" (Frage) und "Ça va." (Aussage) sind SEPARATE Einträge

        Antworte AUSSCHLIESSLICH mit validem JSON (kein Markdown, keine Codeblöcke):

        {
          "document_type": "vocabularyList",
          "mode": "list",
          "source_language": "Französisch",
          "entries": [
            {
              "source": "la maison",
              "target": "das Haus",
              "card_type": "words",
              "source_phonetic": "",
              "target_phonetic": "",
              "confidence": 0.95,
              "learning_category": null,
              "note": null,
              "is_importable": true,
              "notes": []
            }
          ],
          "warnings": [],
          "summary": "15 Vokabelpaare erkannt.",
          "import_message": "15 Einträge bereit zum Import.",
          "confidence": 0.9,
          "used_column_pairing": false,
          "recognized_line_count": 30
        }

        document_type: "vocabularyList" | "freeText" | "textbookTable" | "mixedLayout" | "unknown"
        card_type: "words" | "phrases"
        source_language: "Französisch"
        """
    }
}

// Anthropic Messages API response envelope
struct AnthropicMessagesResponse: Decodable {
    let content: [ContentBlock]

    var firstText: String? {
        content.first(where: { $0.type == "text" })?.text
    }

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}
