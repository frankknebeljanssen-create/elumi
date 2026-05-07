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
                    // **Polish 2026-05-06 Iteration 7**: weight
                    // .bold → .black (User-Spec „alle Fonts im Hub
                    // so fetter wie Akzente"). Akzente nutzt
                    // WideCard mit .black; ModuleCard war bisher
                    // .bold, wirkte daneben dünner. Mit .black
                    // sprechen alle Hub-Cards (ModuleCard 2×2
                    // Spezial + WideCard Akzente) dieselbe
                    // Visual-Weight.
                    // **Polish 2026-05-07** — Title-Font 18 → 20 pt
                    // (User-Spec „Fonts +1-2pt"). ModuleCards im
                    // Training-Hub lesen sich jetzt prominenter,
                    // proportional zur erhöhten Card-Höhe.
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            // **Polish 2026-05-07** — Card-Höhe 76 → 88 pt (+12 pt,
            // User-Spec Hub-Cards-Polish „etwas größer"). Wirkt
            // präsenter ohne das 2×2-Grid zu sprengen; Maskottchen
            // bleibt durch ScrollView-Verhalten erreichbar.
            .frame(height: 88)
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
