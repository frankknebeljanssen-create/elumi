// LeaChatHomeCard.swift
// **Léa-Chat MVP Schritt 1 (2026-05-10)** — Home-Screen-Card für die
// „Live Chat"-Section. Zwei States:
//
//   • **noChat**: keine Léa-History — Fallback "Chat mit Léa" /
//     "Sag bonjour zu Léa 🇫🇷".
//   • **hasHistory**: Letzte Léa-Nachricht als Preview + Zeitstempel.
//
// Beide States: identischer Glas-Look (AppTheme.Gradients.leaChatGlass),
// gleicher leaAvatarComposit (pulsierender Mint-Ring + Online-Dot),
// gleicher Pre-Title ("● LIVE CHAT" in success). Unterschied nur im
// Text-Inhalt des Content-Bereichs — gesteuert über `lastLeaMessage`.
//
// **Glass Redesign (2026-05-22)** — noHistory auf Glas-Look umgebaut.
// **Glass hasHistory (2026-05-22)** — hasHistory auf identischen
// Glas-Look gebracht; gemeinsame Card-Chrome, Avatar-Composit als
// geteilte private Subview. LivePulsingDot entfernt (nicht mehr nötig).

import SwiftUI
import SwiftData

struct LeaChatHomeCard: View {
    let onTap: () -> Void

    @Environment(\.modelContext) private var modelContext
    @Bindable private var chatService = ChatService.shared

    /// Avatar-Ring — scale-Animation (1.0 → 1.12).
    @State private var ringScale: CGFloat = 1.0
    /// Avatar-Ring — opacity-Animation (0.6 → 0.15).
    @State private var ringOpacity: Double = 0.6

    /// Letzte Léa-Message — steuert Content-Row-Inhalt + Zeitstempel.
    /// nil = noHistory (keine Léa-Nachricht vorhanden).
    private var lastLeaMessage: ChatMessage? {
        chatService.messages.last(where: { $0.sender == .lea })
    }

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
            // Glas-Chrome — identisch für beide States, kein Ternary.
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppTheme.Gradients.leaChatGlass)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(AppTheme.Colors.success.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: AppTheme.Colors.success.opacity(0.15), radius: 4, x: 0, y: 2)
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
            Circle()
                .fill(AppTheme.Colors.success)
                .frame(width: 7, height: 7)
            Text("LIVE CHAT")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .tracking(1.0)
                .foregroundStyle(AppTheme.Colors.success)
            Spacer(minLength: 0)
            // Zeitstempel — nur wenn Léa schon geantwortet hat.
            if let timestamp = lastLeaMessage?.timestamp {
                Text(Self.timeFormatter.string(from: timestamp))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
    }

    // MARK: - Content-Row

    @ViewBuilder
    private var contentRow: some View {
        HStack(alignment: .center, spacing: 14) {
            leaAvatarComposit

            VStack(alignment: .leading, spacing: 2) {
                if let last = lastLeaMessage {
                    // hasHistory — echte letzte Léa-Nachricht, hell + truncated.
                    Text(last.text)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    // noHistory — Einladungs-Fallback.
                    Text("Chat mit Léa")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)
                    Text("Sag bonjour zu Léa 🇫🇷")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: - Avatar-Composit

    /// Avatar mit pulsierendem Mint-Ring + Online-Dot.
    /// Gemeinsame Subview — wird in noHistory + hasHistory identisch verwendet.
    private var leaAvatarComposit: some View {
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
    }

    // MARK: - Helpers

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()
}
