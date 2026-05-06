// MethodCard.swift
// **2026-05-06** — Card-Komponente Typ A (110 pt) für den Home-
// Refactor. Methoden-Cards im 2×2-Grid: Karteikarten / Quiz /
// Mix-Training / Training. Jede Card zeigt Icon + Titel + Subtitle.
//
// **Designsprache**: Übernimmt das Gradient-Fill + Drop-Shadow-Pattern
// der existierenden `HeroModuleCard` (2026-04-30 Polish-Pass), damit
// die neuen Methoden-Cards visuell dieselbe Hierarchie sprechen wie
// die alten Hero-Cards. Nur leichte Anpassungen:
//   • Untertitel-Zeile ergänzt (HeroModuleCard hatte nur Titel).
//   • Höhe via `aspectRatio(1.0)` statt `1.15` — die User-Spec gibt
//     110 pt fest; mit 2-Spalten-Grid und 16 pt Outer-Padding +
//     12 pt Spacing hat jede Card Breite ~166 pt (auf iPhone 17),
//     also Aspect ~1.5 (66 % der Breite). Die `aspectRatio(1.0)`
//     würde die Cards zu hoch machen; stattdessen nutzen wir hier
//     `.frame(height: 110)` als feste Höhe pro Spec.
//
// **Icon-Flexibilität**: ViewBuilder-Slot, sodass Caller entweder
// ein `HomeModuleIcon`-Asset (`HomeModuleIconView(...)`) oder ein
// SF-Symbol (`Image(systemName: ...)`) durchreichen kann. Nötig,
// weil Mix-Training und Training keine eigenen Asset-Icons haben
// (für die Live-Iteration nutzen wir SF-Symbole; Asset-Migration
// kann später nachgezogen werden).

import SwiftUI

/// Methoden-Card im Hybrid-γ-v3-Layout — 110 pt hoch, 2×2-Grid auf
/// Home. Icon (52 pt) + Titel (17 pt black rounded) + Subtitle
/// (12 pt semibold). Akzent-Gradient als Background, Drop-Shadow
/// für Hierarchie-Hint. Tap triggert das übergebene `onTap`-Closure.
///
/// **Layout**:
/// ```
/// ┌──────────────────┐
/// │       [Icon]     │
/// │       Titel      │
/// │     Subtitle     │
/// └──────────────────┘
/// ```
/// Vertikal zentriert, alle Texte zentriert.
struct MethodCard<Icon: View>: View {
    let title: String
    let subtitle: String
    let accent: Color
    @ViewBuilder let icon: () -> Icon
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                icon()
                Text(title)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 110)
            // **Background-Pattern** — wie HeroModuleCard: Linear-
            // Gradient 0.95 → 0.75 vom topLeading nach bottomTrailing,
            // 22 pt corner radius, leichter Aufhellungs-Overlay
            // (3 % weiß), Drop-Shadow (5 pt blur, y=3) für Tiefe.
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.95), accent.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 3)
        }
        .buttonStyle(AppCardPressStyle())
    }
}
