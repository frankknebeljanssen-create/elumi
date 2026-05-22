// LeaChatHomeCard.swift
// **Léa-Chat MVP Schritt 1 (2026-05-10)** — Home-Screen-Card für die
// „Live Chat"-Section. Zwei States:
//
//   • **noChat**: keine History — dunkler Glas-Look (AppTheme.Gradients
//     .leaChatGlass), Avatar mit pulsierendem Mint-Ring + Online-Dot,
//     weißer Text, Mint „● LIVE CHAT".
//   • **hasHistory**: Last-Léa-Message als Bubble-Preview links neben
//     einem 40pt-Avatar, „LIVE" Pulsing-Dot oben links, Uhrzeit der
//     letzten Message rechts unten. Helles Card-Design (unverändert).
//
// **Glass Redesign (2026-05-22)** — noHistory-State: BG auf
// AppTheme.Gradients.leaChatGlass umgebaut, Mint-Border + -Shadow,
// Avatar-Ring (scale 1→1.12, opacity 0.6→0.15, 2 s), Online-Dot 12 pt,
// Texte auf weiß. hasHistory-State bleibt unverändert.

import SwiftUI
import SwiftData

struct LeaChatHomeCard: View {
    let onTap: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Bindable private var chatService = ChatService.shared

    /// Avatar-Ring — scale-Animation (1.0 → 1.12). Nur noHistory-State.
    @State private var ringScale: CGFloat = 1.0
    /// Avatar-Ring — opacity-Animation (0.6 → 0.15). Nur noHistory-State.
    @State private var ringOpacity: Double = 0.6

    /// Letzte Léa-Message (für Preview im hasHistory-State).
    private var lastLeaMessage: ChatMessage? {
        chatService.messages.last(where: { $0.sender == .lea })
    }

    private var hasHistory: Bool { !chatService.messages.isEmpty }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                preTitleRow
                contentRow
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 86)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(hasHistory
                          ? AnyShapeStyle(Color.white)
                          : AnyShapeStyle(AppTheme.Gradients.leaChatGlass))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        hasHistory
                            ? Color.black.opacity(0.06)
                            : AppTheme.Colors.success.opacity(0.3),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: hasHistory
                    ? .black.opacity(0.05)
                    : AppTheme.Colors.success.opacity(0.15),
                radius: 4, x: 0, y: 2
            )
        }
        .buttonStyle(AppCardPressStyle())
        .accessibilityLabel("Live Chat mit Léa")
        .onAppear {
            chatService.configure(with: modelContext)
        }
    }

    // MARK: - Pre-Title-Row

    private var preTitleRow: some View {
        HStack(spacing: 6) {
            if hasHistory {
                // hasHistory — unverändert: pulsierender grüner Dot + blauer Label.
                LivePulsingDot()
                Text("LIVE CHAT")
                    .font(.system(size: 11, weight: .black, design: .rounded))
                    .tracking(1.4)
                    .foregroundStyle(Color(red: 0.357, green: 0.416, blue: 0.941)) // #5B6AF0
            } else {
                // noHistory — statischer Mint-Dot + Mint-Label (auf dunklem Glas).
                Circle()
                    .fill(AppTheme.Colors.success)
                    .frame(width: 7, height: 7)
                Text("LIVE CHAT")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(1.0)
                    .foregroundStyle(AppTheme.Colors.success)
            }
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
            // hasHistory — unverändert: Nachrichtenvorschau auf hellem Card-BG.
            HStack(alignment: .center, spacing: 12) {
                ChatAvatarView(size: 40)

                Text(last.text)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102))
                    .lineLimit(1)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            // noHistory — Glas-Look: Avatar mit pulsierendem Ring + Online-Dot,
            // weißer Titel + Subtitle.
            HStack(alignment: .center, spacing: 14) {
                // Avatar-Composit: Ring (ZStack) + Online-Dot (overlay).
                ZStack {
                    // Pulsierender Mint-Ring hinter dem Avatar.
                    Circle()
                        .stroke(AppTheme.Colors.success.opacity(ringOpacity), lineWidth: 2)
                        .scaleEffect(ringScale)

                    ChatAvatarView(size: 40)
                }
                .frame(width: 52, height: 52)
                .overlay(alignment: .bottomTrailing) {
                    // Online-Dot — 12 pt Mint-Kreis mit dunklem Rand.
                    Circle()
                        .fill(AppTheme.Colors.success)
                        .frame(width: 12, height: 12)
                        .overlay(
                            Circle()
                                .stroke(AppTheme.Colors.background, lineWidth: 1.5)
                        )
                }
                .onAppear {
                    withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
                        ringScale  = 1.12
                        ringOpacity = 0.15
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Chat mit Léa")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)
                    Text("Sag bonjour zu Léa 🇫🇷")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
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
/// Verwendet ausschließlich im hasHistory-State (preTitleRow).
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
