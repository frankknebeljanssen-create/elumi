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
        background(AppTheme.Colors.surface.ignoresSafeArea())
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
}
