import SwiftUI
import UIKit

/// Wiederverwendbare Choice-Card für den Scan-Auswahl-Screen.
///
/// Layout (Scan-Redesign 2026-05-21):
///   • oben links: Custom-Illustration 32pt
///   • darunter: Titel 17pt (bold) — vertikal, analog WAS-Cards
///   • kein Chevron (kompakte Card, gleiche Höhe wie die Modus-Cards)
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
    let accent: Color
    var isPriority: Bool = false
    /// Optionaler Hinweis am unteren Rand: zeigt den aktuell gewählten
    /// Modus („Scan als: Vokabelliste"). Gibt dem User Sicherheit, in
    /// welchem Modus die KI das Foto interpretieren wird.
    var modeHint: String? = nil
    /// Optionaler **Card-Tint** (Phase 7.6+): dezent eingefärbter
    /// Background in der Farbe der jeweiligen Quelle (Kamera grün,
    /// Foto-Album violett). Wenn `nil`, bleibt die Card im neutralen
    /// Setup-Card-Look. Tint wird mit 8 %-Opacity als zusätzliche
    /// Ebene über dem `setupCardBackground` gerendert — sehr subtil,
    /// erkennbar ohne aufdringlich zu sein.
    var baseTint: Color? = nil
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
            VStack(alignment: .leading, spacing: 8) {
                // **Scan-Redesign (2026-05-21)** — Icon oben links, Titel
                // darunter (Layout wie die WAS-Cards) → „Foto-Album" passt in
                // voller Breite + gleiche Card-Höhe wie WAS. Glow im Pressed-State.
                Image(illustrationName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .scaleEffect(isPressed ? 1.05 : 1.0)
                    .brightness(isPressed ? 0.12 : 0)
                    .shadow(
                        color: isPressed ? accent.opacity(0.45) : .black.opacity(0.12),
                        radius: isPressed ? 8 : 4,
                        x: 0,
                        y: 2
                    )

                // Titel 17pt = WAS-Card-Größe → konsistentes 2×2-Grid.
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                // Modus-Hint — sehr subtil (von den WOHER-Cards nicht genutzt).
                if let modeHint, !modeHint.isEmpty {
                    Text(modeHint)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.55))
                }
            }
            // Scan-Redesign: Radius 22 → 16, Chevron entfernt (Pillen-Anmutung).
            // „Cards mehr Platz" (2026-05-21): vertikales Padding 18 → Card ~+20%
            // höher (gleich WAS), horizontal 14.
            .padding(.horizontal, 14)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.Colors.setupCardBackground)
                    // Optionaler Quellen-Tint: subtile 8 %-Füllung in der Farbe
                    // der Quelle — Kamera grün, Foto-Album violett.
                    if let baseTint {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(baseTint.opacity(0.08))
                    }
                    // Priority (Kamera) bekommt einen ganz subtilen Akzent-Tint.
                    if isPriority {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(accent.opacity(0.06))
                    }
                    // Pressed → leichte Aufhellung der gesamten Card.
                    if isPressed {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Color.white.opacity(0.04))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
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
                        .frame(width: 32, height: 32)
                    Spacer(minLength: 0)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isSelected ? accent : AppTheme.Colors.textSecondary.opacity(0.35))
                        .scaleEffect(isSelected ? checkScale : 1.0)
                }

                // Subtext („Ich erkenne Wörter …" / „Ich analysiere ganze
                // Sätze …") wurde bewusst entfernt — die Illustration +
                // Titel genügen für den Modus-Switch, der Zusatzsatz hat
                // die Card überfrachtet.
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            // „Cards mehr Platz" (2026-05-21): vertikales Padding 18 → ~+20% höher
            // (gleich den WOHER-Cards), horizontal 14.
            .padding(.vertical, 18)
            .padding(.horizontal, 14)
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
    // Scan-Redesign: 70 → 56 (Header kompakter, damit „Meine Scans"
    // above-the-fold rückt).
    private static let mascotSize: CGFloat = 56

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            VStack(alignment: .leading, spacing: 0) {
                Text("Was möchtest du scannen?")
                    // Scan-Redesign: 25 → 18 pt (Header kompakter). Weight
                    // bleibt .black (App-Pattern), nur Größe runter.
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
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
            // Mascot etwas höher: y-Offset 10 → −6 (User-Wunsch).
            .offset(y: -6)
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
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.55))
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }
}
