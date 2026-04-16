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
    let mainQuestion: String
    var mascotImageName: String = "SplashCharacter"
    /// 65 pt — ~10 % kleiner als der vorherige Wert (72). Der Mascot
    /// bleibt klar erkennbar, gibt dem Greeting-Block aber noch
    /// deutlicher den Vorrang; außerdem kürzt sich der Header vertikal
    /// nochmal etwas.
    private static let mascotSize: CGFloat = 65

    @State private var blinkStartDate: Date = .now

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(greeting)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.elumiPink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Text(mainQuestion)
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
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
            // 20 pt optisch nach links — der Mascot sitzt dadurch bewusst
            // ein Stück von der rechten Screen-Kante weg. Offset statt
            // Padding, damit weder der Header-Rahmen noch der Text-Block
            // links davon ihre Position ändern.
            .offset(x: -20)
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
