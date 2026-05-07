import Foundation

/// Scan AI client using Claude Haiku Vision via Anthropic Messages API.
/// Single-step: image → vocabulary pairs. No OCR needed.
struct ClaudeHaikuScanAIClient: ScanAIClient {
    let apiKey: String
    let model: String
    let maxTokens: Int
    let session: URLSession

    init(
        apiKey: String,
        model: String = "claude-haiku-4-5-20251001",
        maxTokens: Int = 8192,
        session: URLSession = .shared
    ) {
        self.apiKey = apiKey
        self.model = model
        self.maxTokens = maxTokens
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
            "max_tokens": maxTokens,
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
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body = try JSONSerialization.data(withJSONObject: requestBody)
        request.httpBody = body

        let bodyKB = body.count / 1024
        appDebugLog("📡 [Scan] API request [haiku-vision]: model=\(model) payload=\(bodyKB)KB timeout=60s")
        let apiStart = CFAbsoluteTimeGetCurrent()

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
            appDebugLog("📡 [Scan] API response [haiku-vision]: \(Int((CFAbsoluteTimeGetCurrent() - apiStart) * 1000))ms")
        } catch let urlError as URLError where urlError.code == .timedOut {
            appDebugLog("📡 [Scan] ❌ TIMEOUT [haiku-vision] after \(Int((CFAbsoluteTimeGetCurrent() - apiStart) * 1000))ms")
            throw ScanAIProviderError.timedOut
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScanAIProviderError.invalidResponse
        }

        guard 200..<300 ~= httpResponse.statusCode else {
            let errorText = String(data: data, encoding: .utf8) ?? "unknown"
            appDebugLog("📡 [Scan] ❌ HTTP \(httpResponse.statusCode): \(errorText.prefix(200))")
            throw ScanAIProviderError.httpFailure(httpResponse.statusCode, errorText)
        }

        // Anthropic response: { "content": [{ "type": "text", "text": "..." }] }
        let envelope = try JSONDecoder().decode(AnthropicMessagesResponse.self, from: data)
        guard let outputText = envelope.firstText else {
            throw ScanAIProviderError.invalidResponse
        }

        if envelope.wasTruncated {
            appDebugLog("📡 [Scan] ⚠️ Response truncated (max_tokens hit)")
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

        do {
            var scanResult = try JSONDecoder().decode(OpenAIScanSchemaResponse.self, from: Data(jsonText.utf8))
            scanResult.entries = scanResult.entries.map { Self.postProcessEntry($0) }
            // Safety-Netz: AI-Echo-im-Target scrubben und dual-form
            // Einträge („l'ami/l'amie") splitten. Spec-konform und
            // unabhängig davon, ob der System-Prompt bereits richtig
            // gefolgt wurde.
            return ScanAIPostProcessor.apply(to: scanResult.toPayload())
        } catch {
            // If truncated, try to salvage partial JSON by closing brackets
            if envelope.wasTruncated {
                if var salvaged = Self.salvageTruncatedJSON(jsonText) {
                    salvaged.entries = salvaged.entries.map { Self.postProcessEntry($0) }
                    appDebugLog("📡 [Scan] 🩹 Salvaged truncated JSON (\(salvaged.entries.count) entries)")
                    return ScanAIPostProcessor.apply(to: salvaged.toPayload())
                }
            }
            appDebugLog("📡 [Scan] ❌ JSON decode failed: \(error)")
            appDebugLog("📡 [Scan] Raw response (first 500 chars): \(String(jsonText.prefix(500)))")
            throw ScanAIProviderError.invalidResponse
        }
    }

    /// Attempt to salvage truncated JSON by finding the last complete entry and closing brackets
    static func salvageTruncatedJSON(_ json: String) -> OpenAIScanSchemaResponse? {
        // Find the last complete entry: look for the last "}," or "}" before entries array ends
        guard let entriesRange = json.range(of: "\"entries\"", options: .literal) else { return nil }
        let afterEntries = json[entriesRange.upperBound...]

        // Find the last complete object closing brace followed by comma or just brace
        var lastGoodEnd: String.Index?
        var braceDepth = 0
        var inString = false
        var escape = false
        var searchStart = afterEntries.startIndex

        // Skip to opening bracket of entries array
        if let bracketStart = afterEntries.firstIndex(of: "[") {
            searchStart = afterEntries.index(after: bracketStart)
        }

        for i in afterEntries[searchStart...].indices {
            let ch = afterEntries[i]
            if escape { escape = false; continue }
            if ch == "\\" { escape = true; continue }
            if ch == "\"" { inString.toggle(); continue }
            if inString { continue }
            if ch == "{" { braceDepth += 1 }
            if ch == "}" {
                braceDepth -= 1
                if braceDepth == 0 {
                    lastGoodEnd = i
                }
            }
        }

        guard let cutoff = lastGoodEnd else { return nil }

        // Build salvaged JSON: everything up to and including the last complete entry, then close array + object
        let salvaged = String(json[json.startIndex...cutoff]) + "\n  ]\n}"
        do {
            return try JSONDecoder().decode(OpenAIScanSchemaResponse.self, from: Data(salvaged.utf8))
        } catch {
            appDebugLog("📡 [Scan] 🩹 Salvage attempt also failed: \(error)")
            return nil
        }
    }

