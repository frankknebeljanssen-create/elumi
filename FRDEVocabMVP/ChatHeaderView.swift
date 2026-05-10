// ChatHeaderView.swift
// **Léa-Chat MVP Schritt 1 (2026-05-10)** — Header für `ChatView`.
// Lila Gradient (Elumi-Brand-Anker), Léa-Avatar, Name + Subtitle,
// Settings-Zahnrad rechts.
//
// Schritt 1: Settings-Tap zeigt nur ein leeres Sheet (Placeholder
// für spätere Persona-/Level-Settings — kommt in Schritt 2/3).

import SwiftUI

struct ChatHeaderView: View {
    let persona: ChatPersona
    let onBack: () -> Void
    var onSettings: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            // Back-Chevron — pure iOS-Style, weiß auf Gradient.
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zurück")

            // Avatar — kleiner Kreis mit Gradient + Initial.
            ChatAvatarView(size: 38)

            // Name + Subtitle
            VStack(alignment: .leading, spacing: 1) {
                Text(persona.name)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\(persona.city) \(persona.flagEmoji)")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }

            Spacer(minLength: 0)

            // Settings-Zahnrad — rechts, Display-only in Schritt 1.
            Button {
                onSettings?()
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Einstellungen")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.357, green: 0.416, blue: 0.941), // #5B6AF0
                    Color(red: 0.486, green: 0.361, blue: 0.988), // #7C5CFC
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea(edges: .top)
        )
    }
}

/// **Léa-Avatar** — kleiner Gradient-Kreis mit Initial. Wird sowohl
/// im Header als auch in den Léa-Bubbles wiederverwendet.
struct ChatAvatarView: View {
    var size: CGFloat = 38
    var initial: String = "L"

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.961, green: 0.302, blue: 0.502), // #F54D80
                            Color(red: 0.486, green: 0.361, blue: 0.988), // #7C5CFC
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(initial)
                .font(.system(size: size * 0.5, weight: .black, design: .rounded))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)
    }
}
