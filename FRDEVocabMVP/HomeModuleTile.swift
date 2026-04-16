import SwiftUI

/// Einheitliche Modul-Card im Home-Grid. **Eine** Komponente für alle
/// Module — verhindert Mischungen aus SF-Symbols, Eigen-Schriften und
/// SVG-Icons.
///
/// Layout:
///   • Icon oben (SVG aus `HomeModuleIcon`)
///   • Titel unten (gerounded, bold)
///
/// Die Card bringt den Akzent über einen sehr dezenten Background-Tint,
/// nicht über den Border — so bleiben die Icons die visuelle Hauptquelle.
struct HomeModuleTile: View {
    let icon: HomeModuleIcon
    let title: String
    let accent: Color
    let isPressed: Bool
    let onTap: () -> Void

    /// Default 64 pt — entspricht Spec (64–72 pt im Grid).
    var iconSize: CGFloat = 64
    /// Default-Höhe; bleibt in allen Grid-Cards gleich, damit die Kacheln
    /// sauber ausgerichtet sind.
    var minHeight: CGFloat = 118

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                HomeModuleIconView(icon: icon, size: iconSize)
                    .frame(height: iconSize)

                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(
                color: AppTheme.Shadow.card.color.opacity(isPressed ? 0.8 : 0.75),
                radius: isPressed ? 10 : 7,
                x: 0,
                y: isPressed ? 5 : 3
            )
            .scaleEffect(isPressed ? 0.965 : 1.0)
            .opacity(isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(AppTheme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(accent.opacity(0.10))
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .stroke(AppTheme.Colors.border, lineWidth: 1)
    }
}

/// Schwache Organisations-Zeile für „Listen" — bewusst visuell getrennt
/// vom Lern-Modul-Grid. Kein Shadow, ruhiger Hintergrund.
struct HomeOrganizationTile: View {
    let icon: HomeModuleIcon
    let title: String
    let subtitle: String
    let isPressed: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                HomeModuleIconView(icon: icon, size: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.7))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.surface.opacity(0.6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppTheme.Colors.border.opacity(0.65), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(isPressed ? 0.975 : 1.0)
            .opacity(isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(subtitle)")
    }
}