    // Alte lokale „neverCapitalizedSet"-Heuristik entfernt — Casing läuft
    // ausschließlich über TextNormalizationEngine.

    /// Force-lowercase non-nouns in German target text — zentrale Engine.
    static func forceGermanLowercase(_ text: String) -> String {
        return TextNormalizationEngine.normalize(text, language: .german)
    }

    /// Post-process decoded entries to fix systematic AI errors
    static func postProcessEntry(_ entry: OpenAIScanSchemaResponse.Entry) -> OpenAIScanSchemaResponse.Entry {
        var e = entry
        // Force-lowercase non-nouns (und, sich, sind, von, der, die, das...)
        e.target = forceGermanLowercase(e.target)

        // Fix "les les" → "les"
        if e.source.lowercased().hasPrefix("les les") {
            e.source = String(e.source.dropFirst(4))
        }

        // Remove trailing period from placeholder phrases like "ich heiße + Name."
        if e.target.hasSuffix(".") && e.target.contains("+") {
            e.target = String(e.target.dropLast())
        }
        // Fix known question phrases translated as statements
        let sourceKey = normalizeForLookup(e.source)
        if let correctTarget = knownQuestionPhrases[sourceKey] {
            e.target = correctTarget
        }
        // Fix article pairs without slash: "der DAS" → "der/das"
        for (wrong, correct) in articlePairFixes {
            e.target = e.target.replacingOccurrences(of: wrong, with: correct)
        }
        e.target = fixLnError(e.target)
        // Fix commonly misread French source phrases
        e.source = fixMisreadFrenchSource(e.source)
        // Fix French prepositions/articles that got capitalized: "De" → "de"
        e.source = fixFrenchCapitalization(e.source)
        // Ensure source with "comment" has ? in target
        if sourceKey.contains("comment") && !e.target.hasSuffix("?") {
            e.target = e.target.trimmingCharacters(in: CharacterSet(charactersIn: ".")) + "?"
        }
        return e
    }

