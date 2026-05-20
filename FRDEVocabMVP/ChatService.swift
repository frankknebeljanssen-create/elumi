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

    /// User-facing Meldung. Wird seit Sweep „Error-Handling Polish
    /// (2026-05-10)" NICHT mehr in die Léa-Bubble geschrieben, sondern
    /// vom `ChatErrorBannerView` über der Input-Bar gerendert. Der
    /// rateLimit-Variant trägt den Backend-Override-Text durch
    /// (z.B. „Du hast noch 3 Nachrichten heute"); für die anderen
    /// Cases kommt der lokale Default-Text.
    var userMessage: String {
        switch self {
        case .authError:
            return "Authentifizierungs-Problem — App neu starten."
        case .rateLimit(let msg):
            return msg
        case .serverError:
            return "Léa schläft gerade — versuch's gleich nochmal 💤"
        case .networkError:
            return "Léa hat gerade kein Netz 📵"
        case .invalidResponse:
            return "Léa antwortet komisch — versuch's gleich nochmal."
        }
    }

    /// **Sweep „Error-Banner" (2026-05-10)** — mappt jeden Error-Case
    /// auf eine Banner-Kind, die das `ChatErrorBannerView` für
    /// Hintergrund-Color + Icon nutzt.
    var bannerKind: ChatErrorBanner.Kind {
        switch self {
        case .authError: return .authFailed
        case .rateLimit: return .rateLimit
        case .serverError: return .serverError
        case .networkError, .invalidResponse: return .networkError
        }
    }
}

/// **Sweep „Error-Banner" (2026-05-10)** — Modell für die Error-
/// Banner-Anzeige über der Chat-Input-Bar. Identifizierbar via UUID,
/// damit der Auto-Dismiss-Timer den exakten Banner abhängig von der
/// ID identifizieren kann (sonst würde ein Folge-Banner durch den
/// Timer des vorherigen weggewischt).
struct ChatErrorBanner: Identifiable, Equatable {
    let id: UUID
    let message: String
    let kind: Kind

    enum Kind: Equatable {
        case rateLimit       // 429 — Léa hat heute genug, oder Per-Minute-Throttle
        case authFailed      // 401 — Token ungültig
        case serverError     // 5xx — Backend / Anthropic down
        case networkError    // URL-Error / Timeout / Invalid-Response
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

    /// **Sweep „Error-Banner" (2026-05-10)** — wenn nicht-nil, rendert
    /// ChatView den `ChatErrorBannerView` über der Input-Bar.
    /// Wird via `showErrorBanner(...)` gesetzt und nach 5 s automatisch
    /// auf `nil` zurückgewischt (sofern nicht ein neuer Banner schon
    /// dazwischenkommt — der Timer prüft die ID). Tap auf den Banner
    /// (`onDismiss`-Callback in ChatView) setzt ebenfalls direkt auf
    /// `nil`.
    var lastErrorBanner: ChatErrorBanner?

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
        // **Sweep „3A Bug-Fix Iter-2 / Bug E" (2026-05-10)** —
        // Greeting-Text wird jetzt nach Léa-Niveau gestaffelt
        // (Frank-Befund: das alte „Comment s'est passée ta journée ?"
        // war Passé composé und für A1-User über dem Niveau).
        // Niveau aus dem aktuellen `ChatVocabularyContext.level`
        // gelesen — bei nil-Context (Lektionswörter-Toggle off oder
        // keine Liste) Default A1.
        let level = currentVocabContext()?.level ?? .a1
        let greeting = Self.firstGreeting(for: level, hour: hour)

        // Kurzer Typing-Indicator-Spike, damit's natürlich wirkt.
        isTyping = true
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        isTyping = false

        appendLeaMessage(text: greeting)
    }

