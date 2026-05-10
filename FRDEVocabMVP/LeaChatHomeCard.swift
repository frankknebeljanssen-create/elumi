// LeaChatHomeCard.swift
// **Léa-Chat MVP Schritt 1 (2026-05-10)** — Home-Screen-Card für die
// „Live Chat"-Section. Zwei States:
//
//   • **noChat**: keine History — zentraler Avatar + „Sag bonjour zu
//     Léa" — kein Live-Dot, kein Timestamp.
//   • **hasHistory**: Last-Léa-Message als Bubble-Preview links neben
//     einem 60pt-Avatar, „LIVE" Pulsing-Dot oben links, Uhrzeit der
//     letzten Message rechts unten.
//
// Pre-Title CAPS „LIVE CHAT" + Pulsing-Dot (Brand-Anker), Card-Body
// schlicht (kein Eigenbau-3D-Card-Look). Tap auf die Card pusht
// `AppScreen.leaChat`.

import SwiftUI
import SwiftData

struct LeaChatHomeCard: View {
    let onTap: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Bindable private var chatService = ChatService.shared

    /// Letzte Léa-Message (für Preview im hasHistory-State).
    private var lastLeaMessage: ChatMessage? {
        chatService.messages.last(where: { $0.sender == .lea })
    }

    private var hasHistory: Bool { !chatService.messages.isEmpty }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 10) {
                preTitleRow

                contentRow
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Live Chat mit Léa")
        .onAppear {
            chatService.configure(with: modelContext)
        }
    }

    // MARK: - Pre-Title-Row

    private var preTitleRow: some View {
        HStack(spacing: 6) {
            if hasHistory {
                LivePulsingDot()
            }
            Text("LIVE CHAT")
                .font(.system(size: 11, weight: .black, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(Color(red: 0.357, green: 0.416, blue: 0.941)) // #5B6AF0
            Spacer(minLength: 0)
            if hasHistory, let timestamp = lastLeaMessage?.timestamp {
                Text(Self.timeFormatter.string(from: timestamp))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Content-Row

    @ViewBuilder
    private var contentRow: some View {
        if hasHistory, let last = lastLeaMessage {
            HStack(alignment: .top, spacing: 12) {
                ChatAvatarView(size: 48)

                Text(last.text)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            HStack(alignment: .center, spacing: 14) {
                ChatAvatarView(size: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat mit Léa")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102))
                    Text("Sag bonjour zu Léa 🇫🇷")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Helpers

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}

/// **Pulsing-Dot** — kleiner grüner Punkt, slow-pulse 1.5 s.
private struct LivePulsingDot: View {
    @State private var pulsing = false

    var body: some View {
        Circle()
            .fill(Color(red: 0.298, green: 0.788, blue: 0.490)) // grün
            .frame(width: 8, height: 8)
            .opacity(pulsing ? 0.4 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                    pulsing = true
                }
            }
    }
}
