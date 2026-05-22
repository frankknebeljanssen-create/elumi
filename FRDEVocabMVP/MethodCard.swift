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
    /// Titel-Schriftgröße. Default 19 pt — Karteikarten-Caller setzt 22.
    var titleSize: CGFloat = 19
    @ViewBuilder let icon: () -> Icon
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // **Polish 2026-05-06 Iteration 4** — Baseline-Alignment-
            // Fix + größere Fonts (User-Feedback: „Karteikarten und
            // Quiz nicht auf gleicher Höhe + Fonts zu klein, wirkt
            // futzelig"). Vorher VStack mit `spacing: 4` und keiner
            // fixen Vertical-Position — bei unterschiedlichen Title-
            // Längen / Icon-Höhen rutschten Title und Subtitle
            // zwischen den zwei Hero-Cards weg. Jetzt:
            //   • Icon im oberen Drittel via Spacer
            //   • Text-Block am unteren Drittel via Spacer
            //   • Beide Spacer-Frames identisch → Cards gleicher
            //     Größe haben Title und Subtitle auf identischer
            //     vertikaler Baseline.
            //   • Title 17 → 19 pt (knapper, nicht filigran)
            //   • Subtitle 12 → 13 pt
            // **Compaction 2026-05-10** — Card-Höhe 135 → 115 pt
            // (~15 %), VStack-Spacing 6 → 4 pt, Bottom-Spacer 4 → 2 pt.
            // Karteikarten + Quiz wirken jetzt schlanker im
            // heroCardsRow. Title- und Subtitle-Fonts bleiben (Lesbar-
            // keit hat Vorrang). HIG-Tap-Target bleibt mit 115 pt
            // hoch über dem 44-pt-Minimum.
            // **Fixe-Regionen-Layout (2026-05-22)** — Spacer-basierte
            // Verteilung richtete Icons/Titel bei unterschiedlichen
            // Icon-Größen (60/52) und Titel-Größen (22/19) NICHT exakt
            // aus: das kleinere Quiz-Icon rutschte tiefer, Titel-Höhen
            // variierten. Lösung: feste Höhen für Title- und Subtitle-
            // Region → die flexible Icon-Region ist in beiden Cards
            // identisch groß → Icons exakt gleich hoch zentriert; Titel
            // sitzen unabhängig von der Font-Größe auf gleicher Höhe.
            VStack(spacing: 0) {
                // **Fixes Icon-Band (2026-05-22)** — vorher `icon()
                // .frame(maxHeight: .infinity)`: falls die Greedy-Expansion
                // nicht griff, wurde der Content zentriert → der Karteikarten-
                // Titel (60-pt-Icon) saß ~4 px tiefer als Quiz (52-pt-Icon).
                // Jetzt: EIN flexibler Spacer oben, darunter alles fix →
                // Spacer in beiden Cards identisch groß → Icon-Band + Titel
                // exakt auf gleicher Höhe.
                Spacer(minLength: 0)
                // Icon-Band — FIXE 60 pt (= größtes Icon, Karteikarten). Das
                // kleinere Quiz-Icon (52) wird darin zentriert → beide Icon-
                // Mitten exakt gleich. Icon-Größen selbst (60/52) unverändert.
                icon()
                    .frame(width: 60, height: 60)
                Spacer().frame(height: 4)
                // Title-Region — fixe Höhe → Titel auf identischer Höhe.
                Text(title)
                    .font(.system(size: titleSize, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(height: 24)
                Spacer().frame(height: 2)
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.88))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(height: 16)
                Spacer().frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 115)
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
