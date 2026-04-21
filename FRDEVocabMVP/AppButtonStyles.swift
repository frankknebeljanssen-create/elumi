import SwiftUI

struct AppPrimaryButtonStyle: ButtonStyle {
    var color: Color = AppTheme.Colors.cta

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Typography.button)
            // Schwarze Schrift — der CTA-Hintergrund (#FFD166, sonniger Amber)
            // ist hell genug, dass weiße Schrift unleserlich wäre.
            .foregroundStyle(Color.black)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTheme.Layout.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(color.opacity(configuration.isPressed ? 0.88 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
            .shadow(
                color: AppTheme.Shadow.button.color,
                radius: configuration.isPressed ? 4 : AppTheme.Shadow.button.radius,
                x: AppTheme.Shadow.button.x,
                y: configuration.isPressed ? 2 : AppTheme.Shadow.button.y
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// **AppCardPressStyle** (Phase 7.6+) — systemweiter Tap-Feedback-Stil
/// für alle tappbaren Cards (Home-Hero-Grid, Weitere Übungen, Tools,
/// Status-Card, Pokal, etc.).
///
/// Verhalten:
///   • Auf Finger-Down sofort Scale-Down (0.95) — kein Delay, greift
///     im selben Frame wie der Touch-Event.
///   • Auf Release/Drag-Cancel schnelle Spring-Zurück-Animation
///     (response 0.22, dampingFraction 0.55) — natürliches „Pop"-
///     Feedback, minimaler Overshoot.
///   • `scaleEffect` + Spring — keine Opacity-/Shadow-Wackler, die
///     den Render-Path ausbremsen könnten.
///
/// Nutzung: `Button { ... } label: { ... }.buttonStyle(AppCardPressStyle())`
/// statt `.buttonStyle(.plain)` auf allen tappbaren Modul-/Home-Cards.
struct AppCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(
                configuration.isPressed
                    ? .easeOut(duration: 0.08)
                    : .spring(response: 0.22, dampingFraction: 0.55),
                value: configuration.isPressed
            )
    }
}

struct AppSecondaryButtonStyle: ButtonStyle {
    var tint: Color = AppTheme.Colors.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Typography.button)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(minHeight: AppTheme.Layout.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppTheme.Colors.secondarySurface.opacity(configuration.isPressed ? 0.92 : 1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .stroke(tint.opacity(0.18), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.99 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
