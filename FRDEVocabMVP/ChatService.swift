// ChatService.swift
// **Léa-Chat MVP Schritt 1 (2026-05-10)** — Singleton-Service der
// die Konversation mit Léa orchestriert: lädt History aus SwiftData,
// sendet User-Messages an die Edge Function, parst die SSE-Antwort
// von Anthropic Token-für-Token und schreibt sie live in die laufende
// Léa-Message.
//
// **Lifecycle**:
//   1. App-Start: `ChatService.shared` ist verfügbar (lazy init).
//   2. ContentView/HomeView ruft `configure(with: modelContext)` als
//      `.onAppear` o. ä. — erst dann hat der Service Zugriff auf die
//      SwiftData-Persistenz.
//   3. ChatView und LeaChatHomeCard binden direkt an `messages` /
//      `streamingMessageID` / `isTyping` (alle via `@Observable`).
//
// **Streaming-Pattern**:
//   - Léa-Placeholder-Message wird VOR dem Stream als leere Bubble
//     angelegt + in `messages` appended (UI rendert sofort).
//   - Während des Streams modifizieren wir `placeholder.text +=
//     token` direkt — SwiftData @Model + @Observable propagieren
//     das Änderung an alle subscribten Views.
//   - `streamingMessageID` markiert die laufende Message, damit die
//     Bubble den blinkenden Cursor anzeigen kann.
//
// **Error-Pattern**:
//   - Bei Network-, Auth- oder Server-Errors überschreiben wir den
//     Placeholder-Text mit der `userMessage`-Variante des Errors.
//   - User sieht den Error inline als Léa-Bubble (statt Toast/Alert),
//     bleibt im Konversations-Look.

import Foundation
import SwiftData
import SwiftUI // Für `withAnimation`/`.spring(...)` beim Korrektur-Reveal (Schritt 2A)

enum ChatError: Error, Equatable {
    case authError
    case rateLimit(String)
    case serverError
    case networkError(String)
    case invalidResponse

    /// User-facing Meldung — wird im Placeholder-Text angezeigt.
    var userMessage: String {
        switch self {
        case .authError:
            return "Authentifizierungs-Problem — bitte App neu starten."
        case .rateLimit(let msg):
            return msg
        case .serverError:
            return "Léa schläft gerade — versuch's gleich nochmal."
        case .networkError:
            return "Léa hat gerade kein Netz 📵"
        case .invalidResponse:
            return "Léa antwortet komisch — versuch's gleich nochmal."
        }
    }
}

@Observable
@MainActor
final class ChatService {
    // MARK: - Singleton

    static let shared = ChatService()

    // MARK: - State (observed by Views)

    /// Aktuelle Konversation, sortiert nach `timestamp` aufsteigend.
    /// Wird beim ersten `configure(with:)`-Call aus SwiftData geladen.
    var messages: [ChatMessage] = []

    /// Persona für Schritt 1: hardcoded Léa. Multi-Persona kommt später.
    var currentPersona = ChatPersona()

    /// Während des kurzen Wartens nach User-Send aber bevor Léa-Tokens
    /// eintrudeln — TypingIndicator-View bindet daran.
    var isTyping: Bool = false

    /// ID der gerade streamenden Léa-Message — Bubble-View bindet
    /// daran für den blinkenden Cursor.
    var streamingMessageID: UUID?

    /// Zuletzt aufgetretener Error — kann für Banner-Display in Views
    /// genutzt werden (Schritt 1: Error wird primär inline als
    /// Léa-Bubble angezeigt).
    var error: ChatError?

    /// **Schritt 2B-1 (2026-05-10)** — Signalisiert ChatView, dass
    /// der User keine aktive Wortschatz-Liste hat. ChatView blockt
    /// dann via Modal, bis der User über den `GlobalListPickerSheet`
    /// eine Liste wählt. Wird auf `false` gesetzt, sobald
    /// `currentContext` einen non-nil Wert liefert.
    var needsListSelection: Bool = false

    // MARK: - Dependencies

    private(set) var modelContext: ModelContext?

    /// **Schritt 2B-1** — Listen-Store, aus dem der Provider die
    /// aktive Selection auflöst. Optional, weil `LeaChatHomeCard`
    /// (Home-Preview) den Service auch konfiguriert ohne Store-
    /// Zugriff zu brauchen — nur ChatView hängt den Store an.
    /// Bei `nil` während `sendMessage`: behandeln wir als
    /// `needsListSelection`, weil ohne Store keine Liste auflösbar.
    private(set) var listStore: VocabularyListStore?

    private init() {}

    // MARK: - Configuration

