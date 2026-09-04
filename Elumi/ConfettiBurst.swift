import SwiftUI

/// **Konfetti-Burst-Overlay** — wiederverwendbarer Component für
/// Feier-Momente (End-Summary, Jackpot, Level-Up, …).
///
/// Canvas + TimelineView-gestützte Particle-Animation. Niedrig-frequent
/// (30 Hz Refresh), keine Hot-Path-Performance-Issue.
///
/// **Block 5 (2026-05-03, Branch `feature/training-session-flow`)**:
/// Aus `TrainingChainCompleteSummaryView` extrahiert und parametrisiert
/// (`density` + `lifetime`), damit der Jackpot-Pfad (dichteres + längeres
/// Konfetti) und die Chain-End-Summary (sparsameres Konfetti) denselben
/// Code teilen.
///
/// Defaults entsprechen dem End-Summary-Verhalten von Stufe 5
/// (60 Partikel, 2.5 s) — bestehende Call-Sites bleiben unverändert.
///
/// **Particle-Spawn-Charakteristik**:
///   • Spawn-Y bei `-80` (klar off-screen oben).
///   • Stagger-Delay 0…0.4 s pro Partikel (Burst-Optik „rieselt von
///     oben").
///   • Drift-Bewegung sinusförmig um Start-X (Amplitude 15–45 pt).
///   • Rotation gleichmäßig (1–4 rad/s).
///   • Fade-Out in der letzten Sekunde des Lifetimes.
struct ConfettiBurst: View {
    let startDate: Date
    let density: Int
    let lifetime: Double

    /// Default-Init mit End-Summary-Defaults (60 Partikel, 2.5 s).
    /// Particle-Set wird beim Struct-Init einmalig gewürfelt.
    init(startDate: Date, density: Int = 60, lifetime: Double = 2.5) {
        self.startDate = startDate
        self.density = density
        self.lifetime = lifetime
        self.particles = ConfettiBurst.makeParticles(count: density)
    }

    private static let palette: [Color] = [
        Color(hex: "#FF6B6B"),  // rot
        Color(hex: "#FFD166"),  // gelb
        Color(hex: "#4ECDC4"),  // teal
        Color(hex: "#A06CD5"),  // lila
        Color(hex: "#06D6A0"),  // grün
        Color(hex: "#F8961E")   // orange
    ]

    /// Pro-Particle-Konfiguration, einmalig zur Init-Zeit gewürfelt.
    private struct Particle: Identifiable {
        let id: Int
        let xRel: Double         // Start-X als Anteil der Breite (0…1)
        let driftPhase: Double   // Phase-Offset für Sinus-Drift
        let driftAmplitude: Double
        let velocity: Double     // Fall-Geschwindigkeit-Multiplikator
        let color: Color
        let size: CGFloat
        let rotationSpeed: Double
        let spawnDelay: Double
    }

    private let particles: [Particle]

    private static func makeParticles(count: Int) -> [Particle] {
        (0..<count).map { i in
            Particle(
                id: i,
                xRel: Double.random(in: 0...1),
                driftPhase: Double.random(in: 0...(2 * .pi)),
                driftAmplitude: Double.random(in: 15...45),
                velocity: Double.random(in: 0.7...1.4),
                color: ConfettiBurst.palette.randomElement() ?? .white,
                size: CGFloat.random(in: 6...12),
                rotationSpeed: Double.random(in: 1...4),
                spawnDelay: Double.random(in: 0...0.4)
            )
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            Canvas { ctx, size in
                let elapsed = context.date.timeIntervalSince(startDate)
                guard elapsed >= 0, elapsed <= lifetime else { return }

                // Fade-Out in der letzten Sekunde des Lifetimes.
                let fadeStart = lifetime - 1.0
                let opacity: Double = elapsed < fadeStart
                    ? 1.0
                    : max(0, 1.0 - (elapsed - fadeStart))

                for particle in particles {
                    // Stagger-Spawn: Partikel mit `spawnDelay > elapsed`
                    // sind noch nicht erschienen.
                    let elapsedForParticle = elapsed - particle.spawnDelay
                    guard elapsedForParticle > 0 else { continue }

                    // Y-Position: linear über Bildschirmhöhe, mit
                    // Velocity-Multiplikator. Start bei -80 (klar
                    // off-screen oben), Ende bei `+size.height + 60`.
                    let progress = elapsedForParticle / lifetime * particle.velocity
                    let y = -80 + (size.height + 140) * progress

                    // X-Drift: sinusförmig um die Start-Position.
                    let baseX = particle.xRel * size.width
                    let drift = sin(elapsedForParticle * 1.5 + particle.driftPhase) * particle.driftAmplitude
                    let x = baseX + drift

                    // Rotation: gleichmäßige Drehung über die Lifetime.
                    let rotation = elapsedForParticle * particle.rotationSpeed * .pi

                    let rect = CGRect(
                        x: x - particle.size / 2,
                        y: y - particle.size / 2,
                        width: particle.size,
                        height: particle.size * 1.4
                    )

                    // Translation um Particle-Mittelpunkt für Rotation.
                    ctx.transform = CGAffineTransform.identity
                        .translatedBy(x: x, y: y)
                        .rotated(by: CGFloat(rotation))
                        .translatedBy(x: -x, y: -y)

                    ctx.fill(
                        Path(roundedRect: rect, cornerRadius: 1.5),
                        with: .color(particle.color.opacity(opacity))
                    )
                }
            }
        }
    }
}
