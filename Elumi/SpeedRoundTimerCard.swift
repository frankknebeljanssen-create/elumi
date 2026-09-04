import SwiftUI

/// Wiederverwendbare Timer-Card für alle Speed-Round-Modi (Training,
/// Verbformen, Akzente, und alle zukünftigen Module). Zentral an einer
/// Stelle, damit Look + Verhalten überall identisch sind und User-Fixes
/// (Farben, Pulse, Balken-Normierung, Urgency-Schwelle) nicht in drei
/// parallelen Views gepflegt werden müssen.
///
/// Layout (User-Spec):
///   • Oben links: Blitz-Icon + grüne Trefferzahl + „richtig"
///   • Oben rechts: große Sekundenzahl + kleines „s"
///   • Unten: Progress-Balken (von voll → leer, normiert auf
///     `totalSeconds`)
///   • Alles **in einer Card**, mit Urgency-Pulse unter 10 s
///
/// Eingaben:
///   • `remainingSeconds` — verbleibende Sekunden dieser Runde
///   • `totalSeconds` — Gesamtdauer der Runde (für Bar-Normierung),
///     üblicherweise aus `SpeedRoundSettings.currentSeconds`. Schutz
///     gegen 0 via `max(1, ...)` im Body.
///   • `correctCount` — aktuelle Trefferzahl (kann 0 sein)
///   • `sectionStyle` — Modul-Farbschema für den Card-Background
///     (`.train`, `.trainVerbforms`, `.accents`, …)
struct SpeedRoundTimerCard: View {
    let remainingSeconds: Int
    let totalSeconds: Int
    let correctCount: Int
    let sectionStyle: AppSectionStyle

    /// Schwelle, ab der die Card in den Urgency-State kippt (Farbe rot,
    /// Puls, Scale-Bounce). 10 s ist die appweite Konvention (spiegelt
    /// das Legacy-Verhalten in `TrainingView+Components.speedRoundTimerBar`).
    private var isUrgent: Bool { remainingSeconds <= 10 }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isUrgent ? AppTheme.Colors.error : AppTheme.Colors.warning)

                Text("\(correctCount)")
                    .font(.system(size: 29, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.success)
                Text("richtig")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Spacer()

                Text("\(remainingSeconds)")
                    .font(.system(size: 37, weight: .black, design: .rounded))
                    .foregroundStyle(isUrgent ? AppTheme.Colors.error : AppTheme.Colors.warning)
                    .monospacedDigit()
                    .scaleEffect(isUrgent ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: remainingSeconds)
                Text("s")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            GeometryReader { geo in
                // Balken-Normierung auf die **tatsächliche** Gesamtdauer
                // dieser Runde — korrekt bei 20/30/45/60-s-Varianten.
                let safeTotal = max(1, CGFloat(totalSeconds))
                let progress = CGFloat(remainingSeconds) / safeTotal
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.Colors.textSecondary.opacity(0.2))
                    Capsule()
                        .fill(isUrgent ? AppTheme.Colors.error : AppTheme.Colors.warning)
                        .frame(width: max(0, geo.size.width * progress))
                        .animation(.linear(duration: 1.0), value: remainingSeconds)
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .appCardBackground(sectionStyle, intensity: isUrgent ? AppTheme.CardIntensity.strong : AppTheme.CardIntensity.soft)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(isUrgent ? AppTheme.Colors.error.opacity(remainingSeconds % 2 == 0 ? 0.8 : 0.3) : Color.clear, lineWidth: isUrgent ? 2 : 0)
        )
        .opacity(isUrgent ? (remainingSeconds % 2 == 0 ? 1.0 : 0.7) : 1.0)
        .animation(.easeInOut(duration: 0.4), value: remainingSeconds)
    }
}
