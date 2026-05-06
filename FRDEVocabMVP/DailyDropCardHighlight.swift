// DailyDropCardHighlight.swift
// **2026-05-06** — Visual-Highlight-Layer für die Daily-Drop-Card
// auf HomeView. Drei kombinierte Effekte:
//
//   1. **Rotierender Gradient-Border-Glow** (4s Cycle) — `Angular-
//      Gradient` mit Modul-Akzenten, dessen Start-Angle pro Frame
//      über `TimelineView` rotiert. 2pt Stroke um die Card-Kante.
//
//   2. **Diagonaler Shimmer-Sweep** (5s Cycle, 60% sweep / 40%
//      pause) — heller Streifen läuft schräg über die Card. Subtil
//      (max ~25% Opacity).
//
//   3. **Statisches Badge** oben rechts — Pill mit Text + Akzent-
//      Background. Caller liefert Text und Color, sodass der
//      Habit-State (NEU HEUTE / ✓ HEUTE GEMACHT) extern bestimmt
//      wird.
//
// **Animation-Pause**: `TimelineView(.animation)` pausiert systemweit
// im Background (iOS-15+). Kein expliziter `scenePhase`-Listener
// nötig.
//
// **Performance**: keine `.repeatForever()` — würde unter Re-Render
// abbrechen können (siehe Pattern-Doc in `ElumiTabView`s
// `pulseGlow`-Block, Z. 1373-1379). `TimelineView` mit `.animation`
// liefert kontinuierliche Frames ohne SwiftUI-State-Mutation.

import SwiftUI

extension View {
    /// Wraps das Card-View in einen Highlight-Layer (Border-Glow +
    /// Shimmer-Sweep + Badge). Einsatz auf der Daily-Drop-Card; alle
    /// anderen Cards bleiben unanimiert.
    func dailyDropCardHighlight(
        badgeText: String,
        badgeColor: Color,
        cornerRadius: CGFloat = 22
    ) -> some View {
        modifier(DailyDropCardHighlightModifier(
            badgeText: badgeText,
            badgeColor: badgeColor,
            cornerRadius: cornerRadius
        ))
    }
}

struct DailyDropCardHighlightModifier: ViewModifier {
    let badgeText: String
    let badgeColor: Color
    let cornerRadius: CGFloat

    /// Akzent-Farben für den rotierenden Gradient-Border. Start-Farbe
    /// wiederholt sich am Ende, damit der Cycle nahtlos schließt.
    private static let glowColors: [Color] = [
        Color(hex: "#993556"),
        Color(hex: "#F4C775"),
        Color(hex: "#5DCAA5"),
        Color(hex: "#7F77DD"),
        Color(hex: "#993556")
    ]

    /// Border-Glow-Cycle in Sekunden.
    private static let glowCycle: Double = 4.0

    /// Shimmer-Cycle in Sekunden (60% sweep, 40% pause).
    private static let shimmerCycle: Double = 5.0
    private static let shimmerSweepFraction: Double = 0.6

    func body(content: Content) -> some View {
        content
            .overlay { borderGlow }
            .overlay { shimmerSweep }
            .overlay(alignment: .topTrailing) { badge }
    }

    // MARK: - Border-Glow

    /// Rotierender `AngularGradient` als Stroke um die Card. Start-
    /// Angle wandert linear über `TimelineView`, sodass die Farbpalette
    /// einmal pro `glowCycle`-Sekunden rotiert.
    private var borderGlow: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: Self.glowCycle)) / Self.glowCycle
            let angle = phase * 360.0

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(
                    AngularGradient(
                        colors: Self.glowColors,
                        center: .center,
                        startAngle: .degrees(angle),
                        endAngle: .degrees(angle + 360)
                    ),
                    lineWidth: 2
                )
        }
    }

    // MARK: - Shimmer-Sweep

    /// Diagonaler Shimmer: heller Streifen wandert von links-unten
    /// nach rechts-oben. Innerhalb eines Cycles 60% Sweep + 40%
    /// Pause, sodass der Effekt nicht zu hektisch wirkt.
    private var shimmerSweep: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            let phase = (t.truncatingRemainder(dividingBy: Self.shimmerCycle)) / Self.shimmerCycle

            // Während der ersten 60% läuft der Sweep, danach Pause.
            let isSweeping = phase < Self.shimmerSweepFraction
            let sweepProgress = isSweeping ? phase / Self.shimmerSweepFraction : 1.0

            GeometryReader { geo in
                let width = geo.size.width
                // X-Offset: -100% Card-Breite → +100% Card-Breite.
                // Diagonale wird über Rotation des Streifens erzielt.
                let xOffset = -width + sweepProgress * 2.5 * width

                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [
                                .clear,
                                Color.white.opacity(0.25),
                                .clear
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: width * 0.45, height: geo.size.height * 1.8)
                    .rotationEffect(.degrees(20))
                    .offset(x: xOffset, y: 0)
                    .opacity(isSweeping ? 1.0 : 0.0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .allowsHitTesting(false)
    }

    // MARK: - Badge

    /// Pill mit Text + Akzent-Background. Sitzt oben rechts, leicht
    /// über die Card-Kante hinausragend (-12 x / -8 y) — visueller
    /// Anker, hebt sich vom Card-Layout ab.
    private var badge: some View {
        Text(badgeText)
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(
                Capsule(style: .continuous)
                    .fill(badgeColor)
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
            // Leichter Offset über die Card-Kante hinaus — Anker-
            // Effekt. Negative Y hebt das Badge an, negative X
            // zieht es zur rechten Card-Kante.
            .offset(x: -12, y: -8)
    }
}
