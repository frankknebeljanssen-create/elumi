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
                            "text": buildPrompt(ocrContext: payload.ocrContext)
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

    private func buildPrompt(ocrContext: ScanAIContextSnapshot?) -> String {
        var prompt = scanPrompt
        if let context = ocrContext, !context.recognizedLines.isEmpty {
            let lines = context.recognizedLines.prefix(50).joined(separator: "\n")
            prompt += """

            \n\nOCR-Referenz (erkannte Zeilen). Nutze dies um sicherzustellen dass du keine Vokabelzeile übersiehst.
            ACHTUNG: Nicht alle Zeilen sind Vokabeln! Ignoriere Beispielsätze, Dialoge, Grammatik-Erklärungen und Überschriften.
            Extrahiere NUR echte Vokabelpaare (Quellwort ↔ Übersetzung):
            \(lines)
            """
        }
        return prompt
    }

    private var scanPrompt: String {
        """
        Du bist ein Vokabel-Extraktor für Französisch-Deutsch Schulbuchseiten.

        *** PRIORITÄT 1 – WICHTIGSTE REGEL ***
        JEDE Tabellenzeile die in Spalte 2 eine deutsche Übersetzung hat ist ein Vokabeleintrag.
        Es spielt KEINE Rolle ob derselbe Begriff auch als Überschrift vorkommt.
        Entscheide AUSSCHLIESSLICH anhand der Tabellenstruktur, NICHT anhand von Überschriften.
        Beispiel: "C'est parti! [separti] fam." steht in einer Tabellenzeile mit "Los geht's!" in Spalte 2 → EXTRAHIEREN.
        ***

        REGEL 1 – Was eine Vokabelzeile ist:
        Eine Vokabelzeile hat die Struktur: französischer Begriff [Lautschrift] Grammatikangabe → deutsche Übersetzung.
        Extrahiere NUR Zeilen die dieses Muster haben. Die 3. Spalte (Beispielsätze/Dialoge) vollständig ignorieren.
        Auch sehr kurze Einträge zählen: "ah" → "ach, ach so", "et" → "und", "toi" → "du"

        REGEL 2 – Überschriften die auch Vokabeln sind:
        Wenn ein Begriff als Abschnittsüberschrift vorkommt UND gleichzeitig in einer Tabellenzeile darunter mit deutscher Übersetzung steht, ist er ein Vokabeleintrag → extrahieren.
        Beispiel: "C'est parti!" steht als Überschrift UND als erste Tabellenzeile mit "Los geht's!" → extrahieren.
        Die Überschrift selbst ignorieren, den Tabelleneintrag extrahieren.

        REGEL 3 – Was ignoriert wird:
        - Lautschrift in eckigen Klammern: [sava], [twa] → NICHT übernehmen
        - Grammatikabkürzungen: m., f., pl., adj., adv., fam., inv., inf. → NICHT übernehmen
        - Legendenseiten / Symbole-und-Abkürzungen-Blöcke → vollständig ignorieren
        - Seitenzahlen und Seitenbezeichnungen ("cent-soixante-seize") → ignorieren
        - Kulturinfo-Blöcke mit beschreibendem Fließtext → ignorieren
        - Grammatiknotizen am Seitenende → ignorieren
        - Zeichnungen, Bilder, Symbole → ignorieren

        REGEL 4 – Satzzeichen sind bedeutungstragend:
        "Ça va?" (Frage) und "Ça va." (Aussage) = 2 VERSCHIEDENE Einträge.
        "Et toi?" → "Und du?" und "Et toi?" → "Und dir?" = 2 VERSCHIEDENE Einträge.
        Niemals auf Basis gleicher Quellform zusammenfassen oder weglassen.

        REGEL 5 – Grammatikinfo als Typ:
        m./f. → Nomen, adj. → Adjektiv, adv. → Adverb, fam. → Ausdruck. Ohne Angabe → aus Kontext ableiten.

        REGEL 6 – Mehrfachübersetzungen:
        Mehrere deutsche Bedeutungen in einer Zeile getrennt durch / oder , (z.B. "Na ja. / Es geht so.") als EINE Übersetzung komplett übernehmen — NICHT als zwei Einträge splitten.

        REGEL 7 – Kulturpaare die Vokabeln sind:
        "Bienvenue!" → "Willkommen!" ist ein Vokabelpaar (klare FR→DE Struktur) → extrahieren.
        "la Tour Eiffel" in einem Beschreibungsblock ohne eigene Tabellenzeile → ignorieren.

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