    /// Muss einmalig aufgerufen werden (typischerweise vom Root-View
    /// per `.onAppear` mit `\.modelContext` aus dem Environment),
    /// bevor sendMessage / loadHistory funktionieren. Idempotent —
    /// mehrfache Aufrufe sind ok.
    ///
    /// **Schritt 2B-1 (2026-05-10)** — `listStore` als optionaler
    /// Param. ChatView reicht den Store aus dem `runtime.listStore`
    /// durch (für Wortschatz-Auflösung); `LeaChatHomeCard` darf
    /// `nil` lassen, da die Card nur die Message-History rendert
    /// und keinen Send-Pfad triggert.
    /// Verhalten: nil-listStore-Aufrufe überschreiben einen schon
    /// gesetzten Store NICHT — sonst würde ein zweiter Card-Render
    /// (Home → Chat → Home) den vorhandenen Store wegputzen.
    func configure(with context: ModelContext, listStore: VocabularyListStore? = nil) {
        self.modelContext = context
        if let listStore { self.listStore = listStore }
        loadHistory()
    }

    /// Lädt die Konversation aus SwiftData (alle ChatMessages,
    /// sortiert nach timestamp). Synchron, weil SwiftData-Fetches
    /// auf MainActor laufen — Anzahl Messages bleibt klein (<200
    /// pro User typisch).
    func loadHistory() {
        guard let modelContext else { return }
        let descriptor = FetchDescriptor<ChatMessage>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        if let loaded = try? modelContext.fetch(descriptor) {
            messages = loaded
        }
    }

    // MARK: - Reset

    /// **Schritt 2A — Smoke-Helper (2026-05-10)**
    /// Löscht alle persisted ChatMessages aus dem ModelContext und
    /// wischt den In-Memory-State. Wird vom Settings-Sheet getriggert,
    /// damit Frank während des Smokes verschiedene Fehler-Szenarien
    /// frisch durchprobieren kann ohne die App neu zu installieren.
    ///
    /// **Streaming-Guard**: Während eines aktiven Streams wird ein
    /// Reset abgelehnt — der Stream-Loop schreibt in `leaMsg.text`
    /// direkt; ein paralleler Wipe würde in eine detached SwiftData-
    /// Instanz schreiben und potentiell crashen. Caller-Site
    /// (Settings-Sheet) macht den Button zusätzlich `.disabled` wenn
    /// `streamingMessageID != nil || isTyping`.
    ///
    /// **Reentrant**: Caller darf nach `resetHistory()` direkt
    /// `await ensureFirstGreeting()` aufrufen — die leere Konversation
    /// wird sofort wieder mit der tageszeit-passenden Begrüßung
    /// initialisiert.
    func resetHistory() {
        guard streamingMessageID == nil, !isTyping else { return }
        guard let modelContext else { return }

        // SwiftData iOS 17 Bulk-Delete — löscht alle Instances des
        // Models in einem Pass (effizienter als per-Instanz-Schleife).
        do {
            try modelContext.delete(model: ChatMessage.self)
            try modelContext.save()
        } catch {
            // Fallback: per-Instanz-Delete. Sollte nie greifen, aber
            // defensive — wir wollen den Reset nicht wegen einer
            // SwiftData-Quirk verlieren.
            let descriptor = FetchDescriptor<ChatMessage>()
            if let all = try? modelContext.fetch(descriptor) {
                for msg in all { modelContext.delete(msg) }
                try? modelContext.save()
            }
        }

        // In-Memory-State zurücksetzen — Views re-rendern via
        // @Observable sofort auf leere Konversation.
        messages = []
        streamingMessageID = nil
        isTyping = false
        error = nil
    }

    // MARK: - First-Greeting

    /// Wenn die Konversation leer ist, schickt Léa eine tageszeit-
    /// abhängige Begrüßung — KEIN Backend-Call, der Greet-Text ist
    /// canned (spart Rate-Limit-Quota für reale Antworten).
    ///
    /// **Schritt 2B-1**: Greeting-Bedingung an `vocabContext`
    /// gekoppelt — wenn der User keine Liste hat, kein Greeting,
    /// stattdessen `needsListSelection = true` setzen. ChatView
    /// reagiert via Modal.
    func ensureFirstGreeting() async {
        guard messages.isEmpty else { return }

        // Vorab-Check: Vokabel-Kontext da? Sonst Modal triggern und
        // greeting unterlassen — sonst würde Léa „Hi" sagen ohne
        // dass sie Lektionswörter kennt; das Modal kommt dann erst
        // beim ersten User-Tap, was inkonsistent wirkt.
        guard let _ = currentVocabContext() else {
            needsListSelection = true
            return
        }
        needsListSelection = false

        let hour = Calendar.current.component(.hour, from: Date())
        let greeting: String
        switch hour {
        case ..<12:  greeting = "Bonjour ! Bien dormi ? 😊"
        case 12..<18: greeting = "Salut ! Ça va aujourd'hui ?"
        default:     greeting = "Bonsoir ! Comment s'est passée ta journée ?"
        }

        // Kurzer Typing-Indicator-Spike, damit's natürlich wirkt.
        isTyping = true
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        isTyping = false

        appendLeaMessage(text: greeting)
    }