    /// **Sweep „3A Bug-Fix Iter-2 / Bug E"** — Niveau-staffelte
    /// Greeting-Tabelle. Frank's Spec:
    ///   • A1: simpel, Présent only, kurze Floskeln
    ///   • A2: Steigerung, „aujourd'hui" zugelassen
    ///   • B1/B2: aktueller Greeting-Pool inkl. Passé composé am
    ///     Abend („Comment s'est passée ta journée ?")
    ///
    /// Pure / static, damit Test/Preview-Aufrufe ohne Service-Instance
    /// möglich sind.
    static func firstGreeting(for level: ChatLevel, hour: Int) -> String {
        // B2 mappt auf B1-Pool — Frank's Spec sagt „gleiche wie B1".
        switch level {
        case .a1:
            switch hour {
            case ..<12:   return "Salut ! Bien dormi ?"
            case 12..<18: return "Salut ! Ça va ?"
            default:      return "Salut ! Bonne journée ?"
            }
        case .a2:
            switch hour {
            case ..<12:   return "Bonjour ! Bien dormi ?"
            case 12..<18: return "Salut ! Ça va aujourd'hui ?"
            default:      return "Salut ! Bonne journée aujourd'hui ?"
            }
        case .b1, .b2:
            switch hour {
            case ..<12:   return "Bonjour ! Bien dormi ?"
            case 12..<18: return "Salut ! Ça va aujourd'hui ?"
            default:      return "Bonsoir ! Comment s'est passée ta journée ?"
            }
        }
    }

    // MARK: - Session-End-Hooks (Schritt 3A, 2026-05-10)

    /// Wird vom `ChatSessionSummarySheet` in `.onAppear` aufgerufen,
    /// nachdem der Threshold erreicht ist. Drei Pflichten:
    ///   1. Auto-Sammlung der Korrekturen + neuen Wörter in den
    ///      Custom-VocabularyList „Aus Chat mit Léa".
    ///   2. +15 XP via `ProgressStore.mutate` direkt — wir umgehen
    ///      `ProgressService.record(session:)`, weil dessen
    ///      `correctCount × 10`-Math nicht zur Chat-Session passt
    ///      (eine Chat-Session hat keine klassische correct/wrong-
    ///      Zählung).
    ///   3. Streak-Hook via `DailyChallengeStore.recordSession(...)`
    ///      mit synthetischer LearningSession (origin: .leaChat).
    ///      Threshold-Regel sitzt in `LearningSession.meetsMinimumThreshold`.
    ///
    /// Idempotent ist NICHT gewährleistet: wenn der User das Sheet
    /// zweimal öffnet (was im aktuellen Flow nicht möglich ist —
    /// Sheet erscheint genau einmal pro Session-End), würde XP
    /// doppelt addiert. Sollte das jemals nötig werden: Session-ID-
    /// basiertes Throttling einführen.
    ///
    /// **Schritt 3A (γ-Spec)** — `duration` wird durchgereicht, damit
    /// die synthetische LearningSession den 1+Msg+5min-Pfad
    /// abbilden kann: bei kurzem Chat aber langer Dauer wird
    /// `correctCount` auf 5 inflatet, sodass `meetsMinimumThreshold`
    /// (`correctCount >= 5`) trotzdem greift.
    func recordSessionEnd(messages sessionMessages: [ChatMessage], duration: TimeInterval) {
        // 1) Auto-Sammlung
        collectChatItemsToStapel(from: sessionMessages)

        // 2) XP-Increment — direktes mutate, +15 fix.
        ProgressStore.shared.mutate { $0.totalXP += 15 }

        // 3) Streak-Hook. correctCount-Synthesis kodiert beide
        // Summary-Trigger-Pfade in einen Wert:
        //   • Pfad A (≥5 User-Messages): correctCount = userMsgCount
        //   • Pfad B (≥1 + ≥300 s):       correctCount = 5 (inflatet)
        // Beide hitten `meetsMinimumThreshold` (>=5) zuverlässig.
        // ChatView ruft diese Methode nur dann, wenn shouldShowSummary
        // schon true ist — ein Pfad muss daher zugetroffen sein.
        let userMsgCount = sessionMessages.filter { $0.sender == .user }.count
        let synthesizedCount: Int
        if userMsgCount >= 5 {
            synthesizedCount = userMsgCount
        } else if userMsgCount >= 1, duration >= 300 {
            synthesizedCount = 5
        } else {
            // Defensive Fallback — sollte nie greifen, weil ChatView
            // den Pre-Check macht. Setzen auf 5, damit Streak-Hook
            // trotzdem feuert (User hat das Sheet gesehen, also
            // qualifiziert).
            synthesizedCount = 5
        }
        let synthetic = LearningSession(
            origin: .leaChat,
            correctCount: synthesizedCount
        )
        _ = DailyChallengeStore.shared.recordSession(synthetic)
    }

