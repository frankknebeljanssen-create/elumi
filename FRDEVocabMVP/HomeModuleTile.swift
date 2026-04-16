import SwiftUI

/// Einheitliche Modul-Card im Home-Grid. **Eine** Komponente für alle
/// Module — verhindert Mischungen aus SF-Symbols, Eigen-Schriften und
/// SVG-Icons.
///
/// Layout (kompakt für 4×2-Grid):
///   • Icon oben (SVG aus `HomeModuleIcon`)
///   • Titel unten (gerounded, bold)
///
/// Der Akzent steckt in einem sehr dezenten Background-Tint, nicht im
/// Border — die Icons bleiben die visuelle Hauptquelle.
struct HomeModuleTile: View {
    let icon: HomeModuleIcon
    let title: String
    let accent: Color
    let isPressed: Bool
    let onTap: () -> Void

    /// Default 44 pt — gewählt für 4-Spalten-Grid (≈ 68 pt Card-Breite
    /// nach Padding auf einem iPhone). Das matcht die Design-Spec
    /// („Icons alle gleich groß"), bleibt aber sichtbar auf einen
    /// Blick.
    var iconSize: CGFloat = 44
    /// Default-Höhe; bleibt in allen Grid-Cards gleich.
    var minHeight: CGFloat = 86

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                HomeModuleIconView(icon: icon, size: iconSize)
                    .frame(height: iconSize)

                Text(title)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(
                color: AppTheme.Shadow.card.color.opacity(isPressed ? 0.75 : 0.6),
                radius: isPressed ? 8 : 5,
                x: 0,
                y: isPressed ? 4 : 2
            )
            .scaleEffect(isPressed ? 0.965 : 1.0)
            .opacity(isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(AppTheme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(accent.opacity(0.09))
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .stroke(AppTheme.Colors.border.opacity(0.55), lineWidth: 1)
    }
}
