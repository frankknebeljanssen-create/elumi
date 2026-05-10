// ChatView.swift
// **Léa-Chat MVP Schritt 1 (2026-05-10)** — Hauptscreen für die
// Konversation mit Léa. VStack(Header, Body, InputBar) im WhatsApp-/
// iMessage-Look — strikt KEINE Elumi-Card-Tokens im Body.
//
// **Lifecycle**:
//   • `.task`: ChatService.configure(with: modelContext) +
//     ensureFirstGreeting (nur wenn History leer).
//   • Auto-Scroll bei neuer Message via ScrollViewReader.
//
// **Streaming-Render**: ChatBubbleView bekommt
// `isStreaming: chatService.streamingMessageID == message.id` —
// blinkender Cursor erscheint nur an der laufenden Léa-Bubble.

import SwiftUI
import SwiftData
import UIKit

struct ChatView: View {
    let onBack: () -> Void

    /// **Schritt 2B-1 (2026-05-10)** — Listen-Store für die Wortschatz-
    /// Auflösung im Chat-System-Prompt. Wird vom `AppDestinationHost`
    /// aus `runtime.listStore` durchgereicht. Optional, weil
    /// `runtime.listStore` selbst optional ist (async-Bootstrapping);
    /// bei `nil` blockt ChatService den Send via `needsListSelection`.
    let listStore: VocabularyListStore?

    @Environment(\.modelContext) private var modelContext
    /// **Léa-Chat MVP — Polish (2026-05-10)** — Closure, mit der
    /// ChatView den globalen Footer ausblendet, solange das System-
    /// Keyboard sichtbar ist. Wird im `RootContentView` installiert
    /// und schreibt in den `AppNavigationCoordinator`. `nil` außerhalb
    /// der App-Hauptnavigation (Previews, Tests) → no-op.
    @Environment(\.appSetChatKeyboardActiveAction) private var setChatKeyboardActive
    @Bindable private var chatService = ChatService.shared

    @State private var inputText: String = ""
    @State private var isSettingsSheetPresented: Bool = false
    /// **Schritt 2A (2026-05-10)** — Confirmation-State für den
    /// Reset-Button im Settings-Sheet. Verhindert versehentliches
    /// Wegwischen des Chat-Verlaufs durch Fat-Finger-Tap.
    @State private var isResetConfirmPresented: Bool = false
    /// **Schritt 2B-2A (2026-05-10)** — Lektionswörter-Fokus-Toggle.
    /// Default `true` (Fresh-Install zeigt Toggle als ON; Provider
    /// liest UserDefaults direkt mit demselben Default).
    @AppStorage(appLeaFocusOnLessonKey) private var leaFocusOnLesson: Bool = true
    /// **Schritt 2B-1 (2026-05-10)** — wenn nicht-nil, zeigt ChatView
    /// einen Tooltip-Overlay über dem Chat. Wird gesetzt, wenn der
    /// User auf ein blau unterstrichenes neues Wort in einer Léa-
    /// Bubble tippt (Custom-URL-Scheme `leanew://wort`).
    @State private var activeTooltipNewWord: FoundNewWord?
    /// **Bug-Fix Smoke-Iter 2 (2026-05-10)** — `keyboardWillShow`
    /// feuert nicht nur bei der initialen Tastatur-Einblendung,
    /// sondern auch bei jeder Frame-Änderung (Predictive-Bar an/aus,
    /// Keyboard-Wechsel, Memoji-Anzeige). Wenn wir bei jedem Event
    /// scrollToBottom triggerten, wurde der User beim Hochscrollen
    /// zurückgerissen. Diesen Flag tracken wir manuell, sodass
    /// scrollToBottom NUR auf die Transition `hidden → visible`
    /// feuert — nicht auf Frame-Updates während die Tastatur schon
    /// up ist.
    @State private var keyboardWasVisible: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(
                persona: chatService.currentPersona,
                onBack: onBack,
                onSettings: { isSettingsSheetPresented = true }
            )

            messagesScroll

