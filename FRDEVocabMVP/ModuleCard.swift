// ModuleCard.swift
// **2026-05-06** — Card-Komponente Typ B (76 pt) für den Home-
// Refactor (Hybrid γ v3). Sub-Hub-Cards im Training-Hub: Vokabeln
// im Allgemein-Slot (einzeln, full-width), und Nomen / Verben /
// Artikel / Verbformen im 2×2-Spezial-Grid. Jede Card zeigt Icon +
// Titel zentriert, ohne Subtitle (kompakter Look als MethodCard).
//
// **Designsprache**: Spiegelt das Gradient-Fill-Pattern der existier-
// enden `MoreExerciseCard` (76 pt fühlt sich nahtlos an). Corner-
// Radius 16 pt (kompakter als MethodCard's 22), Background-Opacity
// etwas sanfter (0.88 → 0.68 statt 0.95 → 0.75) — die Sub-Hub-Cards
// sind hierarchisch eine Stufe unter den Methoden-Cards auf Home.
//
// **Icon-Flexibilität**: ViewBuilder-Slot, identisch zu MethodCard.

import SwiftUI

/// Modul-Card Typ B — 76 pt hoch, 2×2-Grid (Spezial) oder full-width
/// (Allgemein). Icon (~36 pt) + Titel (15 pt bold rounded) zentriert.
/// Akzent-Gradient als Background, leichter Drop-Shadow.
struct ModuleCard<Icon: View>: View {
    let title: String
    let accent: Color
    @ViewBuilder let icon: () -> Icon
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                icon()
                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 76)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.88), accent.opacity(0.68)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .shadow(color: .black.opacity(0.20), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(AppCardPressStyle())
    }
}
