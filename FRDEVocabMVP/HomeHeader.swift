import SwiftUI

/// Einstiegs-Header des Home-Screens (kompakt).
///
/// Layout:
///   • links: Pink-Begrüßung („Salut Frank") + Streak inline darunter
///     (🔥 X Tag(e) — sekundärer Text, keine Card, kein Background)
///   • rechts: Maskottchen (SplashCharacter + Blink-Overlay), Rechte
///     Kante bündig mit dem Hero-Grid darunter
///
/// Die frühere separate `HomeCompactStatusCard` ist entfallen — Streak
/// wird inline im Header als sekundärer Text geführt. Dadurch spart
/// der Screen eine komplette Card-Zeile + Abstand und Home wirkt
/// oben spürbar schlanker.
struct HomeHeader: View {
    let greeting: String
    let streakDays: Int
    var mascotImageName: String = "SplashCharacter"

    /// 48 → 42 pt (−12 %): User-Wunsch „Axolotl darf nicht stärker
    /// wirken als die Hero-Cards".
    private static let mascotSize: CGFloat = 42

    @State private var blinkStartDate: Date = .now

    private var streakLine: String {
        "🔥 \(streakDays) \(streakDays == 1 ? "Tag" : "Tage")"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                // Salut-Zeile: 22 → 21 pt (Header-Kompakt-Pass 2).
                // Gewicht .black bleibt — Pink-Akzent soll auch auf
                // kleinerem Text noch dominant lesbar sein.
                Text(greeting)
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.elumiPink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)

                // Streak inline als sekundärer Text — kein Card-
                // Wrapper, kein Border, keine eigene Höhe. Nimmt
                // damit fast keinen zusätzlichen Platz ein.
                Text(streakLine)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(1)
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
            // Rechte Kante bündig mit Hero-Grid. `y: -2` zieht den
            // Mascot minimal über die Salut-Baseline — ohne den alten
            // aggressiven `−10` Pull-Up.
            .offset(y: -2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .task {
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
