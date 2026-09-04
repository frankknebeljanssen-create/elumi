import SwiftUI
import UIKit

extension Color {
    /// Vereinfachte Luminanz-Heuristik: hell genug für schwarzen Text?
    /// Berücksichtigt Alpha, weil halbtransparente Farben (z. B.
    /// `textDisabled`) auf dunklem App-Hintergrund effektiv dunkler
    /// wirken als ihre reine RGB-Komponente.
    var isLightBackground: Bool {
        guard let components = UIColor(self).cgColor.components, components.count >= 3 else {
            return true
        }
        let alpha = components.count >= 4 ? components[3] : 1.0
        let luminance = 0.299 * components[0] + 0.587 * components[1] + 0.114 * components[2]
        return (luminance * alpha) > 0.6
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    var color: Color = AppTheme.Colors.cta
    /// Haptic-Feedback beim Press. Default `true`, weil Primary-
    /// Buttons per Definition „wichtige Aktionen" sind — genau
    /// dort wollen wir spürbares Feedback (Phase 7.6 Debug-Pass).
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Typography.button)
            // Kontrastsicher statt hartkodiert Schwarz — bei hellem
            // `color` (z. B. CTA-Amber) bleibt Schwarz, bei dunklerem/
            // transparentem `color` (z. B. textDisabled) wird auf Weiß
            // gewechselt, damit der Text nicht unlesbar wird.
            .foregroundStyle(color.isLightBackground ? Color.black : Color.white)
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

/// **AppDestructiveButtonStyle** — gefüllter destruktiver CTA: rot-solid
/// (`AppTheme.Colors.error`) + weißer Text. Spiegelt `AppPrimaryButtonStyle`
/// (Höhe/Radius/Press-Feedback identisch), nur Error-Rot statt Amber und
/// weiße statt schwarze Schrift (Kontrast auf gesättigtem Rot). Gedacht für
/// destruktive Primär-Aktionen (z. B. Bulk-Löschen in der Multi-Select-Bar).
struct AppDestructiveButtonStyle: ButtonStyle {
    var color: Color = AppTheme.Colors.error
    var haptic: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Typography.button)
            .foregroundStyle(Color.white)
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
                color: color.opacity(0.18),
                radius: configuration.isPressed ? 2 : 10,
                x: 0,
                y: configuration.isPressed ? 1 : 4
            )
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
    /// **2026-05-02** — optionaler Foreground-Override unabhängig vom
    /// `tint`. Default `nil` → `tint` greift wie bisher (Border + Text
    /// einheitlich Modul-Akzent). Bei sehr dunklen Modul-Akzenten
    /// (z.B. Vokabeln-Indigo `#1E3A8A`) entsteht aber dunkler Text auf
    /// dunklem `secondarySurface` — unlesbar. Caller kann hier
    /// `AppTheme.Colors.textPrimary` (cream) durchreichen, um den
    /// Text hell zu zwingen, während der Border in Modul-Akzent
    /// bleibt. Konsistent zum Pre-Screen-Pill-Fix vom selben Tag.
    var foreground: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.Typography.button)
            .foregroundStyle(foreground ?? tint)
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
