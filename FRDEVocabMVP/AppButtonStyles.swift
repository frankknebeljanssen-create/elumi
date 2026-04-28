import SwiftUI

struct AppPrimaryButtonStyle: ButtonStyle {
    var color: Color = AppTheme.Colors.cta
    /// Haptic-Feedback beim Press. Default `true`, weil Primary-
    /// Buttons per Definition „wichtige Aktionen" sind — genau
    /// dort wollen wir spürbares Feedback (Phase 7.6 Debug-Pass).
    var haptic: Bool = true

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
                    .fill(color.opacity(configuration.isPressed ? 0.80 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .stroke(Color.black.opacity(0.10), lineWidth: 1)
            )
            .shadow(
                color: AppTheme.Shadow.button.color,
                radius: configuration.isPressed ? 2 : AppTheme.Shadow.button.radius,
                x: AppTheme.Shadow.button.x,
                y: configuration.isPressed ? 1 : AppTheme.Shadow.button.y
            )
            // Phase 7.6 Debug-Pass — kräftigeres Feedback:
            // Scale 0.95, Opacity auf den Fill drops 20%, Shadow
            // schrumpft spürbar. Dazu leichtes Tap-Haptic.
            .scaleEffect(configuration.isPressed ? AppMotion.Scale.buttonPress : 1)
            .animation(AppMotion.tap, value: configuration.isPressed)
            .onChange(of: configuration.isPressed) { _, isPressed in
                if haptic && isPressed {
                    AppMotion.triggerSelectionHaptic()
                }
            }
    }
}

/// **AppCardPressStyle** — systemweiter Tap-Feedback-Stil für alle
/// tappbaren Cards (Home-Hero-Grid, Weitere Übungen, Tools, Status-
/// Card, Pokal, Scan-Setup-Cards …).
///
/// Phase 7.6 Debug-Pass (User-Report „auf Gerät kaum sichtbar"):
/// Scale 0.97 (statt 0.98), Opacity 0.85 (statt 0.92), zusätzlich
/// dezenter Brightness-Drop (-0.05) für deutlich spürbaren Press.
///
/// Doppel-/Dreifach-Signal (Scale + Opacity + Brightness) greift
/// auch auf komplexen Cards mit Gradients/Overlays, wo ein einzelner
/// Effekt von überlappenden View-Transformationen geschluckt werden
/// kann.
///
/// Nutzung: `Button { ... } label: { ... }.buttonStyle(AppCardPressStyle())`
/// statt `.buttonStyle(.plain)` auf allen tappbaren Modul-/Home-Cards.
struct AppCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // **Phase 7.6 Debug-Visibility-Pass**: sehr deutliche Werte,
            // damit ein Press auf dem Gerät unmissverständlich sichtbar
            // ist. Wenn das hier nicht wirkt, liegt der Grund **nicht**
            // im Style, sondern an einer überdeckenden Touch-Fläche
            // oder einem Parent-Gesture. Nach Verifizierung kann hier
            // wieder zurück auf 0.97 / 0.85 gedreht werden.
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .brightness(configuration.isPressed ? -0.1 : 0)
            .animation(AppMotion.tap, value: configuration.isPressed)
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
            // Phase 7.6 — zentrale Konstanten aus `AppMotion`.
            .scaleEffect(configuration.isPressed ? AppMotion.Scale.buttonPress : 1)
            .animation(AppMotion.tap, value: configuration.isPressed)
    }
}
