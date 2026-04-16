import SwiftUI

/// Einheitliche Modul-Card im Home-Grid. **Eine** Komponente für alle
/// Module — verhindert Mischungen aus SF-Symbols, Eigen-Schriften und
/// SVG-Icons.
///
/// Der Akzent steckt in einem sehr dezenten Background-Tint, nicht im
/// Border — die Icons bleiben die visuelle Hauptquelle. Die Card-Größe
/// wird über `size` gesteuert (`.hero` fürs 2×2-Hauptgrid, `.compact`
/// für die sekundären Reihen) — so bleibt die visuelle Sprache
/// einheitlich, der Inhalt hierarchisiert.
struct HomeModuleTile: View {
    enum Size {
        /// Groß — Modul ist primärer Einstieg. Nutzt das Hero-Grid.
        case hero
        /// Kompakt — Modul ist sekundärer Einstieg. Nutzt die Reihe
        /// unterhalb des Hero-Grids.
        case compact
    }

    let icon: HomeModuleIcon
    let title: String
    let accent: Color
    let isPressed: Bool
    let onTap: () -> Void

    var size: Size = .hero
    /// Wenn `true`, wird die Kachel visuell schwächer gezeichnet — der
    /// Akzent-Tint halbiert und der Titel rückt in den sekundären
    /// Text-Ton. Gedacht für Organisations-Einträge (z. B. Listen),
    /// die zwar mit im Grid laufen sollen, aber kein gleichwertiges
    /// Lernmodul sind.
    var deemphasized: Bool = false

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: spec.iconTextSpacing) {
                HomeModuleIconView(icon: icon, size: spec.iconSize)
                    .frame(height: spec.iconSize)
                    .opacity(deemphasized ? 0.78 : 1)

                Text(title)
                    .font(.system(size: spec.titleFontSize, weight: .black, design: .rounded))
                    .foregroundStyle(
                        deemphasized
                            ? AppTheme.Colors.textSecondary
                            : AppTheme.Colors.textPrimary
                    )
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 6)
            .padding(.vertical, spec.verticalPadding)
            .frame(maxWidth: .infinity, minHeight: spec.minHeight)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: spec.cornerRadius, style: .continuous))
            .shadow(
                color: AppTheme.Shadow.card.color.opacity(isPressed ? 0.8 : spec.shadowOpacity * (deemphasized ? 0.6 : 1.0)),
                radius: isPressed ? spec.shadowRadius + 3 : spec.shadowRadius,
                x: 0,
                y: isPressed ? spec.shadowY + 1 : spec.shadowY
            )
            .scaleEffect(isPressed ? 0.965 : 1.0)
            .opacity(isPressed ? 0.92 : 1.0)
            .animation(.easeOut(duration: 0.12), value: isPressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: spec.cornerRadius, style: .continuous)
            .fill(AppTheme.Colors.surface)
            .overlay(
                RoundedRectangle(cornerRadius: spec.cornerRadius, style: .continuous)
                    .fill(accent.opacity(spec.accentTintOpacity * (deemphasized ? 0.5 : 1.0)))
            )
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: spec.cornerRadius, style: .continuous)
            .stroke(AppTheme.Colors.border.opacity(0.55), lineWidth: 1)
    }

    private var spec: Spec {
        switch size {
        case .hero:
            return Spec(
                iconSize: 72,
                iconTextSpacing: 10,
                titleFontSize: 16,
                verticalPadding: 14,
                minHeight: 148,
                cornerRadius: 22,
                accentTintOpacity: 0.11,
                shadowOpacity: 0.7,
                shadowRadius: 7,
                shadowY: 3
            )
        case .compact:
            return Spec(
                iconSize: 40,
                iconTextSpacing: 4,
                titleFontSize: 12,
                verticalPadding: 8,
                minHeight: 82,
                cornerRadius: 16,
                accentTintOpacity: 0.09,
                shadowOpacity: 0.55,
                shadowRadius: 5,
                shadowY: 2
            )
        }
    }

    private struct Spec {
        let iconSize: CGFloat
        let iconTextSpacing: CGFloat
        let titleFontSize: CGFloat
        let verticalPadding: CGFloat
        let minHeight: CGFloat
        let cornerRadius: CGFloat
        let accentTintOpacity: Double
        let shadowOpacity: Double
        let shadowRadius: CGFloat
        let shadowY: CGFloat
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
                    .strokeBorder(AppTheme.Colors.border.opacity(0.5), lineWidth: 1)
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
