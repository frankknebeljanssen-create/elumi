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

                VStack(alignment: .leading, spacing: 3) {
                    // Klare 3-stufige Typo-Hierarchie:
                    //   Titel groß — Subtext mittel — Modus-Hint klein.
                    Text(title)
                        .font(.system(size: isPriority ? 22 : 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.7))
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)

                    // Modus-Hint — sehr subtil, nicht wie ein Tag.
                    if let modeHint, !modeHint.isEmpty {
                        Text(modeHint)
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.55))
                            .padding(.top, 3)
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
/// Design (final, ruhig):
///   • aktiv: dezenter Accent-Tint im Background (8%) + sehr subtiler
///     Akzent-Border (15%-Opacity, 1pt) — Checkmark ist Hauptsignal
///   • inaktiv: setupCardBorder, ruhig
///   • visuell flacher als die Quelle-Cards (kein Shadow)
struct ScanModeSelectionCard: View {
    let illustrationName: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let accent: Color
    let onTap: () -> Void

    @State private var checkScale: CGFloat = 1.0

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            // Mini Spring auf den Checkmark beim Aktivieren — fühlt sich
            // „lebendig" an, ohne den Stil zu brechen.
            withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                checkScale = 1.25
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.7)) {
                    checkScale = 1.0
                }
            }
            onTap()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 0) {
                    Image(illustrationName)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isSelected ? accent : AppTheme.Colors.textSecondary.opacity(0.35))
                        .scaleEffect(isSelected ? checkScale : 1.0)
                }

                Text(title)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.65))
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
                        // Selected-Signal NUR über Background-Tint —
                        // kein Border-Wechsel, damit die Cards weniger
                        // wie Action-Buttons und mehr wie Toggle-Tiles wirken.
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(accent.opacity(0.16))
                    }
                }
            )
            .overlay(
                // Border bleibt konstant — keine visuelle Differenzierung
                // mehr über die Outline. Ruhiger, weniger "Button"-Look.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppTheme.Colors.setupCardBorder, lineWidth: 1)
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
                // Subtitle nochmal eine Stufe ruhiger — wirkt klar
                // sekundär, Titel hat den Fokus für sich.
                Text(subtitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.5))
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

/// Kombinierter Header-Block des Scan-Screens.
/// Links: Hauptfrage + Subtext. Rechts: Maskottchen, dessen Augen
/// regelmäßig zwinkern — über den bestehenden `SplashCharacterBlinkOverlay`,
/// der die Lider exakt auf die Augen-Positionen legt.
struct ScanScreenHeader: View {
    @State private var blinkStartDate: Date = .now
    private static let mascotSize: CGFloat = 88

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Was möchtest du scannen?")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)

                Text("Ich passe die Analyse automatisch an")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.55))
                    .padding(.top, 4)
            }

            Spacer(minLength: 0)

            ZStack {
                Image("SplashCharacter")
                    .resizable()
                    .scaledToFit()
                    .frame(width: Self.mascotSize, height: Self.mascotSize)
                // Echtes Augen-Zwinkern via existierendem Overlay —
                // legt die Lider exakt auf die Pupillen. Wird periodisch
                // re-startet, damit immer wieder geblinzelt wird.
                SplashCharacterBlinkOverlay(
                    size: Self.mascotSize,
                    startDate: blinkStartDate
                )
                .frame(width: Self.mascotSize, height: Self.mascotSize)
            }
            .offset(y: 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 6)
        .task {
            // Der Overlay blinzelt zweimal innerhalb seiner Session-Range
            // (bei 1.35s und 3.15s nach startDate). Wir restarten den
            // Zyklus alle ~4s mit minimaler Random-Jitter, damit's
            // natürlich wirkt und nicht zu mechanisch.
            while !Task.isCancelled {
                let interval = UInt64.random(in: 3_800...4_400) * 1_000_000
                try? await Task.sleep(nanoseconds: interval)
                await MainActor.run {
                    blinkStartDate = .now
                }
            }
        }
    }
}

/// Sektions-Label im Scan-Screen — als Schritt-Indikator („1. Wähle …",
/// „2. Wähle …"). Klarer als die alte technische „MODUS"/„QUELLE"-
/// Überschrift, kommuniziert Flow-Reihenfolge.
struct ScanSectionLabel: View {
    let stepNumber: Int
    let title: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(stepNumber).")
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.55))
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
