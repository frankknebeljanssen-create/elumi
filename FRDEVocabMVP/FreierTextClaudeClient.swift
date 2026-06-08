import Foundation
import UIKit

/// Claude-Vision-Client speziell für den „Freier Text"-Flow.
///
/// Bewusst **nicht** an den `ClaudeHaikuScanAIClient` gekoppelt — der
/// Vokabel-Scan-Client ist auf Tabellenpaare optimiert (eigenes Schema
/// `OpenAIScanSchemaResponse`, `scanPrompt`, Post-Processing-Heuristiken
/// für OCR-Misreads in FR/DE-Paaren). Freier Text braucht ein anderes
/// Prompt (lexikalische Analyse statt Paar-Extraktion) und ein anderes
/// Response-Schema (`FreeTextResult`). Ein Mischen würde die beiden
/// Flows schwerer wartbar machen — dieser Client hat **genau eine**
/// Aufgabe: Bild → FreeTextResult.
///
/// Das Envelope-Decoding (`AnthropicMessagesResponse`) stammt aus dem
/// Scan-Client; Wiederverwendung ist OK, weil das nur das API-
/// Transport-Format der Messages-API beschreibt und keinerlei
/// Domain-Wissen enthält.
struct FreierTextClaudeClient {
    let model: String
    let maxTokens: Int
    let session: URLSession

    init(
        model: String = "claude-haiku-4-5-20251001",
        maxTokens: Int = 8192,
        session: URLSession = .shared
    ) {
        self.model = model
        self.maxTokens = maxTokens
        self.session = session
    }

    /// Konfigurations-Factory für den Backend-Proxy. Kein lokaler
    /// Schlüssel mehr nötig — die Auth läuft serverseitig. Das Modell
    /// kann optional via Env/Plist (`ANTHROPIC_FREETEXT_MODEL`)
    /// überschrieben werden; Default ist Haiku. Liefert nie `nil`
    /// (Optional-Signatur bleibt nur für Aufruf-Kompatibilität).
    static func fromEnvironment() -> FreierTextClaudeClient? {
        let environment = ProcessInfo.processInfo.environment
        let bundledInfo = Bundle.main.infoDictionary
        let bundledConfig = OpenAIResponsesScanAIClient.bundledOpenAIConfig()

        let model = OpenAIResponsesScanAIClient.resolvedConfigValue(
            environment["ANTHROPIC_FREETEXT_MODEL"],
            fallback: bundledInfo?["ANTHROPIC_FREETEXT_MODEL"] as? String,
            extraFallback: bundledConfig?["ANTHROPIC_FREETEXT_MODEL"] as? String
        ) ?? "claude-haiku-4-5-20251001"

        return FreierTextClaudeClient(model: model)
    }

