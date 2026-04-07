import Foundation

extension OpenAIResponsesScanAIClient {
    func makeRequestBody(from payload: ScanAIRequestPayload) -> [String: Any] {
        let base64Image = payload.imageJPEGData.base64EncodedString()
        let imageURL = "data:image/jpeg;base64,\(base64Image)"
        let prompt = makePrompt(from: payload)

        return [
            "model": model,
            "input": [
                [
                    "role": "system",
                    "content": [
                        [
                            "type": "input_text",
                            "text": """
Extract French learning content from photographed pages for a German learner.
Return only strict JSON matching the provided schema.
Prefer correct French-German pairs over quantity.
Ignore decorative elements, page numbers, and example-dialog columns unless they are the main learnable content.
If the page is a vocabulary table with examples in a third column, pair only the French source term with the German translation.
Copy the visible source and target text as faithfully as possible.
Never replace concrete names or filled-in words with placeholders like "+ Name", "Name", "nom" or similar templates.
Preserve visible terminal punctuation exactly, especially ?, ! and .
If one side is clearly a question, exclamation or full sentence, keep the corresponding punctuation on the paired translation as well.
"""
                        ]
                    ]
                ],
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": prompt
                        ],
                        [
                            "type": "input_image",
                            "image_url": imageURL,
                            "detail": "auto"
                        ]
                    ]
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "elumi_scan_result",
                    "strict": true,
                    "schema": Self.responseSchema
                ]
            ]
        ]
    }

    func makePrompt(from payload: ScanAIRequestPayload) -> String {
        let preferredMode = payload.preferredMode?.rawValue ?? "auto"
        let sourceLanguage = payload.sourceLanguageCode
        let ocrContextDescription: String

        if let ocrContext = payload.ocrContext {
            let recognizedLines = ocrContext.recognizedLines
                .prefix(40)
                .joined(separator: " | ")
            let seededEntries = ocrContext.entries.prefix(16).map {
                let categoryPart = $0.learningCategory.map { "[\($0)]" } ?? ""
                let importablePart = $0.isImportable ? "[importable]" : "[context-only]"
                let notePart = $0.note.flatMap { note in
                    note.isEmpty ? nil : " {\(note)}"
                } ?? ""
                return "\($0.source) => \($0.target) [\($0.cardType)]\(categoryPart)\(importablePart)\(notePart)"
            }.joined(separator: " | ")

            ocrContextDescription = """
OCR context:
- document_type: \(ocrContext.documentType.rawValue)
- mode: \(ocrContext.mode.rawValue)
- confidence: \(String(format: "%.2f", ocrContext.confidence))
- recognized_lines: \(recognizedLines)
- extracted_entries: \(seededEntries)
"""
        } else {
            ocrContextDescription = "OCR context: none"
        }

        return """
Analyze this learning scan for Elumi.

Requirements:
- Source language is usually French and target language is German.
- preferred_mode: \(preferredMode)
- source_language_label: \(sourceLanguage)
- Return concise, high-quality entries only.
- card_type must be "words" for single words and "phrases" for multi-word expressions or questions.
- Keep apostrophes in French.
- Copy the wording from the scan as literally as possible.
- Do not normalize away filled-in names or concrete words.
- Never rewrite `je m'appelle Marie` as `je m'appelle + Name`.
- Never rewrite `ich heiße Marie` as `ich heiße Name`.
- Preserve terminal punctuation exactly when it belongs to the scanned entry.
- Especially keep ?, ! and final periods for phrases, questions, greetings and full-sentence expressions.
- Do not strip punctuation from the source or target if it is visible on the page.
- If the French side is a question, the German translation must also end with `?`.
- If the French side is an exclamation, the German translation must also end with `!`.
- If one side ends with a full-sentence period and the other side is the paired full sentence, keep `.` on both.
- Keep German nouns capitalized.
- Do not invent translations not supported by the page.
- If unsure, omit the weak entry instead of hallucinating.
- warnings should contain short machine-friendly strings.
- For free text pages, do not return every trivial word.
- Skip low-value function words like `je`, `tu`, `et`, `de`, `la`, `est` when they are not meaningful learning content.
- If the page is a poster, notice, sign or public instruction, prefer meaningful sign phrases over schedules, dates and opening times.
- Ignore timetable-like lines with weekdays and hours unless they are the main learning content.
- For free text pages, prefer four buckets:
  1. recognized text context
  2. useful verbs
  3. useful phrases
  4. short grammar learning points
- Use `learning_category` with one of:
  - `recognizedText`
  - `verbs`
  - `phrases`
  - `grammar`
- If an entry is only context and should not become a flashcard, set `is_importable` to `false`.
- Put short user-facing hints like `Kontext aus dem Scan` or `Verb aus dem Text` into `note`.
- Do not use `notes` for bucket metadata unless you need legacy fallback compatibility.
- summary and import_message must be short German UI strings.

Examples:
- `Et toi ?` -> `Und du?`
- `Ça va ?` -> `Wie geht es dir?`
- `C'est parti !` -> `Los geht's!`
- `Je m'appelle Marie.` -> `Ich heiße Marie.`

\(ocrContextDescription)
"""
    }

    func parseAPIErrorMessage(from data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let error = object["error"] as? [String: Any],
            let message = error["message"] as? String,
            !message.isEmpty
        else {
            return "OpenAI API request failed."
        }

        return message
    }
}