            ChatInputBar(
                text: $inputText,
                isSendDisabled: !canSend,
                onSend: handleSend
            )
        }
        // Body-Background = WhatsApp-Style (#F2F2F7) — KEIN Elumi-
        // surface, kein Card-Background. Strikter UI-Anker.
        .background(Color(red: 0.949, green: 0.949, blue: 0.969).ignoresSafeArea(edges: .bottom))
        // **Schritt 2B-1 (2026-05-10)** — Tooltip-Overlay über dem
        // gesamten Chat. Wird nur gerendert wenn ein NEW-Wort
        // angetippt wurde. Tap auf den Hintergrund (außer den
        // Tooltip selbst) dismissed das Overlay.
        .overlay {
            if let nw = activeTooltipNewWord {
                ZStack {
                    // Dim-Background mit Tap-to-dismiss.
                    Color.black.opacity(0.18)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.easeOut(duration: 0.15)) {
                                activeTooltipNewWord = nil
                            }
                        }
                    ChatNewWordTooltipView(
                        word: nw.word,
                        translation: nw.translation,
                        onClose: {
                            withAnimation(.easeOut(duration: 0.15)) {
                                activeTooltipNewWord = nil
                            }
                        }
                    )
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
                }
                .zIndex(100)
            }
        }
        // **Schritt 2B-1** — Custom-URL-Handler für `leanew://wort`.
        // Léa-Bubbles enkodieren das NEW-Wort als URL-Link auf der
        // jeweiligen Substring-Range. Tap → dieser Handler fängt
        // das URL-Event ab, sucht das passende `FoundNewWord` in
        // den persistierten Léa-Messages (rückwärts, neueste zuerst)
        // und öffnet den Tooltip.
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "leanew" else { return .systemAction }
            let host = url.host?.removingPercentEncoding ?? ""
            for msg in chatService.messages.reversed() {
                if let nw = msg.newWords.first(where: { $0.word == host }) {
                    withAnimation(.easeOut(duration: 0.18)) {
                        activeTooltipNewWord = nw
                    }
                    return .handled
                }
            }
            // URL „gegessen", aber kein Match — fallback: einfach
            // schlucken statt Safari zu öffnen.
            return .handled
        })
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            // **Schritt 2B-1** — `listStore` wird beim Configure
            // mit reingegeben, damit der `ChatVocabularyProvider`
            // beim nächsten `sendMessage` die aktive Listen-Auswahl
            // auflösen kann. Bei nil-Store läuft der Send-Pfad in
            // `needsListSelection` → ChatView's Modal triggert.
            chatService.configure(with: modelContext, listStore: listStore)
            await chatService.ensureFirstGreeting()
        }
        // **Schritt 2B-1** — Listen-Auswahl-Modal. ChatService setzt
        // `needsListSelection = true` wenn beim ersten Greet/Send
        // keine aktive Liste resolved werden kann. Wir presenten den
        // existing `GlobalListPickerSheet` mit einem dünnen Header-
        // Text obendrauf. Nach Dismiss prüfen wir, ob der User
        // tatsächlich eine Liste gewählt hat — wenn nicht, popen wir
        // ChatView zurück zu Home (Frank's Spec).
        .sheet(
            isPresented: Binding(
                get: { chatService.needsListSelection },
                set: { newValue in
                    if !newValue { chatService.needsListSelection = false }
                }
            ),
            onDismiss: {
                Task {
                    if chatService.currentVocabContext() == nil {
                        // User hat trotz Modal keine Liste gewählt
                        // (Abbrechen-Tap oder Drag-down). Léa kann
                        // ohne Wortschatz nicht starten → zurück
                        // zu Home.
                        onBack()
                    } else {
                        chatService.needsListSelection = false
                        await chatService.ensureFirstGreeting()
                    }
                }
            }
        ) {
            listSelectionSheetContent
        }
        // **Léa-Chat MVP — Keyboard-Footer-Hide (2026-05-10)**
        // Während das System-Keyboard sichtbar ist, blenden wir den
        // globalen App-Footer (AppBottomBar in RootContentView) aus —
        // sonst kollidiert er optisch mit der Chat-Input-Bar und
        // bricht den WhatsApp-Look. `keyboardWillShowNotification`
        // feuert SYNCHRON zur iOS-Keyboard-Slide-Animation, das
        // 0.25-s-easeOut auf RootContentView läuft parallel → smooth.
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            setChatKeyboardActive?(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            setChatKeyboardActive?(false)
            // Reset des Visibility-Trackers, damit beim NÄCHSTEN
            // Tap auf das TextField wieder einmalig scrollToBottom
            // im messagesScroll feuern kann.
            keyboardWasVisible = false
        }
        .onDisappear {
            // **Cleanup-Guard**: User verlässt ChatView (Back-Tap)
            // während Keyboard noch up — `keyboardWillHide` feuert
            // u.U. NACHDEM die View aus dem Hierarchy-Tree raus ist.
            // Hier explizit auf false setzen, damit der Footer auf
            // den nachfolgenden Screens (Home etc.) garantiert wieder
            // erscheint.
            setChatKeyboardActive?(false)
        }
        .sheet(isPresented: $isSettingsSheetPresented) {
            // **Schritt 2A (2026-05-10)** — Sheet erweitert um den
            // Smoke-Helper „Chat-Verlauf zurücksetzen" (siehe
            // `ChatService.resetHistory()`).
            //
            // **Schritt 2B-2A (2026-05-10)** — Toggle „Lektionswörter
            // benutzen" oben drüber, mit erklärendem Subtitle. Toggle
            // schreibt via @AppStorage in `appLeaFocusOnLessonKey`
            // → der `ChatVocabularyProvider` liest beim nächsten
            // Send/Greet diesen Wert frisch und schaltet dann zwischen
            // „Wortschatz-Fokus" und „freier Konversation" hin und her.
            VStack(alignment: .leading, spacing: 20) {
                Text("Einstellungen")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .center)

                // **Toggle-Row** — schlichte iOS-Settings-Anmutung,
                // keine Elumi-Card-Tokens. Title + Subtitle untereinander,
                // Toggle rechts.
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Lektionswörter benutzen")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Léa nutzt deine aktive Wortliste")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: $leaFocusOnLesson)
                        .labelsHidden()
                }
                .padding(.vertical, 4)

                Divider()

                Button(role: .destructive) {
                    isResetConfirmPresented = true
                } label: {
                    Label("Chat-Verlauf zurücksetzen", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .disabled(chatService.streamingMessageID != nil || chatService.isTyping)

                Button("Schließen") {
                    isSettingsSheetPresented = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .presentationDetents([.medium])
            .confirmationDialog(
                "Chat-Verlauf wirklich zurücksetzen?",
                isPresented: $isResetConfirmPresented,
                titleVisibility: .visible
            ) {
                Button("Zurücksetzen", role: .destructive) {
                    chatService.resetHistory()
                    isSettingsSheetPresented = false
                    // Frische First-Greeting nach dem Wipe — die
                    // Konversation soll nicht leer dastehen, sondern
                    // sofort wieder mit Léas Begrüßung anfangen.
                    Task {
                        await chatService.ensureFirstGreeting()
                    }
                }
                Button("Abbrechen", role: .cancel) {}
            } message: {
                Text("Alle bisherigen Nachrichten werden gelöscht. Léa fängt frisch an.")
            }
        }
    }

    // MARK: - Listen-Auswahl-Sheet (Schritt 2B-1)

    /// Inhalt des Modal-Sheets, das beim Fehlen einer aktiven Liste
    /// erscheint. Header-Text als Léa-spezifische Erklärung, drunter
    /// der existing `GlobalListPickerSheet` (P2-Backlog: laut Frank's
    /// vorigem Feedback „etwas zu groß auf Screen" — pragmatisch
    /// trotzdem nutzen, Optimierung in einem späteren Sweep).
    @ViewBuilder
    private var listSelectionSheetContent: some View {
        if let listStore {
            VStack(spacing: 0) {
                Text("Wähle eine Liste, damit Léa weiß, was du gerade übst.")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color(red: 0.4, green: 0.4, blue: 0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(Color(red: 0.973, green: 0.973, blue: 0.980))

                GlobalListPickerSheet(
                    allLists: listStore.allLists,
                    initialSelection: VocabularyListSelectionResolver.currentGlobalSelectedListIDs() ?? [],
                    onCommit: { _ in
                        // Resolver persistiert bereits in
                        // `setGlobalSelectedListIDs`; nichts weiter
                        // zu tun. ChatView's `onDismiss` triggert
                        // dann den Greet-Pfad.
                    }
                )
            }
        } else {
            // Defensiver Fallback — listStore wird vom
            // AppDestinationHost durchgereicht und sollte hier
            // immer gesetzt sein. Falls nicht: kurzes Info-Sheet
            // mit Zurück-Button, damit der User nicht stuck ist.
            VStack(spacing: 16) {
                Text("Listen werden geladen — bitte gleich nochmal versuchen.")
                    .font(.system(size: 15, weight: .medium))
                    .multilineTextAlignment(.center)
                Button("Zurück") {
                    chatService.needsListSelection = false
                    onBack()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(40)
        }
    }

    // MARK: - Messages-Scroll

    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    Spacer().frame(height: 8)

                    ForEach(chatService.messages, id: \.id) { msg in
                        ChatBubbleView(
                            message: msg,
                            isStreaming: chatService.streamingMessageID == msg.id
                        )
                        .id(msg.id)

                        // **Schritt 2A — CorrectionCard zwischen User-
                        // Bubble und Léa-Antwort**
                        // Wenn die User-Message vom Stream-End-Parser
                        // einen Korrektur-Tipp bekommen hat, wird hier
                        // direkt nach der User-Bubble eine
                        // CorrectionCardView eingeblendet. Da messages
                        // nach dem Stream `[…, userMsg, leaMsg]` ist,
                        // landet die Card visuell zwischen User-Bubble
                        // und Léa-Antwort.
                        //
                        // Identity = `correctionCardId` → Slide-In-
                        // Transition feuert genau einmal beim Erscheinen.
                        // Beim App-Restart (persisted) erscheint die
                        // Card ohne Animation, weil das ForEach sie
                        // im initial-render-Pass mitbringt — kein
                        // Insertion-Event.
                        if msg.sender == .user,
                           let tip = msg.foundErrorGermanTip,
                           let cardID = msg.correctionCardId {
                            CorrectionCardView(germanTip: tip)
                                .id(cardID)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .top)
                                        .combined(with: .opacity),
                                    removal: .opacity
                                ))
                                .padding(.vertical, 4)
                        }
                    }

                    if chatService.isTyping {
                        ChatTypingIndicatorView()
                            .id(typingAnchorID)
                    }

                    Spacer().frame(height: 8)
                }
            }
            .onChange(of: chatService.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: chatService.isTyping) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            // **Bug-Fix Smoke-Iter 2 (2026-05-10) — v2**
            // Erste Variante feuerte auf JEDES `keyboardWillShow`,
            // das iOS aber auch bei Frame-Updates der schon-sichtbaren
            // Tastatur sendet (Predictive-Bar, Keyboard-Switch).
            // Dadurch wurde der User beim Versuch, ältere Léa-Bubbles
            // hochzuscrollen, jedes Mal zurückgerissen → Inhalt
            // rutschte immer wieder unter die Tastatur (Smoke-Bug
            // 2026-05-10).
            //
            // Fix: Trigger NUR auf die Transition `hidden → visible`
            // via lokalem `keyboardWasVisible`-Flag. Beim
            // `keyboardWillHide` wird der Flag zurückgesetzt
            // (oben im View-Body), sodass beim nächsten Tap auf
            // das TextField wieder einmalig auf-Bottom gescrollt
            // wird. Während die Tastatur up ist, kann der User
            // jetzt frei nach oben scrollen.
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
                guard !keyboardWasVisible else { return }
                keyboardWasVisible = true
                withAnimation(.easeOut(duration: 0.25)) {
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
            .onAppear {
                // Anfangs sofort auf Bottom — bei wiederholten Visits
                // erscheint der Chat dann beim letzten Token, nicht
                // beim Top.
                DispatchQueue.main.async {
                    scrollToBottom(proxy: proxy, animated: false)
                }
            }
        }
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        let target: AnyHashable = chatService.isTyping
            ? AnyHashable(typingAnchorID)
            : AnyHashable(chatService.messages.last?.id ?? UUID())
        if animated {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo(target, anchor: .bottom)
            }
        } else {
            proxy.scrollTo(target, anchor: .bottom)
        }
    }

    private let typingAnchorID = "chat.typing.anchor"

    // MARK: - Send-Logic

    private var canSend: Bool {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && chatService.streamingMessageID == nil && !chatService.isTyping
    }

    private func handleSend() {
        let toSend = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !toSend.isEmpty else { return }
        inputText = ""
        Task {
            await chatService.sendMessage(toSend)
        }
    }
}