    /// Hauptflow: `UIImage` → komprimiertes JPEG → Base64 → Messages-API
    /// → `FreeTextResult`. Fehlerpfad wirft `FreierTextError`, die View
    /// mappt auf die user-facing Texte aus der Spezifikation.
    func analyze(image: UIImage) async throws -> FreeTextResult {
        // **Backend-Proxy (Phase 1.5)** — kein Anthropic-Key mehr im
        // Client; die Auth läuft über Anon-Key + Device-Token gegen den
        // Scan-Vision-Proxy. Der frühere `guard !apiKey.isEmpty`-Check
        // entfällt damit.

        // Bild auf ~1 MB JPEG komprimieren. Vision-APIs tolerieren deutlich
        // größere Payloads, aber wir halten Latency & Mobile-Data-Verbrauch
        // in Grenzen — ~1 MB ist der Sweet-Spot aus Vokabel-Scan-Erfahrung.
        guard let jpegData = Self.compressToJPEG(image: image, targetBytes: 1_000_000) else {
            throw FreierTextError.invalidImage
        }

        let base64Image = jpegData.base64EncodedString()
        let prompt = Self.freeTextPrompt

        // **Backend-Proxy (Phase 1.5)** — Body minimal: `max_tokens`,
        // `temperature` und `stream` setzt der Proxy serverseitig fix.
        // `telemetry_hint` trennt den Freier-Text-Pfad in der Backend-
        // Telemetrie vom Vokabel-Scan ab (kein PII).
        let requestBody: [String: Any] = [
            "model": model,
            "telemetry_hint": "scan_freetext",
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
                            "text": prompt
                        ]
                    ]
                ]
            ]
        ]

        let url = ChatConfig.scanBackendURL

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Auth analog Léa-Chat: Anon-Key + Device-Token, kein Anthropic-Key.
        request.setValue("Bearer \(ChatConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(DeviceTokenManager.getOrCreateToken(), forHTTPHeaderField: "X-Device-Token")
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        let bodyKB = (request.httpBody?.count ?? 0) / 1024
        appDebugLog("🧠 [FreeText] AI analysis started")
        appDebugLog("📄 [FreierText] API request: model=\(model) payload=\(bodyKB)KB timeout=60s")
        let apiStart = CFAbsoluteTimeGetCurrent()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            appDebugLog("📄 [FreierText] ❌ network error: \(error.localizedDescription)")
            throw FreierTextError.networkFailure(underlying: error)
        }
        appDebugLog("📄 [FreierText] API response: \(Int((CFAbsoluteTimeGetCurrent() - apiStart) * 1000))ms")

        guard let http = response as? HTTPURLResponse else {
            throw FreierTextError.invalidResponse
        }
        guard 200..<300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? "<binary>"
            appDebugLog("📄 [FreierText] ❌ HTTP \(http.statusCode): \(body.prefix(300))")
            throw FreierTextError.httpFailure(statusCode: http.statusCode, body: body)
        }

        let envelope: AnthropicMessagesResponse
        do {
            envelope = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        } catch {
            throw FreierTextError.decodeFailure(underlying: error)
        }

        guard let rawText = envelope.firstText else {
            throw FreierTextError.invalidResponse
        }

        // Claude umwickelt JSON gelegentlich in ```json … ```. Stripping
        // parallel zum Scan-Client — robust gegenüber beiden Varianten.
        let jsonText = rawText
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let decoder = JSONDecoder()
            // `is_foreign` → `isForeign`. `.convertFromSnakeCase` macht
            // das global — die `CodingKeys` in den Entry-Structs sind
            // trotzdem explizit, damit die auto-generierten ID-Felder
            // nicht aus dem JSON zu decoden versucht werden.
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let result = try decoder.decode(FreeTextResult.self, from: Data(jsonText.utf8))
            appDebugLog("📄 [FreierText] ✅ parsed language=\(result.language) entries=\(result.totalEntryCount)")
            appDebugLog("🧠 [FreeText] AI analysis finished — entries=\(result.totalEntryCount)")
            return result
        } catch {
            appDebugLog("📄 [FreierText] ❌ JSON decode failed: \(error)")
            appDebugLog("📄 [FreierText] Raw (first 500): \(String(jsonText.prefix(500)))")
            throw FreierTextError.decodeFailure(underlying: error)
        }
    }

    /// Komprimiert ein `UIImage` iterativ zu JPEG unter `targetBytes`.
    /// Strategie: zuerst Auflösung deckeln (longEdge ≤ 1600 px), dann
    /// Qualität schrittweise reduzieren bis das Ziel-Byte-Budget
    /// erreicht ist. Liefert `nil`, wenn selbst bei 0.3 Qualität noch zu
    /// groß — in der Praxis extrem selten nach dem Resize.
    static func compressToJPEG(image: UIImage, targetBytes: Int, maxLongEdge: CGFloat = 1600) -> Data? {
        let resized = Self.resized(image: image, maxLongEdge: maxLongEdge)

        // Schnell-Pfad: 0.85 trifft bei normalen Fotos meist schon das Ziel.
        let qualities: [CGFloat] = [0.85, 0.75, 0.65, 0.55, 0.45, 0.35]
        for quality in qualities {
            guard let data = resized.jpegData(compressionQuality: quality) else { continue }
            if data.count <= targetBytes {
                appDebugLog("📄 [FreierText] compress ok quality=\(quality) bytes=\(data.count)")
                return data
            }
        }
        // Fallback: letzte Stufe zurückgeben auch wenn über Budget —
        // besser ein größeres Bild senden als gar nichts.
        let fallback = resized.jpegData(compressionQuality: 0.35)
        if let data = fallback {
            appDebugLog("📄 [FreierText] ⚠️ compress over target, sending \(data.count) bytes")
        }
        return fallback
    }

    /// Skaliert so, dass die längere Kante ≤ `maxLongEdge` ist. Wenn das
    /// Bild kleiner ist, wird es unverändert zurückgegeben — kein
    /// Upscaling, kein Qualitätsverlust durch Re-Draw.
    private static func resized(image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge else { return image }
        let scale = maxLongEdge / longEdge
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1 // wir geben selbst die Pixel-Größe vor
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    /// Das Prompt ist in Deutsch formuliert, weil Claude in seiner
    /// Response die erkannte Sprache als **deutschen** Namen liefern
    /// muss (z. B. „Französisch" — nicht „French"), damit die
    /// Result-View den String 1:1 im Header zeigen kann.
    ///
    /// Die JSON-Struktur ist exakt auf `FreeTextResult` abgestimmt.
    /// Jede Änderung am Prompt muss mit dem Model synchronisiert
    /// werden — sonst schlägt der Decode fehl und der Nutzer landet
    /// in der Fehler-Alert.
    ///
    /// Übersetzungsrichtung: Die App ist für FR↔DE-Lerner. Wenn der
    /// erkannte Text Deutsch ist, muss die Übersetzung ins Französische
    /// gehen (nicht de→de). Für alle anderen Sprachen → Deutsch.
    private static let freeTextPrompt: String = """
    Du bist ein Sprachanalyse-Assistent. Analysiere den auf dem Bild sichtbaren Text und liefere eine strukturierte Antwort mit drei Teilen: Originaltext, Übersetzung, Wortlisten nach Wortart.

    AUFGABE:
    1. Erkenne die dominierende Sprache des Textes (z. B. „Französisch", „Englisch", „Deutsch", „Spanisch", „Italienisch"). Nutze den deutschen Sprachnamen.

    2. Extrahiere den Originaltext als zusammenhängende Zeichenfolge in Lesereihenfolge (Feld `original_text`). Erhalte Zeilenumbrüche mit „\\n", wenn sie dem Layout entsprechen, ansonsten ein Leerzeichen.

    3. ÜBERSETZUNGSRICHTUNG — die App ist für Französisch↔Deutsch-Lerner:
       - Wenn der erkannte Text auf **Deutsch** ist: übersetze den kompletten Text flüssig ins **Französische**.
       - In **allen anderen Fällen** (Französisch, Englisch, Spanisch, Italienisch, …): übersetze den kompletten Text flüssig ins **Deutsche**.
       Schreibe die Übersetzung ins Feld `translation`. Keine wortwörtliche Gloss-Übersetzung — natürlich formulierter Zielsprachen-Text, der den Sinn wiedergibt. Behalte dieselbe Zeilenstruktur wie im Originaltext.

    4. Extrahiere ALLE inhaltstragenden Wörter und gruppiere sie nach Wortart in acht Kategorien: `nomen`, `verben`, `adjektive`, `adverbien`, `pronomen`, `praepositionen`, `konjunktionen`, `sonstige`.
       - `pronomen` enthält Personal-, Possessiv-, Demonstrativ-, Relativ- und Interrogativpronomen.
       - `praepositionen` enthält einfache und zusammengesetzte Präpositionen (à, de, dans, auf, wegen, …).
       - `konjunktionen` enthält nebenordnende (et, ou, und, aber) und unterordnende Konjunktionen (que, weil, obwohl).
       - `sonstige` enthält Interjektionen, Partikeln, Zahlwörter und alles, was in keine der obigen Kategorien passt.
       - Artikel (le, la, the, der, die, das …) NICHT als eigene Einträge listen — sie sind Teil des Nomen-Eintrags bzw. irrelevant.

    5. Liefere für jedes Wort die LEMMA-Form (Grundform):
       - Verben: Infinitiv (parler, to speak, gehen).
       - Nomen: Singular, Nominativ, mit lokalem Artikel falls üblich (le chien, the dog, der Hund).
       - Adjektive: unflektierte Grundform (grand, big, groß).
       - Pronomen: Grundform (je, il, ich, er).
       - Präpositionen/Konjunktionen/Adverbien/Sonstige: wie im Text erscheinend.

    6. ÜBERSETZUNG DER EINZELEINTRÄGE — gleiche Richtung wie die Textübersetzung:
       - Wenn der erkannte Text auf **Deutsch** ist: übersetze jedes Wort ins **Französische** (Feld `translation`).
       - Sonst: übersetze jedes Wort ins **Deutsche** (Feld `translation`).
       Bei mehreren möglichen Übersetzungen: die häufigste/treffendste wählen.

    7. Bei NOMEN: bestimme den bestimmten Artikel des **Originalworts** — Feld `gender`:
       - Französisch: „le", „la" oder „l'" (Elision vor Vokal oder stummem h, z. B. l'ami, l'école).
       - Deutsch: „der", „die" oder „das".
       - Englisch/andere Sprachen ohne Genus: `null`.
       WICHTIG: Das Feld `word` soll das Nomen OHNE vorangestellten Artikel enthalten (also „maison", nicht „la maison"). Der Artikel steht NUR im `gender`-Feld. Die App fügt Artikel und Wort für die Anzeige automatisch zusammen.
       Wenn der Artikel nicht sicher bestimmbar ist: `null` (lieber kein Artikel als ein falscher).

    8. Bei JEDEM Eintrag: setze `is_foreign: true`, wenn das Wort in der erkannten Sprache als Fremdwort gilt (z. B. „Smartphone" im Deutschen, „weekend" im Französischen); ansonsten `false`.

    DUPLIKAT-REGEL:
    - Gleiche Lemmata nur EINMAL pro Kategorie listen, auch wenn sie im Text mehrfach vorkommen.
    - Verschiedene Flexionsformen desselben Lemmas zählen als ein Eintrag (er geht, ich gehe → ein Verb-Eintrag „gehen").

    AUSGABE:
    Antworte AUSSCHLIESSLICH mit validem JSON (kein Markdown, keine Codeblöcke, keine Erklärungen davor oder danach). Struktur:

    {
      "language": "Französisch",
      "original_text": "La maison est grande. Je parle français vite.",
      "translation": "Das Haus ist groß. Ich spreche schnell Französisch.",
      "nomen": [
        { "word": "maison", "translation": "das Haus", "gender": "la", "is_foreign": false }
      ],
      "verben": [
        { "word": "parler", "translation": "sprechen", "is_foreign": false }
      ],
      "adjektive": [
        { "word": "grand", "translation": "groß", "is_foreign": false }
      ],
      "adverbien": [
        { "word": "vite", "translation": "schnell", "is_foreign": false }
      ],
      "pronomen": [
        { "word": "je", "translation": "ich", "is_foreign": false }
      ],
      "praepositionen": [],
      "konjunktionen": [],
      "sonstige": []
    }

    Beispiel bei deutschem Text:
    {
      "language": "Deutsch",
      "original_text": "Das Haus ist groß.",
      "translation": "La maison est grande.",
      "nomen": [
        { "word": "Haus", "translation": "la maison", "gender": "das", "is_foreign": false }
      ],
      "verben": [
        { "word": "sein", "translation": "être", "is_foreign": false }
      ],
      "adjektive": [
        { "word": "groß", "translation": "grand", "is_foreign": false }
      ],
      "adverbien": [],
      "pronomen": [],
      "praepositionen": [],
      "konjunktionen": [],
      "sonstige": []
    }

    Beispiel mit Elision:
    {
      "language": "Französisch",
      "original_text": "L'ami est arrivé.",
      "translation": "Der Freund ist angekommen.",
      "nomen": [
        { "word": "ami", "translation": "der Freund", "gender": "l'", "is_foreign": false }
      ],
      "verben": [
        { "word": "arriver", "translation": "ankommen", "is_foreign": false }
      ],
      "adjektive": [],
      "adverbien": [],
      "pronomen": [],
      "praepositionen": [],
      "konjunktionen": [],
      "sonstige": []
    }

    - Wenn eine Kategorie keine Einträge hat: leeres Array `[]` liefern.
    - Wenn auf dem Bild kein lesbarer Text zu finden ist: `original_text` und `translation` leer, alle Arrays leer, `language` auf „Unbekannt".
    """
}
