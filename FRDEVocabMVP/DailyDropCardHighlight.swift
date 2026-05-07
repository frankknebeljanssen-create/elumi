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

/// **Habit-Tracking-Namespace für die Daily-Drop-Card** (2026-05-06).
/// Hält die Read- und Write-Helper für den persistierten
/// „heute-gemacht"-Zustand, plus die Computed-State-Repräsentation
/// für die Badge-UI.
enum DailyDropTracker {
    /// Markiert „Daily Drop heute komplett gemacht" — wird aus
    /// `ElumiTabView.onChange(of: slotPhase) → .revealed` gerufen.
    /// Idempotent: mehrfaches Aufrufen am gleichen Tag ist no-op
    /// (überschreibt nur den Timestamp innerhalb desselben
    /// Kalendertages).
    static func markCompletedNow() {
        let now = Date()
        UserDefaults.standard.set(
            now.timeIntervalSinceReferenceDate,
            forKey: appLastCompletedDailyDropDateKey
        )
    }

    /// `true` wenn der persistierte Timestamp **heute** liegt
    /// (Calendar-basierter Tag-Vergleich, lokale Zeitzone).
    static func hasCompletedToday() -> Bool {
        let raw = UserDefaults.standard.double(forKey: appLastCompletedDailyDropDateKey)
        guard raw > 0 else { return false }
        let date = Date(timeIntervalSinceReferenceDate: raw)
        return Calendar.current.isDateInToday(date)
    }

    /// Aktueller Badge-State für die HomeView Daily-Drop-Card.
    /// Mappt direkt auf Text + Background-Color + Foreground-Color.
    enum BadgeState {
        case neuHeute
        case erledigt

        var text: String {
            switch self {
            case .neuHeute:  return "Neu heute"
            case .erledigt:  return "✓ Heute gemacht"
            }
        }

        /// Background-Color für die Badge-Pill. Amber für „neu" (Aufmerksam-
        /// keit), Mint für „erledigt" (Achievement-Grün, dezent).
        var color: Color {
            switch self {
            case .neuHeute:  return AppTheme.Colors.moduleQuiz       // Amber
            case .erledigt:  return AppTheme.Colors.elumiMint        // Mint
            }
        }

        /// Foreground-Color für den Badge-Text. **Bug-Fix 2026-05-06**:
        /// vorher überall weiß, was bei Mint-Background den Kontrast
        /// killt (User-Feedback „weiße Schrift auf grünem Pill kaum
        /// lesbar"). Jetzt:
        ///   • `neuHeute` → weiß auf Amber (Kontrast OK)
        ///   • `erledigt` → dunkles Mint-Grün auf hellem Mint-BG
        ///     (`#04342C` — gleiche Farb-Familie, dunkel genug für
        ///     Kontrast-Ratio > 4.5:1).
        var foreground: Color {
            switch self {
            case .neuHeute:  return .white
            case .erledigt:  return Color(hex: "#04342C")
            }
        }
    }

    /// Liefert den aktuellen Badge-State basierend auf dem
    /// persistierten Date-Stempel.
    static func currentBadgeState() -> BadgeState {
        hasCompletedToday() ? .erledigt : .neuHeute
    }
}

extension View {
    /// Wraps das Card-View in einen Highlight-Layer (Border-Glow +
    /// Shimmer-Sweep + Badge). Einsatz auf der Daily-Drop-Card; alle
    /// anderen Cards bleiben unanimiert.
    func dailyDropCardHighlight(
        badgeText: String,
        badgeColor: Color,
        badgeForeground: Color = .white,
        cornerRadius: CGFloat = 22
    ) -> some View {
        modifier(DailyDropCardHighlightModifier(
            badgeText: badgeText,
            badgeColor: badgeColor,
            badgeForeground: badgeForeground,
            cornerRadius: cornerRadius,
            showsBadge: true,
            paused: false
        ))
    }

    /// Slim-Variante ohne Badge — z. B. für den Slot-CTA „Drop
    /// starten". Border-Glow + Shimmer laufen weiter, Badge entfällt.
    /// `paused: true` schaltet die Animationen aus (z. B. während
    /// die Slot-Reels rotieren — vermeidet Frame-Drops auf älteren
    /// Geräten und reduziert visuellen Lärm während der Spin-Phase).
    func dailyDropGlow(
        cornerRadius: CGFloat = 16,
        paused: Bool = false
    ) -> some View {
        modifier(DailyDropCardHighlightModifier(
            badgeText: "",
            badgeColor: .clear,
            badgeForeground: .clear,
            cornerRadius: cornerRadius,
            showsBadge: false,
            paused: paused
        ))
    }
}

struct DailyDropCardHighlightModifier: ViewModifier {
    let badgeText: String
    let badgeColor: Color
    let badgeForeground: Color
    let cornerRadius: CGFloat
    let showsBadge: Bool
    let paused: Bool

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
            .overlay { paused ? AnyView(EmptyView()) : AnyView(borderGlow) }
            .overlay { paused ? AnyView(EmptyView()) : AnyView(shimmerSweep) }
            .overlay(alignment: .topTrailing) {
                if showsBadge { badge } else { EmptyView() }
            }
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
        // **Polish 2026-05-07** — Font 10 → 11 pt + Padding 10/3 →
        // 12/4 pt (User-Feedback „Badge etwas größer"). Das Badge
        // bleibt kompakt genug um nicht aus der Card-Kante
        // herauszuwuchern, liest sich aber auf modernen Displays
        // jetzt deutlich klarer.
        Text(badgeText)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .tracking(0.4)
            .textCase(.uppercase)
            .foregroundStyle(badgeForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
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
