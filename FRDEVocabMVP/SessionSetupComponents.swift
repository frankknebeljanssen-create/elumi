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
    /// Optionales Modul-Icon (Phase 7.6+). Wenn gesetzt, rendert der
    /// Header eine farbige `ModuleHeaderCard` (wie die Home-Cards) und
    /// den Back-Button darüber — visuelle Klammer Home → Modul.
    /// Ohne Icon bleibt der klassische zentrierte Text-Header erhalten
    /// (z.\u{00A0}B. für Screens ohne Home-Pendant).
    let moduleIcon: HomeModuleIcon?
    /// FR-DE-Richtungs-Toggle rechts neben dem Back-Button — spart die
    /// dedizierte Direction-Row im Body.
    let showsDirectionToggle: Bool

    init(
        title: String,
        accent: Color = AppTheme.Colors.primary,
        onBack: @escaping () -> Void,
        moduleIcon: HomeModuleIcon? = nil,
        showsDirectionToggle: Bool = false
    ) {
        self.title = title
        self.accent = accent
        self.onBack = onBack
        self.moduleIcon = moduleIcon
        self.showsDirectionToggle = showsDirectionToggle
    }

    var body: some View {
        VStack(spacing: 0) {
            if let moduleIcon {
                // Modul-Header-Card — farbige Identitäts-Card rendert
                // Back-Chevron + Icon-Card selbst (zentrales Muster
                // aus `ModuleHeaderCard`). Der Setup-Header reicht
                // `onBack` + optionalen FR-DE-Toggle durch.
                ModuleHeaderCard(
                    icon: moduleIcon,
                    title: title,
                    accent: accent,
                    onBack: onBack,
                    showsDirectionToggle: showsDirectionToggle
                )
            } else {
                // Fallback: klassischer ZStack mit zentriertem Text-
                // Header + Back-Chevron links (für Screens ohne Home-
                // Pendant bzw. ohne Modul-Icon).
                ZStack {
                    Text(title)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    HStack {
                        AppBackButton(action: onBack, tint: accent)
                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        // **Chevron-Y-Sweep 2026-05-07** — Top-Padding auf
        // `headerChevronTopPadding` (= 0) umgezogen, damit der
        // Setup-Chevron auf identischer y-Position wie der
        // TrainingHub-Master sitzt. Vorher fest 4 pt → Setup-Chevron
        // saß 4 pt unter TrainingHub-Chevron.
        .padding(.top, AppLayout.headerChevronTopPadding)
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
            // **Naming-Sweep 2026-05-06** — „AUSGEWÄHLTE LISTEN"
            // → „DEINE LISTEN" (persönlicher, kürzer).
            Text("DEINE LISTEN")
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
                    // `frame(maxHeight: .infinity)` stellt sicher, dass
                    // das Pill exakt vertikal in der HStack-Höhe zentriert
                    // sitzt, auch wenn die Content-VStack mehrzeilig ist
                    // (Titel + Subtitle + optional Detail). HStack-Center-
                    // Alignment allein reichte bei asymmetrischen
                    // Paddings nicht.
                    Image(systemName: "pencil")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(data.accentColor)
                        .frame(width: 40, height: 40)
                        .background(
                            Circle().fill(data.accentColor.opacity(0.14))
                        )
                        .frame(maxHeight: .infinity)
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
// Systemweite Preview-Zeile über dem CTA — **neue Reduzierung** (V2):
// nur noch **XP + Dauer**, keine Credits, keine Streak-Multiplier, keine
// Sparkle-Icons mehr. Diese Werte gehören in andere Kontexte:
//
//    Kontext         Inhalt
//    ──────────────  ────────────────
//    Setup Screen    XP + Dauer        ← diese Bar
//    Session-Ende    XP + Reward       (Summary/Reward-Screen)
//    Game Screen     Credits           (Arcade-Hub / Reward-Panel)
//
// Visuell: klar abgehobene Card auf `setupCardBackground`, großzügige
// Innenabstände, exakt vertikal zentrierte Inhalte. Ein Bullet-Separator
// zwischen XP und Dauer — kein Divider, keine Icons pro Wert.
//
// API stabil: `init(estimate:)` bleibt, Call-Sites müssen nichts ändern.
// Nicht genutzte Felder des `SessionEstimate` werden schlicht ignoriert.

struct SessionGamificationBar: View {
    let estimate: SessionEstimate
    /// Optionaler Hinweis-Text. Wenn gesetzt, rendert die Bar **statt**
    /// der XP/Dauer-Zeile diesen Hinweis in Secondary-Farbe. Genutzt
    /// z. B. im Verbformen-Setup: wenn aus der gewählten Liste keine
    /// Verben erkannt werden, soll der „keine Verben erkannt"-Text
    /// **in** der Bar landen (statt als lose Text-Zeile darüber), und
    /// die XP-Zahl (0) verschwindet dabei.
    var hintText: String? = nil

    var body: some View {
        // Inhalt zentriert in der Bar — kein `maxHeight: .infinity` auf
        // den Kindern (würde die Bar vertikal ins Unendliche ausdehnen).
        // `HStack(alignment: .center)` zentriert die drei gleich großen
        // Texte bereits sauber gegeneinander.
        Group {
            if let hintText, !hintText.isEmpty {
                // Hint-Modus: statt XP/Dauer → zentrierter Hinweis in
                // Secondary-Farbe, gleiche Typo wie der CTA darunter.
                Text(hintText)
                    .font(AppTheme.Typography.button)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    // Font identisch zum CTA „Los geht's!" darunter:
                    // `AppTheme.Typography.button` = 17 pt, bold, rounded.
                    // Alle drei Texte (XP, Bullet, Minuten) teilen dieselbe
                    // Typo — Weiß für XP (Hauptwert), Secondary-Farbe für
                    // Bullet und Minuten (dezenter, aber gleich groß/bold).
                    Text("+\(estimate.estimatedXP) XP")
                        .font(AppTheme.Typography.button)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .monospacedDigit()

                    if let minutes = estimate.estimatedMinutes {
                        Text("·")
                            .font(AppTheme.Typography.button)
                            .foregroundStyle(AppTheme.Colors.textSecondary)

                        Text("~\(minutes) min")
                            .font(AppTheme.Typography.button)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        // Corner-Radius jetzt **identisch** zum CTA darunter
        // (`AppLayout.sessionCTARadius`). Bar + CTA lesen sich dadurch
        // als zusammenhängendes Card-Duo.
        .background(
            RoundedRectangle(cornerRadius: AppLayout.sessionCTARadius, style: .continuous)
                // setupCardBackground + leichte weiße Aufhellung —
                // die Bar hebt sich dadurch spürbar vom dunklen
                // Screen-Background ab, ohne die bestehende Farbfamilie
                // zu verlassen.
                .fill(AppTheme.Colors.setupCardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: AppLayout.sessionCTARadius, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppLayout.sessionCTARadius, style: .continuous)
                .stroke(AppTheme.Colors.setupCardBorder, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.28), radius: 7, x: 0, y: 3)
        // Fix-Size vertikal — die Bar bleibt exakt so hoch wie ihr Inhalt
        // + Padding. Verhindert unbegrenztes Ausdehnen in flex-Containern.
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(estimate.estimatedXP) XP, etwa \(estimate.estimatedMinutes ?? 0) Minuten")
    }
}

// MARK: - SessionPrimaryCTA
//
// Primary Session-Start-Button. Volle Breite, große Höhe, CTA-amber.
// **Einzige** Start-Aktion im Screen — keine sekundären Buttons hier.

struct SessionPrimaryCTA: View {
    let title: String
    /// Optionale Subline unter dem Haupttitel. Wird genutzt für
    /// kontextualisierte Setup-Screens (z. B. Vokabeln-Setup zeigt
    /// „Viel Erfolg beim Lernen!" als freundliche Motiv-Zeile). `nil` =
    /// klassischer Single-Line-CTA (Default, ändert nichts an der
    /// bestehenden Optik für alle anderen Setup-Screens).
    var subtitle: String? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(isEnabled ? Color.black : AppTheme.Colors.textDisabled)

                if let subtitle, !subtitle.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .bold))
                        Text(subtitle)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .foregroundStyle(isEnabled ? Color.black.opacity(0.62) : AppTheme.Colors.textDisabled)
                }
            }
            .frame(maxWidth: .infinity)
            // minHeight: 58 → **53** pt (−5 pt global, User-Request „CTA
            // Los geht's / Quiz starten usw — überall 5p weniger Höhe,
            // Größe nicht Position"). Gilt für **alle** Session-Setup-
            // Screens (Karteikarten, Quiz, Training/Vokabeln/Nomen/
            // Artikel/Verben/Verbformen) — der CTA wird system-weit
            // kompakter, ohne dass Titel-Font oder Corner-Radius
            // angetastet werden. Mit Subline wächst der Button weiterhin
            // organisch durch den VStack-Content (+ das Subtitle-Padding).
            .frame(minHeight: 53)
            .padding(.vertical, subtitle == nil ? 0 : 6)
            // Systemweite Corner-Radius — identisch zu den Cards
            // darüber (GamificationBar, Progress-Board, Fokus-Card).
            .background(
                RoundedRectangle(cornerRadius: AppLayout.sessionCTARadius, style: .continuous)
                    .fill(isEnabled ? AppTheme.Colors.cta : AppTheme.Colors.textDisabled.opacity(0.3))
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