    // MARK: - Vocabulary-Context-Helper

    /// **Schritt 2B-1** — Liest den aktuellen `ChatVocabularyContext`
    /// vom Provider. `nil` wenn (a) kein listStore gesetzt oder
    /// (b) keine Liste aktiv. ChatView's Modal-Trigger verlässt
    /// sich auf die nil-Semantik.
    func currentVocabContext() -> ChatVocabularyContext? {
        guard let listStore else { return nil }
        return ChatVocabularyProvider.currentContext(from: listStore)
    }

    // MARK: - Send + Stream

    /// Schickt eine User-Message ans Backend, fügt einen Léa-
    /// Placeholder ein, streamt die Antwort live in den Placeholder.
    /// Der Aufrufer kann das Ergebnis abwarten, muss aber nicht — die
    /// `@Observable`-State-Updates propagieren automatisch.
    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // **Schritt 2B-1** — Vor allem anderen: Vokabel-Kontext da?
        // Wenn nicht, blockieren wir den Send vollständig — kein
        // User-Insert, kein Backend-Call. ChatView öffnet via
        // `needsListSelection`-Beobachtung das GlobalListPickerSheet,
        // der User wählt, kommt zurück, schickt erneut. So lange
        // der Marker steht, ist die Konversation sauber leer
        // (oder bei vorhandener History: nicht angefasst).
        guard let vocabCtx = currentVocabContext() else {
            needsListSelection = true
            return
        }
        needsListSelection = false

        // 1) User-Bubble einfügen + persistieren
        let userMsg = ChatMessage(sender: .user, text: trimmed)
        modelContext?.insert(userMsg)
        messages.append(userMsg)
        try? modelContext?.save()

        // 2) TypingIndicator AN — kurz vor Stream-Start
        isTyping = true
        error = nil
        try? await Task.sleep(nanoseconds: 600_000_000)

        // 3) Léa-Placeholder einfügen + persistieren (mit leerem Text).
        //    Der Stream füllt den Text live; SwiftData propagiert via
        //    @Observable die Änderungen an die Bubble-Views.
        let leaMsg = ChatMessage(sender: .lea, text: "")
        modelContext?.insert(leaMsg)
        messages.append(leaMsg)
        streamingMessageID = leaMsg.id
        isTyping = false

        do {
            // **Schritt 2B-1** — Vocab-Kontext durchreichen. Wir lesen
            // ihn HIER nochmal (statt vom Top zu cachen), falls der
            // User zwischen Top-Guard und Stream-Start die Auswahl
            // wechselt — unwahrscheinlich, aber pragmatisch konsistent
            // mit „live bei jedem API-Call".
            let liveCtx = currentVocabContext() ?? vocabCtx
            try await streamLeaResponse(into: leaMsg, vocabContext: liveCtx)

            // **Schritt 2A — Stream-End-Parsing** (erweitert in 2B-1)
            // Nach dem Stream extrahieren wir alle Marker aus Léas
            // rohem Text:
            //   • [FEHLER: …] → Korrektur-Felder retroaktiv auf
            //     userMsg (Bubble creme + Badge + Underline + Shake,
            //     CorrectionCard zwischen User-Bubble und Léa-Antwort).
            //   • [VOCAB: wort] → vocabUsed auf userMsg (User-Bubble
            //     bekommt grüne Wort-Highlights).
            //   • [NEW: wort|übersetzung] → newWords auf leaMsg
            //     (Léa-Bubble bekommt blaue Underlines + Tooltip).
            // Plus: leaMsg.text bekommt IMMER den cleanText (auch
            // wenn keine Marker gefunden wurden — defensive, weil
            // die Marker-Detection auch ohne Treffer Whitespace
            // trimmt).
            //
            // **Spec-Hinweis**: Léa darf max 1 FEHLER-Marker liefern
            // (System-Prompt). Wir nehmen den ersten, der Rest wird
            // verworfen — sonst würde die Bubble-State mehrere
            // Korrekturen rendern müssen.
            let parsed = ChatMarkerParser.parseLeaMessage(leaMsg.text)
            leaMsg.text = parsed.cleanText

            // 2B-1 — VOCAB-Wörter retroaktiv auf User-Message UND
            // auf Léa-Message. Auf User-Message für den hellen
            // grünen Highlight (User hat das Wort korrekt benutzt);
            // auf Léa-Message für den dezenteren Highlight, wenn
            // Léa das Wort in ihrem Recasting auch verwendet (Frank's
            // Spec: User-Bubble bg 0.25, Léa-Bubble bg 0.15).
            if !parsed.vocabUsed.isEmpty {
                userMsg.vocabUsed = parsed.vocabUsed
                leaMsg.vocabUsed = parsed.vocabUsed
            }

            // 2B-1 — NEW-Wörter auf Léa-Message.
            if !parsed.newWords.isEmpty {
                leaMsg.newWords = parsed.newWords
            }

            // 2A — FEHLER-Korrektur retroaktiv auf User-Message
            // (mit Spring-Animation für die CorrectionCard-Insertion).
            if let firstError = parsed.foundErrors.first {
                userMsg.foundErrorUserText = firstError.userText
                userMsg.foundErrorGermanTip = firstError.germanTip
                let cardID = UUID()
                withAnimation(.spring(response: 0.45, dampingFraction: 0.78)) {
                    userMsg.correctionCardId = cardID
                }
            }

            try? modelContext?.save()
        } catch let chatError as ChatError {
            leaMsg.text = chatError.userMessage
            self.error = chatError
            try? modelContext?.save()
        } catch {
            leaMsg.text = ChatError.networkError(error.localizedDescription).userMessage
            self.error = .networkError(error.localizedDescription)
            try? modelContext?.save()
        }

