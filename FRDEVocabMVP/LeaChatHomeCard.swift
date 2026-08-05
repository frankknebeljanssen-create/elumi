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
    ///
    /// **2026-06-09** — Solange Léa-Chat wegen Backend-Bug deaktiviert
    /// ist (`FeatureFlags.leaChatEnabled == false`), zeigt die Card
    /// immer den noHistory-State („Chat mit Léa" bold) statt einer
    /// stale Chat-Preview aus einem vorherigen Test. Nach dem Fix
    /// (Flag → `true`) erscheinen automatisch wieder echte Previews.
    private var lastLeaMessage: ChatMessage? {
        guard FeatureFlags.leaChatEnabled else { return nil }
        return chatService.messages.last(where: { $0.sender == .lea })
    }

    var body: some View {
        Button(action: onTap) {
            // **2026-08-05** — LIVE-Zeile ist von OBEN nach RECHTS
            // gewandert (User-Spec). Vorher stand sie als eigene Zeile
            // über dem Inhalt und machte die Card höher als Training,
            // Quiz und Daily Drop — sie war als einzige nicht auf
            // 72 pt mitgezogen worden. Rechts sitzt sie jetzt an
            // derselben Stelle wie die „Neu heute"-Pille beim Daily
            // Drop, wodurch die vier Cards konsistent aussehen.
            contentRow
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 72)
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

    // MARK: - LIVE-Pille (rechts)

    /// **2026-08-05** — ersetzt die frühere `preTitleRow` über dem
    /// Inhalt. Als Pille rechts kostet der Status keine eigene Zeile
    /// mehr, wodurch die Card dieselbe Höhe hat wie Training, Quiz und
    /// Daily Drop. Form bewusst wie die „Neu heute"-Pille beim Daily
    /// Drop, damit rechts auf allen Cards dieselbe Sprache steht.
    ///
    /// Der grüne Punkt plus „LIVE" sagt: Léa ist gerade erreichbar.
    private var livePill: some View {
        VStack(alignment: .trailing, spacing: 3) {
            HStack(spacing: 5) {
                Circle()
                    .fill(AppTheme.Colors.success)
                    .frame(width: 6, height: 6)
                Text("LIVE")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(0.8)
                    .foregroundStyle(AppTheme.Colors.success)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule().fill(AppTheme.Colors.success.opacity(0.16)))
            .overlay(Capsule().stroke(AppTheme.Colors.success.opacity(0.35), lineWidth: 1))

            // Zeitstempel — nur wenn Léa schon geantwortet hat.
            if let timestamp = lastLeaMessage?.timestamp {
                Text(Self.timeFormatter.string(from: timestamp))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
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
                    // **2026-06-09** — Titel „Chat mit Léa" → „Live-Chat"
                    // (User-Spec); Subtitle „Sag bonjour zu Léa" bleibt.
                    Text("Live-Chat")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(Color.white)
                    Text("Sag bonjour zu Léa 🇫🇷")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            livePill
        }
    }

    // MARK: - Avatar-Composit

    /// Avatar mit pulsierendem Mint-Ring + Online-Dot.
    /// Gemeinsame Subview — wird in noHistory + hasHistory identisch verwendet.
    private var leaAvatarComposit: some View {
        // Ring als Overlay direkt auf dem Avatar → Overlay-Content wird
        // immer auf dem Host zentriert, liegt also garantiert konzentrisch.
        // Vorher: flexible Circle ohne eigenen Frame neben dem fix
        // dimensionierten Avatar im ZStack → konnte minimal verrutschen
        // (Ring/„L" nicht exakt zentriert).
        ChatAvatarView(size: 40)
            .overlay {
                Circle()
                    .stroke(AppTheme.Colors.success.opacity(ringOpacity), lineWidth: 2)
                    .frame(width: 52, height: 52)
                    .scaleEffect(ringScale)
                    // 1 pt höher → gleicht den Avatar-Schatten (y:+1) optisch
                    // aus, damit der Ring exakt am L-Kreis sitzt (wirkte sonst
                    // minimal zu tief).
                    .offset(y: -1)
            }
            .frame(width: 52, height: 52)
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
