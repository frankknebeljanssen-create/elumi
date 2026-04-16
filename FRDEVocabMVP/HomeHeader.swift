import SwiftUI

/// Einstiegs-Header des Home-Screens.
///
/// Layout (Spec):
///   • links: Begrüßung („Salut Frank") — kleiner, sekundär
///           Hauptfrage („Was möchtest du heute lernen?") — größer, dominant
///   • rechts: Maskottchen mit echtem Augen-Zwinkern (SplashCharacterBlinkOverlay)
///
/// Keine zusätzlichen Subtexte — bewusst ruhig. Die folgenden Bereiche
/// (Progress Board, Daily Fokus, Weiterlernen) liefern den Kontext.
struct HomeHeader: View {
    let greeting: String
    let mainQuestion: String
    var mascotImageName: String = "SplashCharacter"
    private static let mascotSize: CGFloat = 88

    @State private var blinkStartDate: Date = .now

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(greeting)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                Text(mainQuestion)
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.leading)
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
            .offset(y: 4)
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
