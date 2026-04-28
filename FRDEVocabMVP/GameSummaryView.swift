import SwiftUI

/// **Einheitlicher Summary-Screen für alle Spiele** (Phase 7.5 —
/// Ende-Flow-Vereinheitlichung).
///
/// Ersetzt in Elumi-Arcade das game-spezifische `gameOverOverlay` und
/// in Word Runner das vorherige `SessionSummaryView`-Wrapping. Beide
/// Spiele sehen jetzt **strukturell identisch** aus:
///
///   1. **Icon** (spielspezifisch, via Slot)
///   2. **Headline** — „Stark!", „Gut gemacht!", „Geschafft!"
///   3. **Optional Badge** — „Neuer Highscore"
///   4. **Hero-Wert** — Score oder XP, groß und prominent
///   5. **Stat-Grid** — bis zu 4 Secondary-Stats (Runde, Gefangen,
///      Verpasst, Highscore bei Elumi; Richtig, Fehler, Combo,
///      Dauer bei Word Runner)
///   6. **Primär-CTA** — „Nochmal" (fortsetzen) — optional mit Hint
///   7. **Sekundär-CTA** — „Zur Startseite" / „Schließen"
///
/// **Keine XP/Progress-Bar-Integration** — die lebt bewusst NICHT hier,
/// weil nicht alle Spiele `SessionRewardOutcome` füllen (Elumi-Arcade
/// hat kein XP-System). Reicht die UI mehr Fortschritt liefern, wird
/// das separat via einer optionalen `progressFooter`-Slot bereitgestellt.
///
/// Die Komponente ist **daten-agnostisch**: sie nimmt reine Strings
/// und Callbacks entgegen, kein Session-Modell.
struct GameSummaryView<IconContent: View>: View {

    // MARK: - Daten-Slots

    struct Stat: Equatable {
        let title: String
        let value: String
    }

    let headline: String
    /// Optional zusätzliche Zeile unter der Headline.
    let subtitle: String?
    /// Optional Badge (z. B. „Neuer Highscore"). Wenn `nil`, wird
    /// nichts gerendert.
    let badge: String?

    /// Große Zahl (z. B. „480", „+225").
    let heroValue: String
    /// Label über der Zahl („Punkte", „XP").
    let heroValueLabel: String
    /// Optionale Icon-Farbe für den Hero-Wert (Default: warnings orange
    /// wie in Elumi). Nimmt AppTheme-Farben über den Call-Site.
    let heroValueColor: Color

    /// Bis zu 4 sekundäre Werte (werden in 1×4-Row gezeigt). Leer =
    /// kein Stat-Grid.
    let stats: [Stat]

    // MARK: - CTAs

    let primaryCTALabel: String
    /// Icon-Name für den Primär-CTA (Default "arrow.clockwise").
    let primaryCTAIcon: String
    let primaryCTAEnabled: Bool
    let onPrimaryCTA: () -> Void
    /// Kleiner Hint-Text unter dem Primär-CTA — z. B. „1 Credit übrig"
    /// oder „0 Credits — Lernen bringt Credits". `nil` blendet aus.
    let primaryCTAHint: String?

    let secondaryCTALabel: String
    let onSecondaryCTA: () -> Void

    // MARK: - Slots

    let iconContent: IconContent

    init(
        headline: String,
        subtitle: String? = nil,
        badge: String? = nil,
        heroValue: String,
        heroValueLabel: String,
        heroValueColor: Color = Color(hex: "#F2A93B"),
        stats: [Stat] = [],
        primaryCTALabel: String = "Noch eine Runde",
        primaryCTAIcon: String = "arrow.clockwise",
        primaryCTAEnabled: Bool = true,
        primaryCTAHint: String? = nil,
        onPrimaryCTA: @escaping () -> Void,
        secondaryCTALabel: String = "Zur Startseite",
        onSecondaryCTA: @escaping () -> Void,
        @ViewBuilder icon: () -> IconContent
    ) {
        self.headline = headline
        self.subtitle = subtitle
        self.badge = badge
        self.heroValue = heroValue
        self.heroValueLabel = heroValueLabel
        self.heroValueColor = heroValueColor
        self.stats = stats
        self.primaryCTALabel = primaryCTALabel
        self.primaryCTAIcon = primaryCTAIcon
        self.primaryCTAEnabled = primaryCTAEnabled
        self.primaryCTAHint = primaryCTAHint
        self.onPrimaryCTA = onPrimaryCTA
        self.secondaryCTALabel = secondaryCTALabel
        self.onSecondaryCTA = onSecondaryCTA
        self.iconContent = icon()
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            Color.black.opacity(0.42).ignoresSafeArea()

            VStack(spacing: 18) {
                iconContent
                    .frame(width: 92, height: 92)

                VStack(spacing: 8) {
                    Text(headline)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    if let badge = badge {
                        Text(badge)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.warning)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(AppTheme.Colors.warning.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }

                // Hero-Wert (groß)
                VStack(spacing: 2) {
                    Text(heroValueLabel)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Text(heroValue)
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(heroValueColor)
                        .monospacedDigit()
                        .shadow(color: heroValueColor.opacity(0.25), radius: 8, x: 0, y: 2)
                }

                // Stat-Grid
                if !stats.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(stats.enumerated()), id: \.offset) { _, stat in
                            statCell(stat)
                        }
                    }
                }

                // CTA-Bereich
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        Button(action: onSecondaryCTA) {
                            Text(secondaryCTALabel)
                                .font(AppTheme.Typography.button)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 48)
                        }
                        .buttonStyle(AppSecondaryButtonStyle())

                        Button(action: onPrimaryCTA) {
                            HStack(spacing: 8) {
                                Image(systemName: primaryCTAIcon)
                                    .font(.system(size: 14, weight: .bold))
                                Text(primaryCTALabel)
                                    .font(AppTheme.Typography.button)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                        }
                        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                        .disabled(!primaryCTAEnabled)
                        .opacity(primaryCTAEnabled ? 1.0 : 0.55)
                    }

                    if let hint = primaryCTAHint, !hint.isEmpty {
                        Text(hint)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 24)
            .frame(maxWidth: 344)
            .background(AppTheme.Colors.surface.opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }

    // MARK: - Stat-Cell

    private func statCell(_ stat: Stat) -> some View {
        VStack(spacing: 5) {
            Text(stat.value)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(stat.title)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(AppTheme.Colors.secondarySurface.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
