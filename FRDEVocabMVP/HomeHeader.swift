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
    /// 72 pt — ~14 % kleiner als der vorige Wert (84). Spart sichtbar
    /// Höhe im Header, Mascot bleibt klar erkennbar.
    private static let mascotSize: CGFloat = 72

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
            // Periodisches Re-Triggern des Blink-Envelopes — der Overlay
            // blinzelt zweimal pro Session-Range (bei 1.35 s und 3.15 s
            // nach `startDate`). Alle 3.8–4.4 s (Random-Jitter) starten wir
            // neu, damit es natürlich und nicht mechanisch wirkt.
            while !Task.isCancelled {
                let interval = UInt64.random(in: 3_800...4_400) * 1_000_000
                try? await Task.sleep(nanoseconds: interval)
                await MainActor.run {
                    blinkStartDate = .now
                }
            }
        }
    }
}
