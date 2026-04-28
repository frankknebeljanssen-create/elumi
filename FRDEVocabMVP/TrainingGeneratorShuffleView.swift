import SwiftUI

/// **Training-Generator Shuffle-Animation**: drei vertikale Reels, die
/// kurz schnell laufen und gestaffelt stoppen. Visuell eine abgespeckte
/// Slot-Machine — bewusst clean & wertig, keine Casino-Optik.
///
/// Die Werte in den Reels sind kosmetisch; der tatsächliche Generator-
/// Output wird parallel im `TrainingGeneratorView` aus der
/// `TrainingGenerator`-Service-Logik gebaut. Das entkoppelt Animation
/// und Business-Logik, wie in der Spec gefordert.
struct TrainingGeneratorShuffleView: View {
    let accent: Color

    /// Start-Zeit der Animation. Wird beim ersten Render fixiert; jede
    /// Reel rechnet ihren Offset aus `Date() - startDate`.
    @State private var startDate: Date = Date()

    /// Konstanten pro Reel: Gesamt-Lauf-Dauer. Staggered stops → Reel 1
    /// hält zuerst an, dann Reel 2, dann Reel 3. Jedes leicht über 1 s,
    /// Summe bleibt unter 1,5 s-Budget des Container-Stage.
    private let reelDurations: [Double] = [0.9, 1.15, 1.35]

    /// Drei unterschiedliche Wort-Pools für die Reels, damit visuell
    /// nicht dreimal dieselbe Reihenfolge läuft.
    private let reelWords: [[String]] = [
        ["Warmup", "Karten", "Mix", "Speed", "Fokus", "Warmup", "Karten", "Mix"],
        ["Quiz", "Match", "Artikel", "Wiederholen", "Speed", "Quiz", "Match", "Artikel"],
        ["Akzente", "Schreiben", "Challenge", "Karten", "Speed", "Akzente", "Schreiben", "Challenge"]
    ]

    private let rowHeight: CGFloat = 40
    private let visibleRows: Int = 3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let elapsed = context.date.timeIntervalSince(startDate)
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { reelIndex in
                    reel(
                        words: reelWords[reelIndex],
                        elapsed: elapsed,
                        totalDuration: reelDurations[reelIndex],
                        reelSeed: reelIndex
                    )
                }
            }
        }
        .frame(width: 300, height: CGFloat(visibleRows) * rowHeight)
        .onAppear { startDate = Date() }
        .accessibilityHidden(true)
    }

    // MARK: - Reel

    /// Eine einzelne Reel-Kolonne. Berechnet den vertikalen Offset aus
    /// der vergangenen Zeit — zuerst läuft sie schnell, dann ease-out
    /// zum Stop bei einer zufällig-aber-deterministisch gewählten
    /// End-Position.
    private func reel(
        words: [String],
        elapsed: Double,
        totalDuration: Double,
        reelSeed: Int
    ) -> some View {
        // Progress 0…1 über die Laufdauer. Danach statisch am Ende.
        let t = min(max(elapsed / totalDuration, 0), 1)
        // Ease-out-Kurve für den Abbremseffekt. Expo-Ease-Out klingt
        // natürlicher als linear.
        let eased = t == 1 ? 1 : 1 - pow(2, -8 * t)

        // Gesamte Scroll-Distanz in Zeilen. Pro Reel leicht variieren,
        // damit sie optisch nicht synchron stoppen.
        let totalRows = Double(words.count * 5) + Double(reelSeed) * 1.5
        let scrolledRows = totalRows * eased

        // Basis-Offset in Pixeln — nach oben scrollend. Modulo wrap
        // damit es wie eine endlose Liste wirkt.
        let rawOffset = -scrolledRows * Double(rowHeight)
        let wrappedOffset = rawOffset.truncatingRemainder(dividingBy: Double(words.count) * Double(rowHeight))

        return ZStack {
            // Hintergrund-Karte
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: "#1A2A40"))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color(hex: "#243B55"), lineWidth: 1)
                )

            // Scroll-Liste (3× die Wörter wiederholt für sauberes Loop-
            // Feeling, damit wrappedOffset immer Wörter zeigt).
            VStack(spacing: 0) {
                ForEach(0..<(words.count * 3), id: \.self) { index in
                    let word = words[index % words.count]
                    Text(word)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(
                            // Mitteler Eintrag (visibleRows / 2 = 1) leicht
                            // hervorheben durch vollen Textfarb-Contrast;
                            // alle anderen dezenter.
                            Color.white.opacity(0.9)
                        )
                        .frame(height: rowHeight)
                        .frame(maxWidth: .infinity)
                }
            }
            .offset(y: CGFloat(wrappedOffset))
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: .white, location: 0.25),
                        .init(color: .white, location: 0.75),
                        .init(color: .clear, location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            // Akzent-Rahmen um die „Window"-Zeile (die mittlere),
            // erscheint erst am Ende der Animation — Reveal-Moment.
            if t >= 1 {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(accent, lineWidth: 1.2)
                    .frame(height: rowHeight - 4)
                    .padding(.horizontal, 6)
                    .transition(.opacity)
            }
        }
        .frame(width: 92)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
