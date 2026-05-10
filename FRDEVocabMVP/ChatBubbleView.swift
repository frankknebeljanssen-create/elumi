// ChatBubbleView.swift
// **Léa-Chat MVP Schritt 1 (2026-05-10)** — Einzelne Chat-Bubble im
// WhatsApp/iMessage-Look. Strikt KEINE Elumi-Card-Tokens (kein
// `appSetupCardBackground`, kein `AppTheme.Spacing`-System), damit
// der Chat-Body sich klar vom Lern-App-Look abhebt.
//
// User-Bubbles: rechts, lila (#5B6AF0), weiß-Text.
// Léa-Bubbles: links, weiß, Avatar links davor, mit dezentem Schatten.
//
// Streaming-Cursor: blinkender vertikaler Strich am Ende des Léa-
// Bubble-Texts während der Stream läuft. Endet wenn `isStreaming`
// auf der Bubble false wird (vom ChatService gesteuert via
// `streamingMessageID`).

import SwiftUI

struct ChatBubbleView: View {
    let message: ChatMessage
    let isStreaming: Bool

    var body: some View {
        switch message.sender {
        case .user:
            userBubble
        case .lea:
            leaBubble
        }
    }

    // MARK: - User-Bubble (rechts)

    private var userBubble: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Spacer(minLength: 60) // erzwingt max ~75 % screen-width

            // **Bug-Fix 2026-05-10** — vorher
            // `.background(UnevenRoundedRectangle.fill(Color))` —
            // gerendert als weißer Hintergrund (vermutlich SwiftUI-
            // iOS-17-Quirk: `.foregroundStyle(.white)` auf Text
            // propagiert via View-Tree und überschreibt das `.fill()`
            // der Background-Shape). Jetzt via
            // `.background(_ style: in: Shape)`-Overload (iOS-17-
            // idiomatic) — Style ist explizit ShapeStyle und wird
            // nicht vom Text-foregroundStyle inheritiert.
            Text(message.text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white)
                .multilineTextAlignment(.leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Color(hex: "#5B6AF0"),
                    in: UnevenRoundedRectangle(
                        cornerRadii: .init(
                            topLeading: 18,
                            bottomLeading: 18,
                            bottomTrailing: 4,
                            topTrailing: 18
                        ),
                        style: .continuous
                    )
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }

    // MARK: - Léa-Bubble (links, mit Avatar)

    private var leaBubble: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ChatAvatarView(size: 26)

            HStack(alignment: .bottom, spacing: 2) {
                Text(message.text.isEmpty && isStreaming ? " " : message.text)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(Color(red: 0.102, green: 0.102, blue: 0.102)) // #1a1a1a
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if isStreaming {
                    StreamingCursorView()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                UnevenRoundedRectangle(
                    cornerRadii: .init(
                        topLeading: 18,
                        bottomLeading: 4,
                        bottomTrailing: 18,
                        topTrailing: 18
                    ),
                    style: .continuous
                )
                .fill(Color.white)
            )
            .shadow(color: .black.opacity(0.06), radius: 3, x: 0, y: 1)

            Spacer(minLength: 60)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 3)
    }
}

/// **Streaming-Cursor** — 2px breiter lila Strich, blinkt 0.8 s loop.
/// Wird in der Léa-Bubble während des Streams am Ende des Texts
/// gerendert. Verschwindet wenn `isStreaming = false`.
private struct StreamingCursorView: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Color(hex: "#5B6AF0"))
            .frame(width: 2, height: 18)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    visible = false
                }
            }
    }
}
