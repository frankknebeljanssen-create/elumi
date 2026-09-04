import SwiftUI

/// Klein, dezent, aber eindeutig: signalisiert dem User auf **jedem**
/// Scan-Screen (Camera, Processing, Preview, Review), in welchem Modus
/// er gerade scannt. Soll nie dominieren — der User soll den Modus
/// jederzeit sehen können, ohne dass das Badge den Bildinhalt
/// überlagert.
///
/// **Farbcodierung** (User-Wunsch):
///   • `.list` (Vokabelliste) → leicht grünlich — „Structured data"-
///     Assoziation, passt zur Vokabel-Domäne.
///   • `.text` (Freier Text)  → leicht bläulich — passt zur
///     FreeText/Scene-Domäne und harmoniert mit dem Attention-Overlay.
///
/// **Zwei Renderstile** über `variant`:
///   • `.overlay` — halbtransparenter dunkler Hintergrund + farbige
///     Border. Für Screens, die über der Kamera oder einem Bild
///     liegen (Camera, Processing, Preview).
///   • `.card`    — auf hellem Card-Hintergrund, mit farbiger
///     Capsule-Fläche. Für Review-Screens ohne Bild-Hintergrund.
struct ScanModeBadge: View {

    let mode: ScanMode
    let variant: Variant

    enum Variant {
        /// Über Kamera-/Bild-Hintergrund — dunkle halbtransparente
        /// Capsule mit farbiger Akzent-Border.
        case overlay
        /// Auf Card-/Screen-Hintergrund — farbige Capsule mit
        /// dunklem Text.
        case card
    }

    init(mode: ScanMode, variant: Variant = .overlay) {
        self.mode = mode
        self.variant = variant
    }

    private var accent: Color {
        switch mode {
        case .list: return AppTheme.Colors.success   // grün
        case .text: return AppTheme.Colors.elumiBlue // blau
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: mode.badgeSystemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(mode.badgeTitle)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(background)
        .overlay(border)
        .clipShape(Capsule())
        .accessibilityLabel(mode.badgeTitle)
    }

    @ViewBuilder
    private var background: some View {
        switch variant {
        case .overlay:
            Capsule().fill(Color.black.opacity(0.55))
        case .card:
            Capsule().fill(accent.opacity(0.18))
        }
    }

    @ViewBuilder
    private var border: some View {
        switch variant {
        case .overlay:
            Capsule().stroke(accent.opacity(0.85), lineWidth: 1.2)
        case .card:
            Capsule().stroke(accent.opacity(0.6), lineWidth: 1)
        }
    }

    private var textColor: Color {
        switch variant {
        case .overlay: return .white
        case .card:    return accent
        }
    }
}

// MARK: - Convenience-Initializer aus `ScanCaptureProfile`

extension ScanModeBadge {
    /// Convenience-Initializer für die SmartScannerView-Pfade, die nur
    /// das `ScanCaptureProfile` kennen (nicht das `ScanMode`-Enum).
    init(profile: ScanCaptureProfile, variant: Variant = .overlay) {
        switch profile {
        case .vocabularyList: self.init(mode: .list, variant: variant)
        case .freeText:       self.init(mode: .text, variant: variant)
        }
    }
}
