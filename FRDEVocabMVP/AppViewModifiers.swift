import SwiftUI

struct AppTopBarSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.chromeBarHeight)
            .background {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppTheme.Colors.surface.opacity(0.96))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                            .stroke(AppTheme.Colors.border, lineWidth: 1)
                    )
            }
            .shadow(
                color: AppTheme.Shadow.card.color,
                radius: AppTheme.Shadow.card.radius,
                x: AppTheme.Shadow.card.x,
                y: AppTheme.Shadow.card.y
            )
    }
}

struct AppBottomBarSurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, AppTheme.Layout.screenPadding)
            .padding(.top, AppTheme.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: AppTheme.Layout.footerHeight, alignment: .top)
            .safeAreaPadding(.bottom, AppTheme.Spacing.xs)
            .background {
                AppTheme.Colors.background.opacity(0.98)
                    .ignoresSafeArea(edges: .bottom)
            }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(height: 1)
            }
            .shadow(
                color: AppTheme.Shadow.card.color,
                radius: 10,
                x: 0,
                y: -2
            )
    }
}

extension View {
    func appScreenBackground(_ style: AppSectionStyle) -> some View {
        // System-Pattern: Screen-Hintergrund ist der **dunklere** Ton
        // (`background` = elumiMidnight), Cards darauf nutzen `surface`
        // (= elumiNavy) und heben sich minimal heller ab — identisch zum
        // Home-Screen. Frühere Variante (surface als Screen-Fill) ließ
        // Cards in der gleichen Farbe wie der Screen liegen, dadurch
        // verschwanden sie optisch.
        background(AppTheme.Colors.background.ignoresSafeArea())
    }

    func appCardBackground(_ style: AppSectionStyle, intensity: Double = 0.09, cornerRadius: CGFloat = AppTheme.Radius.lg) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.Colors.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppTheme.Colors.border, lineWidth: 1)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(style.accent.opacity(intensity))
                )
        }
        .shadow(
            color: AppTheme.Shadow.card.color,
            radius: AppTheme.Shadow.card.radius,
            x: AppTheme.Shadow.card.x,
            y: AppTheme.Shadow.card.y
        )
    }

    func appChipBackground(_ style: AppSectionStyle, intensity: Double = 0.12, cornerRadius: CGFloat = AppTheme.Radius.md) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.Colors.secondarySurface)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(style.accent.opacity(intensity), lineWidth: 1)
                )
        }
    }

    /// Setup-Card-Hintergrund (Karteikarten-Auswahl-Screen und analoge Setups).
    /// Nutzt die zentralen Farb-Tokens `setupCardBackground` (#0F2D48) +
    /// `setupCardBorder` (#1A3A55) — Single Source of Truth, sodass alle
    /// Setup-Cards einheitlich aussehen, unabhängig vom Modul-Akzent.
    func appSetupCardBackground(cornerRadius: CGFloat = AppTheme.Radius.lg) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.Colors.setupCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(AppTheme.Colors.setupCardBorder, lineWidth: 1)
                )
        }
        .shadow(
            color: AppTheme.Shadow.card.color,
            radius: AppTheme.Shadow.card.radius,
            x: AppTheme.Shadow.card.x,
            y: AppTheme.Shadow.card.y
        )
    }
}

/// Globaler Section-Header-Label für Setup-Cards (z. B. „AUSGEWÄHLTE LISTEN",
/// „ANZAHL DER KARTEN"). Single Source of Truth für app-weite Konsistenz.
/// Spec: 10pt, weight 600, tracking 1.5, uppercase, linksbündig,
/// Farbe `cardLabel` (= elumiAmber #FFD166).
@ViewBuilder
func setupCardLabel(_ text: String) -> some View {
    Text(text)
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .tracking(1.5)
        .foregroundStyle(AppTheme.Colors.cardLabel)
        .textCase(.uppercase)
        .frame(maxWidth: .infinity, alignment: .leading)
}
