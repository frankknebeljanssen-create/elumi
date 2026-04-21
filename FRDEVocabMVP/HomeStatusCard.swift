import SwiftUI

/// Home-Status-Card „Heute".
///
/// **Feedback, nicht Steuerung.** Anders als die ehemalige „Dein Fokus
/// heute"-Card gibt diese Card **kein** Tagesziel vor — sie zeigt, was der
/// User heute bereits getan hat. Damit passt sie zum Konzept „User wählt
/// selbst" und ergänzt die Status-Card (Streak/Level/XP) darunter, ohne
/// mit ihr zu konkurrieren.
///
/// Datenquelle: `DailyStatsStore` (zählt zentral in `ProgressService.
/// record(session:)`). Die View kennt nur zwei Zahlen und kein
/// Zielsystem — saubere Trennung zu `DailyChallenge`.
///
/// Layout (konsistent zu den Nachbarn `HomeProgressBoardCard` und
/// `HomeContinueSessionCard`):
///   • Icon-Badge links (Sparkles-Symbol, Akzentfarbe)
///   • Mitte: kleiner Pink-Label „Heute", dann „N Aktionen" + optionale
///     „+N seit letzter Session"-Zeile
///   • Hero-Zahl rechts — dominanter Zählwert in Akzentfarbe
///
/// Tap: der Aufrufer entscheidet (Home leitet auf die zuletzt genutzte
/// Aktivität bzw. den Default-Entry).
struct HomeStatusCard: View {
    let actionsToday: Int
    let actionsSinceLastSession: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .center, spacing: 11) {
                iconBadge

                VStack(alignment: .leading, spacing: 1) {
                    Text("Heute")
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.elumiPink)

                    Text(actionsLabel)
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(.leading)

                    if actionsSinceLastSession > 0 {
                        Text("+\(actionsSinceLastSession) seit letzter Session")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }

                Spacer(minLength: 6)

                heroNumber
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            // −5 pt Höhe gegenüber vorher (User-Request): vertikales
            // Padding 9 → 7 und minHeight 71 → 66. Die Content-Elemente
            // (Icon 38×38, Textblock, Hero-Zahl 28 pt) bleiben
            // unverändert — nur die Luft oben/unten schrumpft. Synchron
            // zur `HomeProgressBoardCard`, damit beide Cards weiterhin
            // als visuelles Paar mit identischer Höhe wirken.
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: AppTheme.Shadow.card.color.opacity(0.5), radius: 5, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Pieces

    private var iconBadge: some View {
        ZStack {
            Circle()
                .fill(AppTheme.Colors.elumiPink.opacity(0.16))
            Image(systemName: "sparkles")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(AppTheme.Colors.elumiPink)
        }
        .frame(width: 38, height: 38)
    }

    /// Dominante Tages-Zahl rechts — liest sich wie ein kompakter Counter.
    /// Font-Größe ist bewusst groß (28 pt) gegenüber der 15-pt-Textzeile
    /// links, damit die Zahl **das** visuelle Ankerelement der Card ist.
    private var heroNumber: some View {
        Text("\(actionsToday)")
            .font(.system(size: 28, weight: .black, design: .rounded))
            .foregroundStyle(AppTheme.Colors.elumiPink)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: actionsToday)
    }

    // MARK: - Text helpers

    /// Deutsche Singular-/Plural-Form — 1 Aktion vs. N Aktionen. Bei 0
    /// zeigt die Zeile „Heute noch nichts gemacht" (User-Wunsch:
    /// freundlicher als das alte „Noch keine Aktionen", weniger
    /// statisch-formal).
    private var actionsLabel: String {
        switch actionsToday {
        case 0:  return "Heute noch nichts gemacht"
        case 1:  return "1 Aktion"
        default: return "\(actionsToday) Aktionen"
        }
    }

    private var accessibilitySummary: String {
        var parts: [String] = ["Heute", actionsLabel]
        if actionsSinceLastSession > 0 {
            parts.append("plus \(actionsSinceLastSession) seit letzter Session")
        }
        return parts.joined(separator: ", ")
    }

    // MARK: - Chrome

    private var cardBackground: some View {
        // Home-Modul-Akzent additiv auf den Surface-Fill — Card liest sich
        // jetzt als Teil des Home-Farbsystems, ohne dass Border/Shadow der
        // Card ihre bewusst weiche Home-Optik verlieren.
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppTheme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppSectionStyle.home.accent.opacity(AppTheme.CardIntensity.soft))
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(AppTheme.Colors.border.opacity(0.5), lineWidth: 1)
    }
}
