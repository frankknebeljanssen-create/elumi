import SwiftUI

/// Systemweiter Zurück-Button.
///
/// **Einheitliche Darstellung in der gesamten App** — kein „Zurück"-Text,
/// kein Hintergrund-Rechteck, keine abweichende Farbgebung. Nur ein
/// einzelnes `chevron.left`-Symbol in der Primär-Textfarbe. Die Touch-
/// Fläche ist 44 × 44 pt (Apple HIG), der Chevron selbst bleibt
/// optisch schlank.
///
/// Wird genutzt von `AppTopBar`, `ScreenHeaderCard`, `SessionSetupHeader`
/// und den Session-eigenen Headern (Training, Karteikarten). Neue Screens
/// sollen diese Komponente immer verwenden — keine lokalen Chevron-
/// Varianten mehr.
struct AppBackButton: View {
    let action: () -> Void
    /// Optionaler Farbton; Default: Primär-Textfarbe. Session-Module,
    /// die ihren Back-Pfeil in Akzentfarbe haben wollen, können das
    /// hier setzen. Empfehlung: meistens Default nutzen.
    var tint: Color = AppTheme.Colors.textPrimary

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Zurück"))
    }
}
