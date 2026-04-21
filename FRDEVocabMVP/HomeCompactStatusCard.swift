import SwiftUI

/// **Kompakte Status-Card** unter dem Home-Greeting (Home-Rebuild).
///
/// Zeigt ausschließlich den aktuellen Tages-Streak (`X 🔥 Tag/Tage`). Die
/// frühere Lernstand-Phrase rechts daneben ist entfernt — der Screen
/// wird dadurch ruhiger, die ausführliche Detail-Darstellung lebt im
/// Pokal-Tab. Tap auf die Card öffnet den Pokal.
struct HomeCompactStatusCard: View {
    let streakDays: Int
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // Streak als eine zusammengehörige Angabe: Flamme + Zahl +
            // „Tag/Tage" in identischer Fontgröße/-gewichtung.
            HStack(spacing: 6) {
                Text("🔥")
                    .font(.system(size: 19))
                Text("\(streakDays)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .monospacedDigit()
                Text(streakDays == 1 ? "Tag" : "Tage")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.secondarySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(AppTheme.Colors.border.opacity(0.35), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
