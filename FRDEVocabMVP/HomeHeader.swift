import SwiftUI

/// Einstiegs-Header des Home-Screens.
///
/// Layout (Spec):
///   • links: kleine Pink-Begrüßung („Salut Frank")
///            Hauptfrage („Was möchtest du heute lernen?") — groß, dominant
///   • rechts: Maskottchen mit echtem Augen-Zwinkern (SplashCharacterBlinkOverlay)
///
/// Keine zusätzlichen Subtexte — bewusst ruhig. Die folgenden Bereiche
/// (Progress Board, Daily Fokus, Weiterlernen) liefern den Kontext.
struct HomeHeader: View {
    let greeting: String
    var mascotImageName: String = "SplashCharacter"
    /// 58 pt — zwei Schritte: ~10 % kleiner als der vorherige Wert (65),
    /// um nochmal ein wenig Luft aus dem Header zu nehmen und der
    /// Salut-Zeile den Vorrang zu geben.
    private static let mascotSize: CGFloat = 58

    @State private var blinkStartDate: Date = .now

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                // Greeting („Salut Franki") auf **27 pt** (+2 nach User-
                // Wunsch; vorher 25). Dominiert den Header deutlicher,
                // nachdem der Mascot auf 58 pt geschrumpft ist.
                // `offset(y: -10)` rückt **nur** die Salut-Baseline
                // 10 pt höher. HStack-Höhe bleibt vom Mascot definiert,
                // alle nachfolgenden Cards sitzen unverändert an ihrer
                // bisherigen Y-Position.
                Text(greeting)
                    .font(.system(size: 27, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.elumiPink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
                    .offset(y: -10)
            }

            Spacer(minLength: 0)

            ZStack {
                Image(mascotImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.mascotSize, height: Self.mascotSize)
                SplashCharacterBlinkOverlay(
                    size: Self.mascotSize,
                    startDate: blinkStartDate
                )
                .frame(width: Self.mascotSize, height: Self.mascotSize)
            }
            // 20 pt optisch nach links (= Abstand zur rechten Screen-Kante)
            // plus `y: -10` — User-Wunsch: „alles außer Salut 10 pt nach
            // oben". Die Salut-Zeile bleibt an ihrer Baseline, der Mascot
            // rutscht als einziges Header-Element 10 pt höher und die
            // darunterliegenden Cards folgen (via reduziertem Top-Padding
            // auf `focusOrContinueCard` in `HomeView`).
            .offset(x: -20, y: -10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            // Periodisches Re-Triggern des Blink-Envelopes — der Overlay
            // blinzelt zweimal pro Session-Range (bei 1.35 s und 3.15 s
            // nach `startDate`). Intervall zwischen den Envelopes bewusst
            // **um 2 s erhöht** (3.8–4.4 s → 5.8–6.4 s), damit der Mascot
            // seltener blinzelt und Pausen zwischen den Blinks ruhiger
            // wirken.
            while !Task.isCancelled {
                let interval = UInt64.random(in: 5_800...6_400) * 1_000_000
                try? await Task.sleep(nanoseconds: interval)
                await MainActor.run {
                    blinkStartDate = .now
                }
            }
        }
    }
}
