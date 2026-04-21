import SwiftUI

/// **Pop-Card-Background** — gemeinsamer 3-Lagen-Tiefen-Look für die
/// farbigen Hero- und Tool-Karten auf Home.
///
/// Aufbau (von hinten nach vorne):
///   1. **Basis-Tint**: Akzentfarbe mit zusätzlichem Schwarz-Overlay,
///      damit die Karte insgesamt **satter / dunkler** wirkt — analog
///      zu den User-Referenzbildern, wo die Farben klar tiefer als
///      das Default-Theme-Token sind.
///   2. **Bottom-Schatten-Overlay**: vertikaler Black-Gradient
///      (transparent oben → ~40 % schwarz unten). Erzeugt die
///      „lit from above"-Optik: oben kräftig, unten organisch
///      ins Dunkle abkippend, wie bei einem geprägten Plastik-Pad.
///   3. **Top-Highlight**: dünner heller Streifen ganz oben innen,
///      simuliert reflektiertes Licht auf der Oberkante.
///
/// `accent` = Modul-Hauptfarbe (z. B. `moduleFlashcards`).
/// `cornerRadius` für saubere Clipping-Ecken.
struct PopCardBackground: View {
    let accent: Color
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            // (1) Basis-Tint — Akzent + kräftiger Schwarz-Anteil
            // (~28 %), damit die Card **deutlich satter/dunkler**
            // wirkt als der Theme-Akzent. User-Feedback: „dunkler,
            // vor allem diese 4".
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(accent)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.28))
                )

            // (2) Bottom-Schatten-Overlay — der Tiefen-Effekt
            // läuft jetzt **stärker IN** die Card hinein:
            // 0 % oben → 22 % Mitte → 60 % unten. Liest sich wie
            // ein Inset-Shadow am unteren Innenrand, kein äußerer
            // Glow mehr.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.black.opacity(0),
                            Color.black.opacity(0.22),
                            Color.black.opacity(0.60)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // (3) Top-Highlight — dünner heller Streifen am
            // oberen Innenrand. Bleibt erhalten, schafft den
            // „Plastik-Knopf"-Eindruck.
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.18),
                            Color.white.opacity(0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .blendMode(.plusLighter)
                .frame(maxHeight: .infinity)
                .mask(
                    VStack(spacing: 0) {
                        Rectangle()
                        Color.clear
                            .frame(maxHeight: .infinity)
                    }
                )
        }
    }
}

/// Dazugehörige **Bevel-Border** — leichter Rand-Stroke mit
/// vertikalem Hell-/Dunkel-Verlauf. Wird über den `PopCardBackground`
/// gelegt; trennt die Card visuell vom Hintergrund und verstärkt den
/// Plastik-/Pad-Eindruck.
struct PopCardBevel: View {
    let cornerRadius: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.32),
                        Color.white.opacity(0.05),
                        Color.black.opacity(0.30)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.4
            )
    }
}
