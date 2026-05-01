import SwiftUI

/// **Trainings-Chain Step-Timer-Bar** (Stufe 4a, 2026-05-01,
/// Branch `feature/training-session-flow`).
///
/// Schmale, **kompakte** Status-Zeile, die während eines aktiven
/// Chain-Steps ganz oben (zwischen Status-Bar und Modul-Header)
/// eingeblendet wird (via `ChainTimerOverlayModifier`).
///
/// **Layout-Update 2026-05-01 (Stufe 4a-Fix)**:
/// Vorherige Variante war zu groß (~43 pt zweizeilig). Neue Variante:
///   • EINE Zeile: „⏳ ÜBUNG X VON Y · [Modul-Name] · MM:SS"
///   • Dünner 2-pt-Progress-Strip darunter
///   • Vertical-Padding 4 pt → Total-Höhe ~30 pt
///   • Soft-Cutoff-Banner ist **rausgenommen** — dafür nutzt Stufe 4a
///     jetzt einen mittigen `ChainCutoffToast` (siehe Modifier).
///
/// **Urgency-Verhalten:**
///   • Sekunden ≤ 10 → Sekunden-Zahl rot + leichter Scale-Bounce
///   • Sekunden = 0 (timerExpired) → Komplettzeile in Warning-Rot
///     („0:00" bleibt sichtbar als persistentes Signal)
struct ChainStepTimerBar: View {
    let stepNumber: Int
    let totalSteps: Int
    let moduleName: String
    let remainingSeconds: Int
    let totalSeconds: Int

    /// Schwelle für Urgency-Highlight (rote Sekunden-Zahl + Bounce).
    /// Konsistent mit `SpeedRoundTimerCard.isUrgent` (10-s-Konvention).
    private var isUrgent: Bool { remainingSeconds <= 10 && remainingSeconds > 0 }

    /// 0 Sekunden → Soft-Cutoff erreicht. Zeile bleibt sichtbar mit
    /// Progress = 0 und Warning-Rot — der Toast (im Modifier) übernimmt
    /// die einmalige Hinweis-Kommunikation.
    private var isExpired: Bool { remainingSeconds <= 0 }

    private var formattedTime: String {
        let mm = remainingSeconds / 60
        let ss = remainingSeconds % 60
        return String(format: "%d:%02d", mm, ss)
    }

    private var foregroundForTime: Color {
        if isExpired { return AppTheme.Colors.error }
        if isUrgent { return AppTheme.Colors.error }
        return AppTheme.Colors.warning
    }

    var body: some View {
        VStack(spacing: 3) {
            HStack(alignment: .center, spacing: 6) {
                Image(systemName: "hourglass")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(foregroundForTime)

                Text("ÜBUNG \(stepNumber) VON \(totalSteps)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .textCase(.uppercase)

                Text("·")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text(moduleName)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Spacer(minLength: 6)

                Text(formattedTime)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(foregroundForTime)
                    .monospacedDigit()
                    .scaleEffect(isUrgent ? 1.06 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: remainingSeconds)
            }

            GeometryReader { geo in
                let safeTotal = max(1, CGFloat(totalSeconds))
                let progress = max(0, min(1, CGFloat(remainingSeconds) / safeTotal))
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppTheme.Colors.textSecondary.opacity(0.18))
                    Capsule()
                        .fill(foregroundForTime)
                        .frame(width: max(0, geo.size.width * progress))
                        .animation(.linear(duration: 1.0), value: remainingSeconds)
                }
            }
            .frame(height: 2)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
