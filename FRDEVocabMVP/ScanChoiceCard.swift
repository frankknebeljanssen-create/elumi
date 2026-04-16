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
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button {
            // Sofortiges Feedback: visual press + haptic
            isPressed = true
            UIImpactFeedbackGenerator(style: .light).impactOccurred()

            // Kurze Verzögerung, dann Navigation — User soll die
            // Bestätigung wahrnehmen, bevor der Screen wechselt.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                isPressed = false
                action()
            }
        } label: {
            HStack(spacing: 16) {
                Image(illustrationName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 68, height: 68)
                    .scaleEffect(isPressed ? 1.05 : 1.0)
                    .brightness(isPressed ? 0.10 : 0)
                    .shadow(color: .black.opacity(0.12), radius: 4, x: 0, y: 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: isPriority ? 20 : 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    Text(subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.5))
            }
            .padding(.horizontal, isPriority ? 18 : 16)
            .padding(.vertical, isPriority ? 18 : 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(AppTheme.Colors.setupCardBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(
                        // Pressed → Akzent-Outline; Priority → leicht
                        // stärkerer Border-Ton; Default → setupCardBorder.
                        isPressed
                            ? accent
                            : (isPriority ? accent.opacity(0.40) : AppTheme.Colors.setupCardBorder),
                        lineWidth: isPressed ? 2 : 1
                    )
            )
            .scaleEffect(isPressed ? 0.97 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isPressed)
        }
        .buttonStyle(.plain)
    }
}

/// Hero-Card oben im Scan-Screen — Maskottchen + Frage + Subtext. Kein
/// CTA, nur emotionaler Einstieg vor den 4 Choice-Cards.
struct ScanHeroCard: View {
    let mascotImageName: String
    let title: String
    let subtitle: String
    let accent: Color

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(mascotImageName)
                .resizable()
                .scaledToFit()
                .frame(width: 60, height: 60)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
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
