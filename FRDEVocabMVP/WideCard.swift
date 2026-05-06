// WideCard.swift
// **2026-05-06** — Card-Komponente Typ C (56-76 pt) für den Home-
// Refactor (Hybrid γ v3). Quer-Cards: Tools-Section auf Home
// (Scannen / Listen, je 76 pt) und Akzente am Ende des Training-
// Hubs (56 pt, kompakter weil eigenständige Spezial-Modus-Card).
//
// **Designsprache**: Spiegelt das HStack-Pattern der existierenden
// `ToolCard` (HomeToolsSection.swift). Icon links, Titel mitte,
// Akzent-Gradient als Background, identische Corner-Radius (18 pt)
// und Drop-Shadow-Tiefen.
//
// **Höhen-Variante**: Caller übergibt `height` — User-Spec sagt
// 76 pt für Tools, 56 pt für Akzente. Icon-Größe und vertikales
// Padding bleiben relativ konstant; die Card nimmt nur leicht Höhe
// weg bei 56 pt.

import SwiftUI

/// Quer-Card Typ C — Icon links + Titel mitte, full-width. Caller
/// gibt Höhe (typisch 56 oder 76 pt) und Icon (ViewBuilder).
struct WideCard<Icon: View>: View {
    let title: String
    let accent: Color
    let height: CGFloat
    /// Title-Schriftgröße. Default 17 pt (Home-Tools-Konvention);
    /// Caller kann bumpen — z. B. Hub-Akzente nutzt 18 pt nach dem
    /// Polish 2026-05-06 (User-Spec „alle Fonts in den Hub-Cards
    /// +1p").
    var titleSize: CGFloat = 17
    @ViewBuilder let icon: () -> Icon
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                icon()
                Text(title)
                    .font(.system(size: titleSize, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 1, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .frame(minHeight: height)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [accent.opacity(0.95), accent.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.03))
            )
            .shadow(color: .black.opacity(0.25), radius: 5, x: 0, y: 3)
        }
        .buttonStyle(AppCardPressStyle())
    }
}
