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

    /// **Polish 2026-05-06** — Prominente Streak-Pill mit Amber-Tint.
    /// Caps-Form (24 pt minHeight), Background = `moduleQuiz` (Amber)
    /// mit Gradient für Tiefe, weiß-translucent Stroke für Lesbarkeit
    /// auf Streifen-Backgrounds. Schrift: 15 pt black rounded weiß.
    /// Drop-Shadow gehalten subtil (radius 3, y=1) — Achievement-
    /// Charakter, nicht aufdringlich.
    private var streakPill: some View {
        Text(streakLine)
            .font(.system(size: 15, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                AppTheme.Colors.moduleQuiz.opacity(0.95),
                                AppTheme.Colors.moduleQuiz.opacity(0.78)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: AppTheme.Colors.moduleQuiz.opacity(0.35), radius: 4, x: 0, y: 2)
            .accessibilityLabel(Text("Streak: \(streakDays) \(streakDays == 1 ? "Tag" : "Tage")"))
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 14) {
                // **Spacing-Polish 2026-05-06** — Salut-Zeile von
                // 21 → 32 pt (User-Spec „Title-Größe erhöhen, mehr
                // Atemraum oben"). Vorherige Compact-Variante war für
                // ein ehemaliges enges Layout optimiert; mit dem
                // Hero+Wide-Refactor hat das obere Drittel jetzt
                // genug Platz für eine prominentere Greeting-Zeile.
                // VStack-Spacing von 6 → 14 pt zieht Streak-Pill
                // klar ab vom Greeting (vorher fast geklebt).
                Text(greeting)
                    .font(.system(size: 32, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.elumiPink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                // **Polish 2026-05-06** — Streak von Plain-Text-Zeile zu
                // einer prominenten Pill mit Amber-Tint-Background +
                // dezentem Glow. Vorher: 14 pt semibold textSecondary
                // (winzig, kaum als Achievement erkennbar). Jetzt:
                // 16 pt black rounded auf einer Capsule mit Modul-
                // Quiz-Amber-Hintergrund (Feuer-Vibe), heller Stroke
                // für Pop-Effekt. Konsistenz mit der Methoden-Cards-
                // Designsprache (Gradient-Fill, leichter Drop-Shadow).
                streakPill
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
