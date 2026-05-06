// WideMethodCard.swift
// **2026-05-06** — Hybrid-Card-Komponente für den Home-Layout-
// Refactor (Hybrid γ v3 Iteration 3). Vollbreite-Card mit:
//   • Icon links (~52 pt)
//   • Text-Block mittig (Title 17 pt black + Subtitle 12 pt semibold)
//   • Chevron rechts (Tap-Affordance)
//
// Ergänzt `MethodCard` (110/135 pt 2×2) und `WideCard` (Tools-only:
// Icon links + Title mitte, kein Subtitle, kein Chevron). Genutzt
// auf Home für die zwei Sub-Hero-Methoden „Mix-Training" und
// „Training" — visuell kleiner als die Hero-2×2 (Karteikarten/Quiz),
// aber prominenter als die Tools-Reihe (Scannen/Listen).
//
// **Designsprache**: identisches Gradient-Fill + Drop-Shadow-Pattern
// wie MethodCard, damit alle Methoden-Cards (Hero + Wide) visuell
// zusammenfinden. Card-Höhe 86 pt (mid zwischen den 135 pt Hero und
// den 76 pt Tools).

import SwiftUI

/// Vollbreite-Methoden-Card mit Icon-links, Text-Block mittig (Title
/// + Subtitle) und Chevron rechts. Tap triggert das übergebene
/// `onTap`-Closure.
///
/// **Layout**:
/// ```
/// ┌────────────────────────────────────┐
/// │ [Icon]   Titel              ›      │
/// │          Subtitle                  │
/// └────────────────────────────────────┘
/// ```
struct WideMethodCard<Icon: View>: View {
    let title: String
    let subtitle: String
    let accent: Color
    @ViewBuilder let icon: () -> Icon
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                icon()
                    .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)

                // Chevron-Affordance — sofort lesbar als „weiter zu"-
                // Hinweis. Farbe weiß-translucent, damit er sich vom
                // farbigen Card-Background sanft absetzt, ohne den
                // Akzent zu überlagern.
                Image(systemName: "chevron.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                    .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 86)
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
