// ChatTypingIndicatorView.swift
// **Léa-Chat MVP Schritt 1 (2026-05-10)** — „Léa schreibt …"-Indicator
// zwischen User-Bubble und ersten Léa-Token. 3 bouncende Punkte im
// Léa-Bubble-Style (links, mit Avatar). Verschwindet sobald der erste
// Token vom Stream eintrudelt.

import SwiftUI

struct ChatTypingIndicatorView: View {
    var body: some View {
        HStack(alignment: .bottom, spacing: 6) {
            ChatAvatarView(size: 26)

            HStack(spacing: 4) {
                TypingDot(delay: 0)
                TypingDot(delay: 0.15)
                TypingDot(delay: 0.30)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
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

/// Einzelner bouncender Punkt — `delay` in Sekunden definiert das
/// Phase-Offset zur Animation.
private struct TypingDot: View {
    let delay: Double
    @State private var lifted = false

    var body: some View {
        Circle()
            .fill(Color(red: 0.55, green: 0.55, blue: 0.58)) // mid-grey
            .frame(width: 7, height: 7)
            .offset(y: lifted ? -5 : 0)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.6)
                        .repeatForever(autoreverses: true)
                        .delay(delay)
                ) {
                    lifted = true
                }
            }
    }
}