    /// Normalize text for dictionary lookup — unify apostrophe variants, lowercase, trim
    private static func normalizeForLookup(_ text: String) -> String {
        text.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\u{2019}", with: "'") // ' → '
            .replacingOccurrences(of: "\u{02BC}", with: "'") // ʼ → '
            .replacingOccurrences(of: "\u{2018}", with: "'") // ' → '
            .replacingOccurrences(of: "?", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Fix French capitalization — zentrale Engine.
    private static func fixFrenchCapitalization(_ text: String) -> String {
        return TextNormalizationEngine.normalize(text, language: .french)
    }

    /// Fix commonly misread French phrases in source text
    private static func fixMisreadFrenchSource(_ text: String) -> String {
        var result = text

        // Fix "le l" → "le/la" (misread slash)
        let sourceFixes: [(wrong: String, correct: String)] = [
            ("le l", "le/la"),
            ("Le L", "le/la"),
            ("le la", "le/la"),
            ("Le La", "le/la"),
            ("le l'", "le/la/l'"),
            ("le la l'", "le/la/l'"),
            ("les les", "les"),
        ]
        let lower = result.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for (wrong, correct) in sourceFixes {
            if lower == wrong.lowercased() {
                result = correct
                return result
            }
        }

        // Phrase-level fixes
        let phraseFixes: [(wrong: String, correct: String)] = [
            ("ca vient", "ce sont"),
            ("ça vient", "ce sont"),
            ("c'est sont", "ce sont"),
        ]
        for (wrong, correct) in phraseFixes {
            if lower == wrong {
                result = correct
                break
            }
        }
        return result
    }

    /// Fix "ln" / "l'n" errors in target text (l'ami misread)
    private static func fixLnError(_ text: String) -> String {
        text.replacingOccurrences(of: "der ln", with: "der Freund")
            .replacingOccurrences(of: "die ln", with: "die Freundin")
            .replacingOccurrences(of: "mein ln", with: "mein Freund")
            .replacingOccurrences(of: "meine ln", with: "meine Freundin")
            .replacingOccurrences(of: "der l'n", with: "der Freund")
            .replacingOccurrences(of: "die l'n", with: "die Freundin")
    }

    /// Fix missing slash between article pairs: "der DAS" → "der/das", "Der Die" → "der/die"
    private static let articlePairFixes: [(wrong: String, correct: String)] = [
        // Mixed case without slash
        ("der DAS", "der/das"), ("der Das", "der/das"), ("der das", "der/das"),
        ("die DAS", "die/das"), ("die Das", "die/das"),
        ("der DIE", "der/die"), ("der Die", "der/die"),
        ("die DER", "die/der"), ("die Der", "die/der"),
        // Both capitalized without slash
        ("Der Die", "der/die"), ("Der Das", "der/das"), ("Die Der", "die/der"),
        ("Die Das", "die/das"), ("Das Die", "das/die"),
        ("Der die", "der/die"), ("Die der", "die/der"),
        // Plural
        ("die Plural", "die (bestimmter Artikel im Plural)"),
    ]

    /// Known French phrases that are ALWAYS questions — fix if translated as statement
    private static let knownQuestionPhrases: [String: String] = [
        "tu t'appelles comment": "Wie heißt du?",
        "comment tu t'appelles": "Wie heißt du?",
        "ça va": "Wie geht's?",
        "ca va": "Wie geht's?",
        "c'est qui": "Wer ist das?",
        "c'est quoi": "Was ist das?",
        "tu as quel âge": "Wie alt bist du?",
        "tu as quel age": "Wie alt bist du?",
    ]

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

        *** KRITISCHE FEHLER DIE DU VERMEIDEN MUSST ***
        1. l'ami = "der Freund". l'amie = "die Freundin". NIEMALS "ln", "l'n", "der ln", "die ln" schreiben!
           Das l' ist der verkürzte Artikel (le/la). ami/amie ist das Wort. Zusammen: l'ami, l'amie.
        2. Deutsche Kleinschreibung bei Verben/Konjunktionen: "und" NICHT "Und", "sind" NICHT "Sind", "bist" NICHT "Bist".
           NUR Nomen und Satzanfänge groß! Alles andere klein!
        3. "ce sont" NICHT überspringen! Es ist die Pluralform von "c'est" und steht häufig in Vokabeltabellen.
           "ce sont" → "das sind". IMMER extrahieren wenn sichtbar!
        ***

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
        Korrekte Übersetzungen der französischen Artikel:
        le → der, la → die, l' → der/die (je nach Geschlecht), les → die (bestimmter Artikel im Plural)
        NIEMALS "les" als "die Plural" übersetzen — schreibe "die (bestimmter Artikel im Plural)" oder einfach "die".
        le/la → "der/die" (mit Schrägstrich, NICHT "der die" oder "der DAS")
        ***

        REGEL 1 – Was eine Vokabelzeile ist:
        Eine Vokabelzeile hat die Struktur: französischer Begriff [Lautschrift] Grammatikangabe → deutsche Übersetzung.
        Extrahiere NUR Zeilen die dieses Muster haben. Die 3. Spalte (Beispielsätze/Dialoge) vollständig ignorieren.
        Auch sehr kurze Einträge zählen: "ah" → "ach, ach so", "et" → "und", "toi" → "du"
        Häufig übersehene Einträge — NICHT vergessen:
        "ce sont" → "das sind" (Plural von "c'est")
        "c'est" → "das ist" (Singular)
        Beide MÜSSEN extrahiert werden wenn sie im Bild stehen!
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

        **NIEMALS die französische Quellform als deutsche Übersetzung ausgeben.**
        Wenn du die deutsche Übersetzung nicht erkennst oder dir unsicher bist:
        - target: "" (leer lassen) und is_importable: false
        - NIEMALS den französischen Text in das "target"-Feld schreiben
        - NIEMALS OCR-Müll als Übersetzung ausgeben
        Beispiel falsch: source="le chat", target="le chat" — NEIN
        Beispiel richtig bei Unsicherheit: source="le chat", target="", is_importable=false, confidence=0.3

        REGEL 10 – Apostrophe und Elision (HÄUFIGSTER FEHLER!):
        Wenn du im Bild "l'ami" oder "l'amie" siehst:
        - l'ami → Übersetzung: "der Freund"
        - l'amie → Übersetzung: "die Freundin"
        - l'école → Übersetzung: "die Schule"
        Das l' ist IMMER der Artikel le/la, verkürzt vor Vokal. Das Wort ist ami/amie/école.
        Du darfst UNTER KEINEN UMSTÄNDEN "ln", "l'n", "der ln", "die ln" schreiben.
        Wenn du "ln" in deiner Ausgabe findest, hast du einen Fehler gemacht — korrigiere zu "Freund"/"Freundin".
        Auch: C'est (NICHT C#est), j'ai, qu'est-ce que — Apostroph = '
        le/la/l' sind EINZELNE Artikel — NIEMALS "le l" oder "le la" zusammen.

        REGEL 11 – Deutsche Groß-/Kleinschreibung (ZWEITHÄUFIGSTER FEHLER!):
        Im Deutschen werden NUR groß geschrieben:
        - Satzanfänge
        - Nomen (Substantive): Freund, Haus, Schule, Name
        ALLES ANDERE wird klein geschrieben:
        - Verben: ist, bist, sind, heißt, geht, vorstellen
        - Konjunktionen: und, oder, aber, denn
        - Pronomen: du, andere, sich, es
        - Adjektive: groß, klein, gut, alt, neu, jung
        - Präpositionen: in, auf, mit, von
        KONKRETE BEISPIELE:
        ✅ "sich und andere vorstellen" ❌ "Sich Und Andere Vorstellen"
        ✅ "das bist du" ❌ "Das Bist Du"
        ✅ "wir sind Freunde" ❌ "Wir Sind Freunde"
        ✅ "wie heißt du?" ❌ "Wie Heißt Du?"
        ✅ "wie alt?" ❌ "Wie Alt?"
        ✅ "Ich weiß nicht" ❌ "ich weiß nicht" (Satzanfang → groß!)
        PRÜFE JEDEN EINTRAG: Ist ein Verb/Konjunktion/Pronomen großgeschrieben? → KORRIGIEREN!

        REGEL 12 – Vollständige Übersetzungen und m/f Paare:
        "moi, c'est + Name" → "ich heiße + Name" (NICHT nur "+ Name")
        "mon ami" → "mein Freund" (NICHT "mein ln", NICHT "mein l'n")
        "mon amie" → "meine Freundin" (NICHT "meine ln")
        Übersetze den GESAMTEN Ausdruck — nicht nur Teile davon.

        **BEI MÄNNLICH/WEIBLICH-PAAREN MIT "/" IM BILD: IMMER ZWEI SEPARATE EINTRÄGE ERZEUGEN!**
        Vorher wurde das als ein Eintrag mit Schrägstrich ausgegeben, das soll
        jetzt **aufgeteilt** werden, damit jede Form einzeln lernbar ist.
        "l'ami/l'amie" im Bild → zwei Einträge:
           1. source: "l'ami",  target: "der Freund"
           2. source: "l'amie", target: "die Freundin"
        "mon ami/mon amie" im Bild → zwei Einträge:
           1. source: "mon ami",  target: "mein Freund"
           2. source: "mon amie", target: "meine Freundin"
        "le copain/la copine" im Bild → zwei Einträge:
           1. source: "le copain", target: "der Kumpel"
           2. source: "la copine", target: "die Kumpelin"
        WICHTIG: Beide Teile als ZWEI SEPARATE entries-Objekte ausgeben.
        NIEMALS "ln"/"l'n" schreiben. NIEMALS die source mit "/" zusammenlassen.

        REGEL 13 – Eigennamen korrekt schreiben:
        Namen werden mit großem Anfangsbuchstaben und kleinen Folgebuchstaben geschrieben:
        "Lena" NICHT "LENA", "Max" NICHT "MAX", "Jeanne" NICHT "JEANNE".
        NIEMALS Namen komplett in Großbuchstaben schreiben — auch wenn sie im Bild so stehen.

        REGEL 14 – Einzahl/Mehrzahl EXAKT vom Bild übernehmen:
        Wenn im Bild "les jeux vidéo" steht, schreibe "les jeux vidéo" — NICHT "le jeu vidéo".
        Wenn im Bild "les sports" steht, schreibe "les sports" — NICHT "le sport".
        NIEMALS Mehrzahl zu Einzahl ändern oder umgekehrt. Übernimm EXAKT was sichtbar ist.
        Wenn keine deutsche Übersetzung daneben steht, trotzdem den französischen Teil exakt übernehmen.

        REGEL 15 – Wortart bestimmen:
        Bestimme für JEDEN Eintrag die Wortart im Feld "word_class":
        "noun" = Nomen/Substantiv (le chat, la maison, l'ami)
        "verb" = Verb (être, avoir, aller)
        "adjective" = Adjektiv (grand, petit, bon)
        "adverb" = Adverb (bien, mal, très)
        "pronoun" = Pronomen (je, tu, il, moi, toi)
        "preposition" = Präposition (de, à, dans, pour, avec)
        "conjunction" = Konjunktion (et, ou, mais)
        "interjection" = Interjektion (ah, oh, merci, salut)
        "phrase" = Feste Wendung/Phrase (ça va?, c'est parti!, je m'appelle)
        Bei Phrasen mit mehreren Wörtern: "phrase" verwenden.

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
              "word_class": "noun",
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
    let stop_reason: String?

    var firstText: String? {
        content.first(where: { $0.type == "text" })?.text
    }

    var wasTruncated: Bool {
        stop_reason == "max_tokens"
    }

    struct ContentBlock: Decodable {
        let type: String
        let text: String?
    }
}