        streamingMessageID = nil
    }

    // MARK: - Helpers

    /// Fügt eine Léa-Message direkt ein (ohne Backend-Call). Genutzt
    /// für die First-Greeting und potentiell zukünftige System-Hints.
    private func appendLeaMessage(text: String) {
        let msg = ChatMessage(sender: .lea, text: text)
        modelContext?.insert(msg)
        messages.append(msg)
        try? modelContext?.save()
    }

    /// Baut den Edge-Function-Request, parst den Anthropic-SSE-Stream
    /// und appendt jeden `text_delta` an `placeholder.text`.
    ///
    /// **Schritt 2B-1** — System-Prompt wird mit dem Live-Vokabel-
    /// Kontext + Niveau-Mapping gebaut (aus `vocabContext`). Caller
    /// hat den Kontext direkt vor diesem Call frisch geholt.
    private func streamLeaResponse(
        into placeholder: ChatMessage,
        vocabContext: ChatVocabularyContext
    ) async throws {
        var request = URLRequest(url: ChatConfig.backendURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(ChatConfig.anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(DeviceTokenManager.getOrCreateToken(), forHTTPHeaderField: "X-Device-Token")
        request.timeoutInterval = ChatConfig.timeoutSeconds

        // Body-Aufbau — Konversations-History (ohne den noch leeren
        // Léa-Placeholder, der ist erst die Antwort) plus System-Prompt.
        let history = messages
            .dropLast() // letzter Eintrag = `placeholder` mit text="" — ausschließen
            .map { msg -> [String: String] in
                [
                    "role": msg.sender == .user ? "user" : "assistant",
                    "content": msg.text,
                ]
            }
        let systemPrompt = currentPersona.buildSystemPrompt(
            vocabulary: vocabContext.words,
            level: vocabContext.level
        )
        let body: [String: Any] = [
            "system": systemPrompt,
            "messages": history,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ChatError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            break
        case 401:
            throw ChatError.authError
        case 429:
            // Versuche, die Backend-Nachricht zu lesen — meist Plain-JSON
            // statt SSE. Fallback: Standard-Rate-Limit-Text.
            var rateMsg = "Léa muss heute schlafen — bis morgen!"
            for try await line in bytes.lines {
                if let data = line.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let msg = json["message"] as? String {
                    rateMsg = msg
                    break
                }
            }
            throw ChatError.rateLimit(rateMsg)
        case 500..<600:
            throw ChatError.serverError
        default:
            throw ChatError.networkError("HTTP \(http.statusCode)")
        }

        // Anthropic-SSE-Format:
        //   event: <type>
        //   data: {"type":"...","delta":{"type":"text_delta","text":"..."}}
        //
        // Wir interessieren uns für `data:`-Lines mit `text_delta`-
        // Inhalten. Andere Events (ping, message_start, message_stop,
        // content_block_start/stop, usage-deltas) werden ignoriert.
        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let jsonStr = String(line.dropFirst("data: ".count))
            guard let data = jsonStr.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }

            let type = (json["type"] as? String) ?? ""

            if type == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               (delta["type"] as? String) == "text_delta",
               let textChunk = delta["text"] as? String {
                placeholder.text += textChunk
            } else if type == "message_stop" {
                return
            }
        }
    }
}
