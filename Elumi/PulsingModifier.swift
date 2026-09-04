import SwiftUI

/// **Zentraler Pulse-Hint-Modifier** (Stufe 7 UX-Polish, 2026-05-02).
///
/// Reine **Opacity/Scale + Shadow**-Pulsation für „tap me"-Hints
/// (Setup-Modal-Time-Cards bevor Wahl, „Los geht's"-CTA nach Wahl,
/// „Maschine starten"-Slot-CTA, Pre-Screen-„Bereit?"-Headline,
/// Pre-Screen-„Training starten"-CTA). Kein Frame-Recompute, kein
/// Layout-Pulse — nur GPU-Effekte.
///
/// **Implementation (Iter 2, 2026-05-02 — User-Spec „Pulsation muss
/// sofort starten, kein 2-Sek-Lag")**: TimelineView-getrieben statt
/// `withAnimation(.repeatForever)`. Vorher entstand beim
/// `active=false → true`-Flip eine wahrnehmbare Verzögerung — der
/// `phase = 0`-Reset plus der erste Animation-Cycle (~0.6 s
/// `cycleSeconds`) plus SwiftUI-Animation-Frame-Sync addierten sich
/// zu ~1.5–2 s, bis der erste sichtbare Peak kam. Jetzt kommt der
/// Wave-Wert aus der System-Clock (`context.date`) — beim
/// Aktiv-Flip steht der nächste Frame schon mit dem aktuellen
/// Wave-Wert da, kein Warmup. Pattern-Mirror zur
/// `TrainingResultCard.TimelineView`-Pulse-Mechanik (siehe
/// `ElumiTabView.trainingResultCard` Z. 1199-1224).
///
/// **Performance:** TimelineView mit `minimumInterval: 1/30 s`
/// → max 30 Frames/Sek. SwiftUI rendert nur die `.scaleEffect` /
/// `.shadow`-Modifier-Tree neu, der Inhalt (`content`) wird gecached.
/// Kein Frame-Recompute auf dem Inhalt selbst.
///
/// **Active=false-Pfad**: TimelineView wird komplett umgangen,
/// `content` direkt zurückgegeben — null Overhead bei inaktivem
/// State.
struct PulsingModifier: ViewModifier {
    /// Wenn `false`, sitzt der Modifier ruhig (scale 1, kein Glow,
    /// kein TimelineView-Tick).
    let active: Bool

    /// Peak-Skalen-Faktor — bei 1.05 sind die Cards beim Peak 5 %
    /// größer. Stark genug zum Bemerken, dezent genug um nicht
    /// kindisch zu wirken.
    var peakScale: CGFloat = 1.05

    /// Peak-Glow-Radius (Shadow). Setzt die maximale Strahlung beim
    /// Peak; Ruhewert ist 0 (kein Schatten).
    var peakGlow: CGFloat = 32

    /// Glow-Farbe. Default cream/textPrimary für Light-on-Dark UI.
    var glowColor: Color = AppTheme.Colors.cta

    /// Cycle-Dauer in Sekunden — Zeit zwischen zwei Peaks.
    /// Frequenz = `1 / cycleSeconds`. 0.6 s → ≈ 1.7 Hz, klar als
    /// „Blink", nicht „Atem".
    var cycleSeconds: Double = 0.6

    /// Peak-Glow-Opacity — Anteil der `glowColor`-Sättigung im
    /// Shadow beim Pulse-Peak. 1.0 = volle Sättigung.
    var peakGlowOpacity: Double = 1.0

    @ViewBuilder
    func body(content: Content) -> some View {
        if active {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let wave = currentWave(for: context.date)
                content
                    .scaleEffect(CGFloat(1.0 + Double(peakScale - 1.0) * wave))
                    .shadow(
                        color: glowColor.opacity(peakGlowOpacity * wave),
                        radius: peakGlow * CGFloat(wave),
                        x: 0,
                        y: 0
                    )
            }
        } else {
            content
        }
    }

    /// System-Clock → Pulse-Amplitude in `[0, 1]`. Zwei Halb-Cycles
    /// pro `cycleSeconds * 2` für Sine-symmetrisches Pulsen
    /// (analog zur autoreverse-Semantik aus dem alten withAnimation-
    /// Pfad).
    private func currentWave(for date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
        let fullCycle = cycleSeconds * 2
        let phase = t.truncatingRemainder(dividingBy: fullCycle) / fullCycle
        return (sin(phase * 2 * .pi) + 1) / 2
    }
}

extension View {
    /// **Pulse-Hint** für „tap me"-Affordance. Siehe `PulsingModifier`-
    /// Doc für Defaults und Performance-Hinweise. Wenn `active = false`,
    /// ist der Modifier ein No-Op (TimelineView wird komplett umgangen).
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
