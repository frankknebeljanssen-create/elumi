// MethodCard.swift
// **2026-05-06** — Card-Komponente Typ A für den Home-Refactor.
// Methoden-Cards im 2×2-Grid: Karteikarten / Quiz / Mix-Training /
// Training. Jede Card zeigt Icon + Titel + Subtitle.
//
// **Designsprache**: Übernimmt das Gradient-Fill + Drop-Shadow-Pattern
// der existierenden `HeroModuleCard` (2026-04-30 Polish-Pass), damit
// die neuen Methoden-Cards visuell dieselbe Hierarchie sprechen wie
// die alten Hero-Cards.
//
// **Polish 2026-05-06 (Hybrid-γ-v3 Iteration 2)**:
// - Default-Höhe 110 → 135 pt — Cards füllen den Raum unter den
//   Tools sichtbar besser, der Tools-Block hat weniger Leer-Raum
//   ringsum.
// - Optionaler `emphasized: Bool`-Param — Caller kann eine Card als
//   Haupt-Methode markieren (User-Spec: Karteikarten = App-Grundidee).
//   Emphasized-State: stärkerer Drop-Shadow + zusätzlicher weißer
//   Stroke (1.5 pt, 32 % opacity) für ein subtil aufgewertetes
//   Erscheinungsbild ohne die Layout-Konsistenz zu brechen.
//
// **Icon-Flexibilität**: ViewBuilder-Slot, sodass Caller entweder
// ein `HomeModuleIcon`-Asset oder ein SF-Symbol durchreichen kann.
// Nötig, weil Mix-Training und Training keine eigenen Asset-Icons
// haben.

import SwiftUI

/// Methoden-Card im Hybrid-γ-v3-Layout — 135 pt hoch (Default),
/// 2×2-Grid auf Home. Icon (52 pt typ.) + Titel (17 pt black rounded)
/// + Subtitle (12 pt semibold). Akzent-Gradient als Background.
///
/// **Layout**:
/// ```
/// ┌──────────────────┐
/// │       [Icon]     │
/// │       Titel      │
/// │     Subtitle     │
/// └──────────────────┘
/// ```
struct MethodCard<Icon: View>: View {
    let title: String
    let subtitle: String
    let accent: Color
    /// Wenn `true`, bekommt die Card einen aufgewerteten Stroke +
    /// stärkeren Shadow. Genutzt für die „Haupt-Methode" auf Home
    /// (Karteikarten — App-Grundidee).
    var emphasized: Bool = false
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
            .frame(height: 135)
            // Background-Pattern — Linear-Gradient 0.95 → 0.75 vom
            // topLeading nach bottomTrailing, 22 pt corner radius.
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
            // **Emphasized-Stroke** — nur wenn `emphasized: true`.
            // Dezenter weißer Stroke (32 % Opacity) macht die Card
            // erkennbar als „Haupt-Methode", ohne das 4-Card-Grid
            // visuell zu brechen.
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        emphasized ? Color.white.opacity(0.32) : Color.clear,
                        lineWidth: emphasized ? 1.5 : 0
                    )
            )
            // Stärkerer Drop-Shadow für Emphasized — dezent, hebt
            // die Card minimal aus dem Grid.
            .shadow(
                color: .black.opacity(emphasized ? 0.32 : 0.25),
                radius: emphasized ? 8 : 5,
                x: 0,
                y: emphasized ? 4 : 3
            )
        }
        .buttonStyle(AppCardPressStyle())
    }
}