    /// Iteriert die Session-Messages und packt jedes Korrektur-Pair
    /// + jedes neue Léa-Wort als VocabularyItem in den Chat-Stapel.
    /// Skippt silent bei nil-listStore (z.B. wenn der Service nur
    /// vom HomeCard ohne Store konfiguriert wurde).
    private func collectChatItemsToStapel(from sessionMessages: [ChatMessage]) {
        guard let listStore else { return }

        // Korrektur-Cards: from User-Messages mit foundError-Felder.
        // Front (German): Tipp mit ___-Blank wo die korrekte
        // französische Form steht. Back (French): die extrahierte
        // Form — oder leer, wenn der Tipp keine Quoted-Form
        // enthielt (User pflegt nach).
        for msg in sessionMessages where msg.sender == .user {
            guard let germanTip = msg.foundErrorGermanTip else { continue }
            let card = Self.makeCorrectionCard(germanTip: germanTip)
            listStore.addChatStapelItem(
                french: card.french,
                german: card.german,
                cardType: .phrases
            )
        }

        // Neue-Wörter-Cards: from Léa-Messages mit newWords.
        // Front (German) = translation, Back (French) = word.
        for msg in sessionMessages where msg.sender == .lea {
            for newWord in msg.newWords {
                listStore.addChatStapelItem(
                    french: newWord.word,
                    german: newWord.translation,
                    cardType: .words
                )
            }
        }
    }

