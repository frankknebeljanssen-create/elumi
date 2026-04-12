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
            "temperature": 0,
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
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = body

        let bodyKB = body.count / 1024
        print("📡 [Scan] API request [haiku-vision]: model=\(model) payload=\(bodyKB)KB timeout=45s")
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
        var jsonText = outputText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Fix known OCR/vision misreads in the raw JSON
        for (wrong, correct) in Self.knownVisionCorrections {
            jsonText = jsonText.replacingOccurrences(of: "\"\(wrong)\"", with: "\"\(correct)\"")
        }

        // Debug: check if "ou" appears as a standalone source entry in raw response
        if jsonText.range(of: #""source"\s*:\s*"ou""#, options: .regularExpression) != nil {
            print("📡 [Scan] ✅ 'ou' FOUND as entry in raw Haiku output")
        } else if jsonText.range(of: #""source"\s*:\s*"où""#, options: .regularExpression) != nil {
            print("📡 [Scan] ✅ 'où' FOUND as entry in raw Haiku output")
        } else {
            print("📡 [Scan] ❌ 'ou/où' NOT found as entry — Haiku didn't extract it")
        }

        do {
            let scanResult = try JSONDecoder().decode(OpenAIScanSchemaResponse.self, from: Data(jsonText.utf8))
            print("📡 [Scan] Haiku entries (\(scanResult.entries.count)):")
            for (i, e) in scanResult.entries.enumerated() {
                print("   \(i+1). \(e.source) → \(e.target)")
            }
            return scanResult.toPayload()
        } catch {
            print("📡 [Scan] ❌ JSON decode failed: \(error)")
            print("📡 [Scan] Raw response (first 500 chars): \(String(jsonText.prefix(500)))")
            throw ScanAIProviderError.invalidResponse
        }
    }

    /// Known vision/OCR misreads — corrected in raw JSON before decode
    private static let knownVisionCorrections: [(wrong: String, correct: String)] = [
        ("mah", "mais"),
        ("paa", "pas"),
        ("moi5", "mois"),
    ]

    // Also support text-only for compatibility (just pass through)
    func analyzeTextOnly(_ payload: ScanAIRequestPayload) async throws -> ScanAIResponsePayload {
        // Haiku Vision doesn't need a text-only path — always use the image
        try await analyze(payload)
    }

    private func buildPrompt(ocrContext: ScanAIContextSnapshot?) -> String {
        var prompt = scanPrompt
        // Only include OCR context if it's high quality (enough lines detected)
        if let context = ocrContext, context.recognizedLines.count >= 10 {
            let lines = context.recognizedLines.prefix(50).joined(separator: "\n")
            prompt += """

            \n\nOCR-Referenz (erkannte Zeilen). Nutze dies NUR als Checkliste — nicht als Textquelle.
            WICHTIG: Vertraue bei Konflikten DEINER eigenen Bilderkennung, NICHT dem OCR-Text.
            OCR kann Buchstaben falsch lesen (z.B. "mais" als "mah", "ou" als etwas anderes).
            Lies die Wörter IMMER selbst vom Bild ab.
            ACHTUNG: Nicht alle Zeilen sind Vokabeln! Ignoriere Beispielsätze, Dialoge, Grammatik-Erklärungen und Überschriften.
            Extrahiere NUR echte Vokabelpaare die SICHTBAR auf dem Bild stehen — NIEMALS Wörter erfinden:
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

        *** ARTIKEL-REGEL ***
        Wenn im Buch ein Artikel vor dem Wort steht (le, la, l', les), übernimm ihn EXAKT so in den source-Eintrag.
        Ergänze KEINEN Artikel wenn keiner sichtbar ist.
        Entferne KEINEN Artikel der sichtbar ist.
        ***

        REGEL 1 – Was eine Vokabelzeile ist:
        Eine Vokabelzeile hat die Struktur: französischer Begriff [Lautschrift] Grammatikangabe → deutsche Übersetzung.
        Extrahiere NUR Zeilen die dieses Muster haben. Die 3. Spalte (Beispielsätze/Dialoge) vollständig ignorieren.
        Auch sehr kurze Einträge zählen: "ah" → "ach, ach so", "et" → "und", "toi" → "du"
        Artikel: siehe ARTIKEL-REGEL oben.

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
        - Die DRITTE SPALTE (Beispielsätze/Dialoge) wird KOMPLETT ignoriert.
          Erkennungszeichen: Fettgedruckte französische Wörter mitten im Satz,
          oder mehrere französische Wörter hintereinander ohne deutsche Übersetzung daneben.
          Niemals einen Eintrag aus der dritten Spalte extrahieren.

        REGEL 4 – Satzzeichen sind bedeutungstragend:
        "Ça va?" = "Wie geht's?" / "Geht's dir gut?" (FRAGE – NIEMALS "Es geht mir gut")
        "Ça va." = "Es geht mir gut." (AUSSAGE – NIEMALS "Wie geht's?")
        "Et toi?" → "Und du?" und "Et toi?" → "Und dir?" = 2 VERSCHIEDENE Einträge.
        Wenn dasselbe französische Wort in verschiedenen Sektionen mit verschiedenen Übersetzungen vorkommt, BEIDE extrahieren.
        Niemals auf Basis gleicher Quellform zusammenfassen oder weglassen.
        Das Präfix "hier:" im Buch bedeutet "in diesem Kontext" — nur den Teil NACH "hier:" als Übersetzung nehmen.

        REGEL 5 – Grammatikinfo als Typ:
        m./f. → Nomen, adj. → Adjektiv, adv. → Adverb, fam. → Ausdruck. Ohne Angabe → aus Kontext ableiten.

        REGEL 6 – Mehrfachübersetzungen:
        Wenn in einer Zeile mehrere deutsche Übersetzungen durch / oder , stehen:
        - Feste Wendung (z.B. "Na ja. / Es geht so.") → komplett übernehmen
        - Varianten (z.B. "ich heiße / mein Name ist") → NUR die ERSTE Übersetzung nehmen
        NIEMALS selbst Übersetzungen ergänzen die nicht in der Zeile stehen.

        REGEL 7 – Kulturpaare die Vokabeln sind:
        "Bienvenue!" → "Willkommen!" ist ein Vokabelpaar (klare FR→DE Struktur) → extrahieren.
        "la Tour Eiffel" in einem Beschreibungsblock ohne eigene Tabellenzeile → ignorieren.

        REGEL 8 – Symbole neben Text ignorieren:
        Farbpunkte, Symbole oder kleine Illustrationen NEBEN einer Textzeile bedeuten
        NICHT dass die Zeile kein Vokabeleintrag ist. Extrahiere den Text der Zeile
        unabhängig davon ob daneben ein Symbol, Farbpunkt oder Bild steht.
        Besonders betroffen: Farb-Vokabeln stehen oft neben einem Farbpunkt:
        le jaune (Gelb), le rouge (Rot), le bleu (Blau), le vert (Grün),
        le noir (Schwarz), le blanc (Weiß) — ALLE extrahieren, Farbpunkt ignorieren.
        Prüfe das Bild EXPLIZIT auf diese Farben — sie stehen oft als Reihe untereinander
        zwischen "la salade" und "les chats". Wenn du einen Farbpunkt siehst, steht LINKS
        davon immer ein Text wie "le jaune [ləʒon]" mit einer deutschen Übersetzung.

        REGEL 9 – NIEMALS halluzinieren:
        Extrahiere NUR Vokabeln die SICHTBAR auf dem Bild stehen.
        Erfinde KEINE Wörter, Übersetzungen oder Einträge die nicht im Bild sind.
        Im Zweifel lieber einen Eintrag weglassen als einen falschen erfinden.

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
