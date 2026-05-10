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

    // MARK: - Dependencies

    private(set) var modelContext: ModelContext?

    private init() {}

    // MARK: - Configuration

    /// Muss einmalig aufgerufen werden (typischerweise vom Root-View
    /// per `.onAppear` mit `\.modelContext` aus dem Environment),
    /// bevor sendMessage / loadHistory funktionieren. Idempotent —
    /// mehrfache Aufrufe sind ok.
    func configure(with context: ModelContext) {
        self.modelContext = context
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

    // MARK: - First-Greeting

    /// Wenn die Konversation leer ist, schickt Léa eine tageszeit-
    /// abhängige Begrüßung — KEIN Backend-Call, der Greet-Text ist
    /// canned (spart Rate-Limit-Quota für reale Antworten).
    func ensureFirstGreeting() async {
        guard messages.isEmpty else { return }

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

    // MARK: - Send + Stream

    /// Schickt eine User-Message ans Backend, fügt einen Léa-
    /// Placeholder ein, streamt die Antwort live in den Placeholder.
    /// Der Aufrufer kann das Ergebnis abwarten, muss aber nicht — die
    /// `@Observable`-State-Updates propagieren automatisch.
    func sendMessage(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

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
            try await streamLeaResponse(into: leaMsg)
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
    private func streamLeaResponse(into placeholder: ChatMessage) async throws {
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
        let body: [String: Any] = [
            "system": currentPersona.buildSystemPrompt(),
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
