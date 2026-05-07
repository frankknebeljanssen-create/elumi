// WideCard.swift
// **2026-05-06** — Card-Komponente Typ C (56-86 pt) für den Home-
// Refactor (Hybrid γ v3). Vollbreite-Card mit Icon links + Text-
// Block rechts daneben. Verschiedene Höhen-Varianten:
//
//   • **Tools-Style** (Default): Icon + Title, 56-76 pt, kompakt.
//     Genutzt für die Tools-Reihe auf Home (Scannen / Listen) und
//     für die Akzente-Card am Ende des Training-Hubs.
//   • **Method-Style** (`subtitle:` + `showsChevron: true` setzen):
//     Icon + Title + Subtitle + Chevron, 86 pt, präsenter. Genutzt
//     für die zwei Sub-Hero-Methoden auf Home (Daily Drop, Training).
//
// **Merged 2026-05-07** — Vorher gab es zwei separate Komponenten
// (`WideCard` für Tools, `WideMethodCard` für die Method-Variante)
// mit identischem Gradient/Shadow-Pattern. Hier zusammengezogen via
// optionale Parameter; der Aufrufer wählt das Style-Profil.
//
// **Designsprache**: Akzent-Gradient als Background (0.95 → 0.75
// opacity, topLeading → bottomTrailing), leichter Drop-Shadow
// (0.25 / radius 5 / y 3), white-overlay 0.03 für minimalen
// Depth-Effekt.

import SwiftUI

/// Vollbreite-Card mit Icon links + Title (+ optional Subtitle +
/// Chevron). Caller wählt Höhe + Style-Parameter.
struct WideCard<Icon: View>: View {
    let title: String
    /// Optionale Subline unter dem Titel. Wenn gesetzt, rendert die
    /// Card eine zweizeilige VStack rechts vom Icon (Method-Style).
    /// `nil` = nur Title (Tools-Style, einzeilig).
    var subtitle: String? = nil
    let accent: Color
    let height: CGFloat
    /// Title-Schriftgröße. Default 17 pt (Tools-Konvention); Caller
    /// kann bumpen — z. B. Hub-Akzente nutzt 20 pt nach den Hub-
    /// Cards-Polish-Iterationen, Method-Cards nutzen 19 pt.
    var titleSize: CGFloat = 17
    /// Subtitle-Schriftgröße (nur wirksam wenn `subtitle != nil`).
    var subtitleSize: CGFloat = 13
    /// Optionaler Chevron-Right rechts in der Card als Tap-Affordance
    /// für „weiter zu …"-Routes. Default aus für Tools.
    var showsChevron: Bool = false
    /// Corner-Radius — Default 18 pt für Tools, 22 pt für Method-
    /// Style (etwas runder, prominenter).
    var cornerRadius: CGFloat = 18
    /// Internes horizontales Padding der HStack zum Card-Rand.
    var horizontalPadding: CGFloat = 14
    /// Internes vertikales Padding der HStack zum Card-Rand.
    var verticalPadding: CGFloat = 8
    /// Optionale fixe Icon-Frame-Größe. `nil` = Icon nutzt seine
    /// intrinsische Größe (Tools-Default). 52 pt für Method-Style.
    var iconFrameSize: CGFloat? = nil
    @ViewBuilder let icon: () -> Icon
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: subtitle == nil ? 12 : 14) {
                Group {
                    if let iconFrameSize {
                        icon()
                            .frame(width: iconFrameSize, height: iconFrameSize)
                    } else {
                        icon()
                    }
                }

                if let subtitle {
                    // Method-Style: Title + Subtitle untereinander.
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.system(size: titleSize, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(subtitle)
                            .font(.system(size: subtitleSize, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                } else {
                    // Tools-Style: nur Title, einzeilig.
                    Text(title)
                        .font(.system(size: titleSize, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 0)

                if showsChevron {
                    // Chevron-Affordance — sofort lesbar als „weiter zu"-
                    // Hinweis. Farbe weiß-translucent, damit er sich vom
                    // farbigen Card-Background sanft absetzt.
                    Image(systemName: "chevron.right")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity)
            .frame(minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.95), accent.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 3)
        }
        .buttonStyle(AppCardPressStyle())
    }
}
