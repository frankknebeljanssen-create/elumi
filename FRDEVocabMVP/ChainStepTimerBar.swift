import SwiftUI

/// **Trainings-Chain Step-Timer-Bar** (Stufe 4a, 2026-05-01,
/// Branch `feature/training-session-flow`).
///
/// Schmale Status-Zeile, die während eines aktiven Chain-Steps oben
/// in jedem Modul-View eingeblendet wird (via `ChainTimerOverlay-
/// Modifier`). Zeigt:
///   • links: Step-Indikator („Übung 2 von 3") + Modul-Name
///   • rechts: verbleibende Zeit als „M:SS"
///   • unten: dünner Progress-Balken (von voll → leer, normiert auf
///     `stepTotalSeconds`)
///   • Urgency-State < 10 s: Farbe wechselt auf `error` (rot), Pulse-
///     Animation auf der Sekunden-Zahl
///
/// Bewusst **schlanker** als `SpeedRoundTimerCard` — der Chain-Timer
/// ist kein Rundenscore (kein Treffer-Count), nur eine Soft-Cutoff-
/// Anzeige. Layout ist eine Zeile, kein Card. Background ist halb-
/// transparent damit die Bar sich klar vom Modul-Content abhebt,
/// aber nicht visuell dominiert.
///
/// Eingaben:
///   • `stepNumber` — 1-basierter Index („Übung X von Y"); aus
///     `chain.displayStepNumber`
///   • `totalSteps` — Gesamtzahl Module-Steps; aus
///     `chain.totalStepCount`
///   • `moduleName` — Anzeige-Name des aktuellen Steps; aus
///     `chain.currentStep?.title`
///   • `remainingSeconds` / `totalSeconds` — beide aus
///     `TrainingChainStore.shared.stepRemainingSeconds` /
///     `stepTotalSeconds`
struct ChainStepTimerBar: View {
    let stepNumber: Int
    let totalSteps: Int
    let moduleName: String
    let remainingSeconds: Int
    let totalSeconds: Int

    /// Schwelle für Urgency-Highlight — gleiche 10-s-Konvention wie
    /// `SpeedRoundTimerCard.isUrgent`, damit Look-Konsistenz im
    /// Codebase erhalten bleibt.
    private var isUrgent: Bool { remainingSeconds <= 10 && remainingSeconds > 0 }

    /// 0 Sekunden → Soft-Cutoff erreicht. Bar bleibt sichtbar mit
    /// Progress = 0, das Banner darunter (im Modifier) übernimmt die
    /// Hinweis-Kommunikation.
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
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "hourglass")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(foregroundForTime)

                Text("Übung \(stepNumber) von \(totalSteps)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .textCase(.uppercase)

                Text("·")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text(moduleName)
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Spacer(minLength: 8)

                Text(formattedTime)
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(foregroundForTime)
                    .monospacedDigit()
                    .scaleEffect(isUrgent ? 1.08 : 1.0)
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
            .frame(height: 4)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppTheme.Colors.surface.opacity(0.95))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    isUrgent || isExpired
                        ? AppTheme.Colors.error.opacity(0.5)
                        : AppTheme.Colors.border,
                    lineWidth: 1
                )
        )
    }
}
