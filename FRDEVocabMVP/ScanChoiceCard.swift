import SwiftUI
import UIKit

/// Wiederverwendbare Choice-Card für den Scan-Auswahl-Screen.
///
/// Layout (per Spec):
///   • links: Custom-Illustration ~64–72pt
///   • rechts: Titel (bold) + Subtitle (sekundär)
///   • ganz rechts: Chevron (transparent)
///
/// Tap-Feedback (per Spec):
///   • Card scaliert auf 0.97
///   • Icon wird leicht heller (+0.10 brightness)
///   • Subtiler Outline-Ring im Akzent
///   • Light-Haptic-Impact
///   • ~120 ms Verzögerung, dann Action
///
/// `isPriority` hebt die Top-Optionen (Vokabelliste / Kamera) leicht an —
/// minimal stärkerer Akzent-Border, kein Größen-Sprung. Bewusst dezent.
struct ScanChoiceCard: View {
    let illustrationName: String
    let title: String
    let subtitle: String
    let accent: Color
    var isPriority: Bool = false
    /// Optionaler Hinweis am unteren Rand: zeigt den aktuell gewählten
    /// Modus („Scan als: Vokabelliste"). Gibt dem User Sicherheit, in
    /// welchem Modus die KI das Foto interpretieren wird.
    var modeHint: String? = nil
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            isPressed = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                isPressed = false
                action()
            }
        } label: {
            HStack(spacing: 14) {
                // Icon mit subtilem Glow im Pressed-State (statt rotem
                // Outline-Ring auf der Card).
                Image(illustrationName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 68, height: 68)
                    .scaleEffect(isPressed ? 1.05 : 1.0)
                    .brightness(isPressed ? 0.12 : 0)
                    .shadow(
                        color: isPressed ? accent.opacity(0.45) : .black.opacity(0.12),
                        radius: isPressed ? 8 : 4,
                        x: 0,
                        y: 2
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: isPriority ? 20 : 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(subtitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.7))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    // Modus-Hint — gibt subtile Sicherheit, in welchem
                    // Modus die KI gleich analysiert.
                    if let modeHint, !modeHint.isEmpty {
                        Text(modeHint)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(accent.opacity(0.85))
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.4))
            }
            .padding(.horizontal, isPriority ? 18 : 16)
            .padding(.vertical, isPriority ? 18 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(AppTheme.Colors.setupCardBackground)
                    // Priority bekommt einen ganz subtilen Akzent-Tint
                    // (nicht über die Outline) — führt den Blick ohne den
                    // Look zu zerschneiden.
                    if isPriority {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(accent.opacity(0.06))
                    }
                    // Pressed → leichte Aufhellung der gesamten Card
                    // (statt roter Outline). Brighter in einem ruhigen Stil.
                    if isPressed {
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        AppTheme.Colors.setupCardBorder,
                        lineWidth: 1
                    )
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .shadow(
                color: isPressed ? .black.opacity(0.18) : .black.opacity(0.10),
                radius: isPressed ? 10 : 6,
                x: 0,
                y: isPressed ? 5 : 3
            )
            .animation(.easeOut(duration: 0.15), value: isPressed)
        }
        .buttonStyle(.plain)
    }
}

/// Modus-Auswahl-Card für den Scan-Screen. **Kein** Navigations-Element —
/// reine Toggle-Selection (Vokabelliste / Freier Text). Tap ändert nur
/// die Modus-Auswahl, der User bleibt auf dem Screen.
///
/// Design:
///   • aktiv: Accent-Border 1.5pt + 10%-Accent-Background-Tint
///   • inaktiv: setupCardBorder, ruhig
///   • Checkmark-Indikator oben rechts wenn aktiv
///   • KEIN Chevron, KEIN Shadow-Sprung
struct ScanModeSelectionCard: View {
    let illustrationName: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 0) {
                    Image(illustrationName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 44, height: 44)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isSelected ? accent : AppTheme.Colors.textSecondary.opacity(0.4))
                }

                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.7))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(AppTheme.Colors.setupCardBackground)
                    if isSelected {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(accent.opacity(0.10))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(
                        isSelected ? accent : AppTheme.Colors.setupCardBorder,
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
            .animation(.easeOut(duration: 0.18), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

/// Hero-Card oben im Scan-Screen — Maskottchen + Frage + Subtext. Kein
/// CTA, nur emotionaler Einstieg.
struct ScanHeroCard: View {
    let mascotImageName: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            Image(mascotImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                // Subtitle kleiner + weniger Kontrast — wirkt ruhiger,
                // Titel bekommt klaren Fokus.
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.6))
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.Colors.setupCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.Colors.setupCardBorder, lineWidth: 1)
        )
    }
}

/// Header-Block des neuen Scan-Screens — links-bündig.
/// Nur der Titel „Scan" — Frage + Subtext leben in der HeroCard
/// darunter, daher hier bewusst keine Wiederholung.
struct ScanScreenHeader: View {
    var body: some View {
        Text("Scan")
            .font(.system(size: 32, weight: .black, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Kleines Sektions-Label (uppercase, tracking) für die Trennung
/// „MODUS" / „QUELLE" im Scan-Screen.
struct ScanSectionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .black, design: .rounded))
            .tracking(1.4)
            .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.7))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}
