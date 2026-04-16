import SwiftUI

// MARK: - Shared Data Models for the Session Setup System
//
// Das globale Session-Setup-System gibt allen Modulen (Karteikarten,
// Quiz, Nomen, Artikel, Verben, Verbformen, Vokabeln) einen **gemeinsamen
// visuellen Aufbau**. Unterschiede leben nur noch in den Optionen und
// den Daten — nicht mehr im grundsätzlichen Screen-Gerüst.
//
// Dieser File enthält:
//   • die gemeinsamen Datenmodelle (`SessionContextData`)
//   • die gemeinsamen View-Komponenten
//     (`SessionCardBackground`, `SessionSetupHeader`,
//      `SessionContextCard`, `SessionGamificationBar`,
//      `GamificationMetric`, `SessionPrimaryCTA`)
//
// Option-Komponenten (Chip-Grid, Slider, Toggle) leben in
// `SessionOptionsComponents.swift`.
// Die generische Screen-Hülle liegt in `SessionSetupScreen.swift`.

/// Kompakte Beschreibung des Auswahl-Kontexts im Kopf eines Setup-Screens
/// („Buch S. 178 · 1 Liste · 35 Nomen").
struct SessionContextData: Equatable {
    let iconName: String
    let accentColor: Color
    let title: String
    let subtitle: String
    let detailText: String?

    init(
        iconName: String,
        accentColor: Color,
        title: String,
        subtitle: String,
        detailText: String? = nil
    ) {
        self.iconName = iconName
        self.accentColor = accentColor
        self.title = title
        self.subtitle = subtitle
        self.detailText = detailText
    }
}

// MARK: - SessionCardBackground
//
// Einheitlicher Card-Hintergrund für alle Setup-Cards. Corner-Radius,
// Fill und Border liegen **hier** — nicht mehr in jeder einzelnen View.

/// Gemeinsamer Karten-Hintergrund im Session-Setup. Nutzt das
/// bestehende Setup-Card-Token (`appSetupCardBackground`), damit die
/// Optik konsistent mit Home- und Hub-Karten bleibt.
struct SessionCardBackground: View {
    var cornerRadius: CGFloat = 24
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(AppTheme.Colors.setupCardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(AppTheme.Colors.setupCardBorder, lineWidth: 1)
            )
    }
}

// MARK: - SessionSetupHeader
//
// Einheitlicher Kopfbereich: kleiner „< Zurück"-Button links, zentraler
// Modultitel, symmetrischer Platzhalter rechts (damit der Titel wirklich
// mittig sitzt und nicht durch die Zurück-Breite verschoben wird).

struct SessionSetupHeader: View {
    let title: String
    let accent: Color
    let onBack: () -> Void

    init(title: String, accent: Color = AppTheme.Colors.primary, onBack: @escaping () -> Void) {
        self.title = title
        self.accent = accent
        self.onBack = onBack
    }

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .center)

            HStack {
                // Systemweiter Back-Button — „Zurück"-Text entfernt,
                // einheitlicher nackter Pfeil. `tint` in Modul-Akzent
                // erlaubt, damit der Setup-Header seine Akzent-Sprache
                // behält.
                AppBackButton(action: onBack, tint: accent)

                Spacer()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        // Systemweites Bottom-Padding — identisch zu allen anderen
        // Headern in der App.
        .padding(.bottom, AppLayout.screenHeaderBottomPadding)
    }
}

// MARK: - SessionContextCard
//
// Der „Ausgewählte Listen"-Block. Einheitlich für alle Module:
// Modul-Icon im getönten Quadrat, Titel + Subtitle + Detail-Text,
// Edit-Button (Pen-Circle) rechts.

struct SessionContextCard: View {
    let data: SessionContextData
    let onEditTapped: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AUSGEWÄHLTE LISTEN")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .tracking(1.4)
                .foregroundStyle(AppTheme.Colors.cardLabel)

            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(data.accentColor.opacity(0.18))
                    Image(systemName: data.iconName)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(data.accentColor)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(data.title)
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    HStack(spacing: 6) {
                        Text(data.subtitle)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        if let detail = data.detailText {
                            Text("·").foregroundStyle(AppTheme.Colors.textSecondary)
                            Text(detail).foregroundStyle(data.accentColor)
                        }
                    }
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)

                Button(action: onEditTapped) {
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(data.accentColor)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle().fill(data.accentColor.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Auswahl bearbeiten"))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SessionCardBackground())
    }
}

// MARK: - SessionGamificationBar
//
// DIE verbindliche Preview-Zeile über dem CTA. Master-Design-Regeln:
// keine Card, kein Rahmen — flache horizontale Zeile mit 4 Metriken.
// Die Bar wird nur mit `SessionEstimate` gefüttert — die View macht
// keinerlei eigene Rechnung.

struct SessionGamificationBar: View {
    let estimate: SessionEstimate

    var body: some View {
        HStack(spacing: 0) {
            GamificationMetric(
                icon: "sparkles",
                value: "+\(estimate.estimatedXP)",
                label: "XP",
                isPrimary: true
            )
            .frame(maxWidth: .infinity)

            if let minutes = estimate.estimatedMinutes {
                metricDivider
                GamificationMetric(
                    icon: "clock",
                    value: "~\(minutes)",
                    label: "min"
                )
                .frame(maxWidth: .infinity)
            }

            if let streakText = estimate.streakMultiplierText {
                metricDivider
                GamificationMetric(
                    icon: "flame.fill",
                    value: streakText,
                    label: "Bonus",
                    iconTint: Color(hex: "#FF9F40")
                )
                .frame(maxWidth: .infinity)
            }

            if let creditText = estimate.estimatedCreditsText {
                metricDivider
                GamificationMetric(
                    icon: "circle.hexagongrid.fill",
                    value: creditText,
                    label: "Credit",
                    iconTint: AppTheme.Colors.elumiBlue
                )
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.Colors.setupCardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Colors.setupCardBorder, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    /// Dezenter vertikaler Trennstrich zwischen den Metriken.
    /// Nicht über die volle Höhe — trennt, ohne zu zerschneiden.
    private var metricDivider: some View {
        Rectangle()
            .fill(AppTheme.Colors.textSecondary.opacity(0.16))
            .frame(width: 1, height: 26)
    }
}

/// Einzelne Metrik in der Gamification-Bar. Icon + fetter Wert + kleines Label.
/// `isPrimary` → Wert in größerer Bold-Type (für den XP-Eintrag).
struct GamificationMetric: View {
    let icon: String
    let value: String
    let label: String
    var isPrimary: Bool = false
    var iconTint: Color = AppTheme.Colors.textSecondary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: isPrimary ? 13 : 11, weight: .semibold))
                .foregroundStyle(iconTint)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }

            Text(value)
                .font(.system(size: isPrimary ? 17 : 15, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()

            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .lineLimit(1)
    }
}

// MARK: - SessionPrimaryCTA
//
// Primary Session-Start-Button. Volle Breite, große Höhe, CTA-amber.
// **Einzige** Start-Aktion im Screen — keine sekundären Buttons hier.

struct SessionPrimaryCTA: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(isEnabled ? Color.black : AppTheme.Colors.textDisabled)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 58)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(isEnabled ? AppTheme.Colors.cta : AppTheme.Colors.textDisabled.opacity(0.3))
                )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
