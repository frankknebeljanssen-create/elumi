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

struct ChatView: View {
    let onBack: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Bindable private var chatService = ChatService.shared

    @State private var inputText: String = ""
    @State private var isSettingsSheetPresented: Bool = false

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
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            chatService.configure(with: modelContext)
            await chatService.ensureFirstGreeting()
        }
        .sheet(isPresented: $isSettingsSheetPresented) {
            // Schritt 1: leerer Placeholder-Sheet. Inhalt (Persona-
            // Wahl, Level-Toggle, History-Reset) kommt in späteren
            // Schritten. Geöffnet halten, Zugriff blockt nichts.
            VStack(spacing: 16) {
                Text("Einstellungen")
                    .font(.system(size: 22, weight: .black, design: .rounded))
                Text("Persona-Settings folgen in Schritt 2.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                Button("Schließen") {
                    isSettingsSheetPresented = false
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 12)
            }
            .padding(40)
            .presentationDetents([.medium])
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