    /// Extrahiert eine (front/german, back/french)-Karten-Struktur
    /// aus einem Korrektur-Tipp. Erwartet, dass die korrekte
    /// französische Form in einer Quote-Form im Tipp steht
    /// (`'à l'école'`, `"au école"`, `«école»`, `„école"` etc.).
    ///
    /// **Schritt 3A Smoke-Fix Bug A (2026-05-10)** — vorher returnt
    /// die Methode `nil` bei Quote-Extraction-Failure und der Caller
    /// hat die Karte stillschweigend geskipped. Frank's Smoke
    /// („chien"-Korrektur fehlt im Stapel) zeigt: bei Tipps ohne
    /// Quotes (z.B. „Plural braucht ein s: chiens") fällt die Karte
    /// hinten runter. Jetzt: bei Failure returnt die Methode immer
    /// noch eine Card, mit `french=""` und `german=germanTip`. Der
    /// User kann den Französisch-Teil manuell in Listen-Edit
    /// nachpflegen; die Karte ist „besser unfertig im Stapel als
    /// gar nicht da".
    ///
    /// Result-Pattern bei erfolgreicher Quote-Extraction: deutsche
    /// Aufgabe = Tipp mit Quoted-Segment durch `___` ersetzt
    /// (Lückentext-Charakter); französische Antwort = extrahierte
    /// Quoted-Form.
    private static func makeCorrectionCard(
        germanTip: String
    ) -> (french: String, german: String) {
        let quotePairs: [(open: Character, close: Character)] = [
            ("'", "'"),     // ASCII single
            ("\"", "\""),   // ASCII double
            ("„", "\u{201C}"), // German curly («Anführungszeichen unten/oben rechts»)
            ("«", "»"),     // French guillemets
            ("\u{2018}", "\u{2019}"), // typographic single
            ("\u{201C}", "\u{201D}"), // typographic double
        ]
        for pair in quotePairs {
            guard let openIdx = germanTip.firstIndex(of: pair.open) else { continue }
            let afterOpen = germanTip.index(after: openIdx)
            guard afterOpen < germanTip.endIndex,
                  let closeIdx = germanTip[afterOpen...].firstIndex(of: pair.close)
            else { continue }
            let extracted = String(germanTip[afterOpen..<closeIdx])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !extracted.isEmpty else { continue }

            // Quote-Segment durch ___-Blank ersetzen.
            var blanked = germanTip
            let segmentRange = openIdx...closeIdx
            blanked.replaceSubrange(segmentRange, with: "___")
            let blankedTrimmed = blanked.trimmingCharacters(in: .whitespacesAndNewlines)
            return (french: extracted, german: blankedTrimmed)
        }
        // **Bug A Fallback** — keine Quoted-Form gefunden. Karte
        // landet trotzdem im Stapel: deutscher Tipp 1:1, französische
        // Seite leer (User editiert manuell wenn er üben will).
        return (french: "", german: germanTip.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    // MARK: - Error-Banner-Helpers (Sweep „Error-Banner", 2026-05-10)

    /// Setzt einen neuen Error-Banner und plant den Auto-Dismiss
    /// nach 5 Sekunden. Der Auto-Dismiss prüft die Banner-ID, sodass
    /// ein nachfolgender Banner durch den Timer des vorherigen NICHT
    /// versehentlich gelöscht wird (häufiger Race-Bug bei naiven
    /// Auto-Hide-Implementierungen).
    private func showErrorBanner(message: String, kind: ChatErrorBanner.Kind) {
        let banner = ChatErrorBanner(id: UUID(), message: message, kind: kind)
        lastErrorBanner = banner

        let bannerID = banner.id
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self else { return }
            if self.lastErrorBanner?.id == bannerID {
                self.lastErrorBanner = nil
            }
        }
    }

    /// Entfernt eine halb-gestreamte oder leere Léa-Placeholder-
    /// Message aus dem Stream (modelContext + messages-Array). Wird
    /// vom Error-Catch-Pfad in `sendMessage` aufgerufen, damit der
    /// User keinen unfinished/empty Léa-Bubble sieht — Banner
    /// erklärt stattdessen, was schief gelaufen ist.
    private func discardLeaPlaceholder(_ leaMsg: ChatMessage) {
        if let modelContext {
            modelContext.delete(leaMsg)
        }
        messages.removeAll { $0.id == leaMsg.id }
        try? modelContext?.save()
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
            // **Bug-K/L Smoke-Diagnose (2026-05-10)** — DEBUG-only Log
            // des roh-Léa-Outputs vor Parsing. Hilft beim Smoke zu sehen,
            // ob Sonnet die „ABSOLUTE REGEL — nur ein FEHLER-Marker"
            // einhält und wie VOCAB/NEW-Marker positioniert sind.
            // `appDebugLog` ist `#if DEBUG`-gated in Release ein no-op.
            appDebugLog("📩 [LeaRaw] \(leaMsg.text)")
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
            // **Sweep „Error-Banner" (2026-05-10)** — Backend-Errors
            // landen jetzt als Banner über der Input-Bar, NICHT mehr
            // als Léa-Bubble. Die leere/halb-gestreamte Léa-Message
            // wird gelöscht, sodass der User keinen halben Satz sieht.
            self.error = chatError
            discardLeaPlaceholder(leaMsg)
            showErrorBanner(message: chatError.userMessage, kind: chatError.bannerKind)
        } catch {
            // Generischer Catch für URLError/Timeout/sonstige Throws.
            // Wir wrappen in ChatError.networkError, damit Banner-
            // Kind und Message konsistent zur ChatError-Mapping
            // bleiben.
            let wrapped = ChatError.networkError(error.localizedDescription)
            self.error = wrapped
            discardLeaPlaceholder(leaMsg)
            showErrorBanner(message: wrapped.userMessage, kind: wrapped.bannerKind)
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
                // **Bug Q (2026-05-20)** — Correction-State in die History
                // injizieren: an User-Turns mit bereits erfolgter Korrektur
                // hängen wir einen kompakten `[Bereits korrigiert: …]`-Tag an.
                // So „sieht" Sonnet, dass der rohe Fehler in der History
                // schon behandelt wurde, und korrigiert ihn nicht erneut
                // (siehe ZWEITE ABSOLUTE REGEL im System-Prompt). Der Tag
                // geht NUR ins outbound Array — die UI rendert weiter den
                // rohen `msg.text`.
                if msg.sender == .user {
                    var content = msg.text
                    if let original = msg.foundErrorUserText, !original.isEmpty {
                        content += "\n\n[Bereits korrigiert: \(original)]"
                    }
                    return ["role": "user", "content": content]
                } else {
                    return ["role": "assistant", "content": msg.text]
                }
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
            //
            // **Sweep „Error-Banner" (2026-05-10)** — der Text
            // erscheint jetzt im Banner über der Input-Bar (nicht
            // mehr als Léa-Bubble), daher ist die persona-narrative
            // Form wieder vertretbar — der visuelle Banner-Kontext
            // macht klar, dass das eine System-Meldung ist.
            var rateMsg = "Léa muss heute schlafen — bis morgen! 😴"
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
