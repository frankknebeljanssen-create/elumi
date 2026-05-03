import SwiftUI

/// **Zentraler Pulse-Hint-Modifier** (Stufe 7 UX-Polish, 2026-05-02).
///
/// Reine **Opacity/Scale + Shadow**-Pulsation für „tap me"-Hints
/// (Setup-Modal-Time-Cards bevor Wahl, „Los geht's"-CTA nach Wahl,
/// „Maschine starten"-Slot-CTA, Pre-Screen-„Bereit?"-Headline).
/// Kein Frame-Recompute, kein Layout-Pulse — nur GPU-Effekte.
///
/// **Implementation:** `@State var phase` toggelt zwischen 0 und 1
/// per `.onAppear`/`.onChange(of: active)` mit `.repeatForever`-
/// Animation auf `.easeInOut`. `scaleEffect` und `shadow.radius`
/// interpolieren zwischen Ruhe- und Peak-Werten.
///
/// **Performance:** `.repeatForever(autoreverses: true)` läuft auf
/// GPU; SwiftUI cached die Render-Tree und animiert nur die
/// Transformations-Matrix. Keine 60fps-Hot-Path-Issue.
struct PulsingModifier: ViewModifier {
    /// Wenn `false`, sitzt der Modifier ruhig (scale 1, kein Glow).
    /// Wechsel auf `true` startet die Pulse-Schleife; zurück auf
    /// `false` stoppt sie (Spring-Snap-Back zu Default).
    let active: Bool

    /// Peak-Skalen-Faktor — bei 1.05 sind die Cards beim Peak 5 %
    /// größer. Stark genug zum Bemerken, dezent genug um nicht
    /// kindisch zu wirken.
    var peakScale: CGFloat = 1.05

    /// Peak-Glow-Radius (Shadow). Setzt die maximale Strahlung beim
    /// Peak; Ruhewert ist 0 (kein Schatten).
    /// **UX-Polish 2026-05-02 Iter 2 (User „schneller + stärker
    /// pulsieren, einheitlich überall")**: 22 → 32 pt.
    var peakGlow: CGFloat = 32

    /// Glow-Farbe. Default cream/textPrimary für Light-on-Dark UI.
    var glowColor: Color = AppTheme.Colors.cta

    /// Cycle-Dauer in Sekunden (1 Pulse-Zyklus = scale-up + scale-
    /// down).
    /// **UX-Polish 2026-05-02 Iter 2 (User „muss schneller blinken,
    /// einheitlich auf allen Pulse-Stellen")**: 0.85 → 0.6 s. Damit
    /// liegt die Pulse-Frequenz auf knapp 1.7 Hz — klar als „Blink",
    /// nicht mehr als „Atem".
    var cycleSeconds: Double = 0.6

    /// Peak-Glow-Opacity — Anteil der `glowColor`-Sättigung im
    /// Shadow beim Pulse-Peak.
    /// **UX-Polish 2026-05-02 Iter 2 (User „kräftig blinken")**:
    /// 0.95 → 1.0. Volle Sättigung am Peak.
    var peakGlowOpacity: Double = 1.0

    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .scaleEffect(active ? (1.0 + (peakScale - 1.0) * phase) : 1.0)
            .shadow(
                color: active ? glowColor.opacity(peakGlowOpacity * Double(phase)) : .clear,
                radius: active ? peakGlow * phase : 0,
                x: 0,
                y: 0
            )
            .onAppear {
                if active {
                    startPulsing()
                }
            }
            .onChange(of: active) { _, isActive in
                if isActive {
                    startPulsing()
                } else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        phase = 0
                    }
                }
            }
    }

    private func startPulsing() {
        // Snap to 0 ohne Animation, dann starten — vermeidet
        // visuellen Sprung wenn `active` mid-cycle re-aktiviert wird.
        phase = 0
        withAnimation(.easeInOut(duration: cycleSeconds).repeatForever(autoreverses: true)) {
            phase = 1
        }
    }
}

extension View {
    /// **Pulse-Hint** für „tap me"-Affordance. Siehe `PulsingModifier`-
    /// Doc für Defaults und Performance-Hinweise. Wenn `active = false`,
    /// ist der Modifier ein No-Op (scale 1, kein Glow).
    func pulsing(
        active: Bool,
        peakScale: CGFloat = 1.05,
        peakGlow: CGFloat = 32,
        glowColor: Color = AppTheme.Colors.cta,
        cycleSeconds: Double = 0.6,
        peakGlowOpacity: Double = 1.0
    ) -> some View {
        modifier(
            PulsingModifier(
                active: active,
                peakScale: peakScale,
                peakGlow: peakGlow,
                glowColor: glowColor,
                cycleSeconds: cycleSeconds,
                peakGlowOpacity: peakGlowOpacity
            )
        )
    }
}
