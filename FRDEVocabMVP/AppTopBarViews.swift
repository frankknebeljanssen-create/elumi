import SwiftUI

/// **ModuleHeaderCard** (Phase 7.6+): farbige Modul-Identitäts-Card,
/// die direkt nach dem `AppTopBar` oben im Body jedes Modul-Screens
/// sitzt. Zeigt das Modul-Icon (Home-Style Cartoon-SVG) links und
/// den Modul-Namen rechts — **exakt die visuelle Anmutung**, die
/// der User von seiner Home-Card kennt.
///
/// Damit entsteht eine geschlossene visuelle Klammer Home → Modul:
/// tappt der User z.\u{00A0}B. auf die blaue „Karteikarten"-Card,
/// landet er auf einem Screen, dessen erste Card genau dieselbe
/// blaue Identität mit demselben Icon trägt.
///
/// Design-Regeln:
///   • Volle Screen-Card-Breite (matched `AppLayout.screenPadding`
///     am Call-Site — diese Card setzt kein eigenes horizontales Inset).
///   • Gleicher Gradient-Look wie die Hero-Cards auf Home
///     (`accent.opacity(0.95) → 0.75`, `topLeading → bottomTrailing`).
///   • Höhe mind. ~78 pt — genug Platz, dass ein 64-pt-Icon
///     ca. 2 Zeilen hoch reicht; Title-Font dick + weiß mit
///     dezentem Drop-Shadow, gleiche Lesbarkeit wie Home-Hero.
struct ModuleHeaderCard: View {
    /// Entweder ein `HomeModuleIcon` (Standard — eigene SVG-Assets) oder
    /// ein SF-Symbol-Fallback für Screens ohne dediziertes Modul-Asset
    /// (z. B. Spielen/Arcade → `gamecontroller.fill`, Fortschritt →
    /// `trophy.fill`). **Genau einer** der beiden Werte muss gesetzt
    /// sein — der Convenience-Init erzwingt das über separate Signatures.
    let icon: HomeModuleIcon?
    let iconSystemImage: String?
    /// **Custom-View-Icon-Slot (2026-05-07)** — für Screens die weder
    /// ein `HomeModuleIcon` noch ein SF-Symbol nutzen wollen, sondern
    /// einen eigenen View (z. B. `DailyDropStackedCardsIcon` für den
    /// Slot-Screen-Header). Type-Erasure via `AnyView`, damit der
    /// Struct nicht generisch werden muss (würde alle Call-Sites
    /// brechen). Render-Priorität in `coloredCard`:
    /// `customIcon` → `icon` → `iconSystemImage`.
    let customIcon: AnyView?
    let title: String
    let accent: Color
    /// Optionaler Back-Chevron (Phase 7.6+). Wenn gesetzt, sitzt der
    /// `AppBackButton` **oberhalb** der farbigen Card — identisches
    /// Muster wie auf **allen** anderen Screens der App (Back-Row,
    /// darunter Haupt-Content). Kein Overlay mehr auf der Card, kein
    /// geteiltes Layout pro Aufrufer.
    var onBack: (() -> Void)? = nil
    /// **FR-DE-Toggle** in der Back-Chevron-Row (Phase 7.6+). Wenn
    /// `true`, rendert rechts vom Back-Button ein kompakter
    /// `LanguageDirectionSwitch` — spart Platz im Setup-Body, wo
    /// früher die dedizierte Direction-Row saß. Nutzt die `.compact`-
    /// Size des Switches, wird vertikal mit dem Back-Button
    /// zentriert.
    var showsDirectionToggle: Bool = false
    /// **Elumi-Hilfe (2026-08-05)** — wenn gesetzt, sitzt rechts in der
    /// Back-Row das Elumi-Abzeichen mit Fragezeichen und öffnet die
    /// kontextbezogene Hilfe.
    ///
    /// **Warum hier und nicht in `AppTopBar`:** `AppTopBar` wird gar
    /// nicht gerendert. Der `topBar`-Parameter von `appLocalChrome`
    /// (`AppChromeSupport.swift`) wird in keinem Zweig aufgerufen, alle
    /// 23 Aufrufe laufen ins Leere — deshalb war oben rechts auf
    /// Training und Karteikarten nichts zu sehen (User-Report
    /// 2026-08-05). Diese Card hier ist der Header, den die Modul-
    /// Screens tatsächlich zeichnen.
    var onHelp: (() -> Void)? = nil
    /// **Compact-Mode (2026-05-07)** — verkleinert Icon-Frame (64 → 48),
    /// Title-Font (24 → 20 pt) und Vertical-Padding (12 → 8 pt) für
    /// Screens die Header-Card-Höhe sparen müssen (z. B. Slot-Screen,
    /// wo der CTA sonst vom Footer verdeckt wird). Default `false` —
    /// alle bestehenden Call-Sites unverändert.
    var compact: Bool = false

    // MARK: - Inits
    //
    // Zwei getrennte Inits, damit der Aufrufer **einen** Icon-Pfad wählt
    // und das Modell keine Ambiguität trägt. Die bestehenden Call-Sites
    // (Flashcards, Quiz, Training, Scan, Lists, Accents) nutzen weiterhin
    // den Standard-Init mit `HomeModuleIcon` — kein Breakage.

    init(
        icon: HomeModuleIcon,
        title: String,
        accent: Color,
        onBack: (() -> Void)? = nil,
        showsDirectionToggle: Bool = false,
        onHelp: (() -> Void)? = nil,
        compact: Bool = false
    ) {
        self.icon = icon
        self.iconSystemImage = nil
        self.customIcon = nil
        self.title = title
        self.accent = accent
        self.onBack = onBack
        self.showsDirectionToggle = showsDirectionToggle
        self.onHelp = onHelp
        self.compact = compact
    }

    init(
        systemImage: String,
        title: String,
        accent: Color,
        onBack: (() -> Void)? = nil,
        showsDirectionToggle: Bool = false,
        onHelp: (() -> Void)? = nil,
        compact: Bool = false
    ) {
        self.icon = nil
        self.iconSystemImage = systemImage
        self.customIcon = nil
        self.title = title
        self.accent = accent
        self.onBack = onBack
        self.showsDirectionToggle = showsDirectionToggle
        self.onHelp = onHelp
        self.compact = compact
    }

    /// **Custom-Icon-Init (2026-05-07)** — für arbiträre Icon-Views
    /// wie `DailyDropStackedCardsIcon` auf dem Slot-Screen-Header.
    /// Aufrufer übergibt einen View (z. B. `DailyDropStackedCardsIcon(...)`),
    /// der intern in `AnyView` gewrapped wird (Type-Erasure für
    /// non-generic Struct).
    init<Icon: View>(
        customIcon: Icon,
        title: String,
        accent: Color,
        onBack: (() -> Void)? = nil,
        showsDirectionToggle: Bool = false,
        onHelp: (() -> Void)? = nil,
        compact: Bool = false
    ) {
        self.icon = nil
        self.iconSystemImage = nil
        self.customIcon = AnyView(customIcon)
        self.title = title
        self.accent = accent
        self.onBack = onBack
        self.showsDirectionToggle = showsDirectionToggle
        self.onHelp = onHelp
        self.compact = compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // **2026-08-05** — vorher zwei getrennte Zweige (mit Back /
            // ohne Back aber mit Toggle). Mit dem Hilfe-Abzeichen als
            // drittem möglichen Element wären das vier Kombinationen
            // gewesen; eine Zeile, die alle drei Slots optional füllt,
            // bleibt lesbar und verhält sich in allen Fällen gleich.
            if onBack != nil || showsDirectionToggle || onHelp != nil {
                HStack(alignment: .center, spacing: 8) {
                    if let onBack {
                        AppBackButton(action: onBack, tint: accent)
                    }
                    Spacer(minLength: 0)
                    if showsDirectionToggle {
                        LanguageDirectionSwitch(size: .compact)
                    }
                    if let onHelp {
                        ElumiHelpBadge(action: onHelp)
                    }
                }
            }
            coloredCard
        }
    }

    /// Die eigentliche farbige Identitäts-Card (Icon + Title) — ohne
    /// Back-Logik. Privates Sub-View, damit der Body lesbar bleibt
    /// und der Back-Chevron immer oberhalb sitzt.
    private var coloredCard: some View {
        // **Compact-Mode (2026-05-07)** — Icon 64 → 48, Title 24 → 20,
        // Vertical-Padding 12 → 8. Spart ~20 pt Card-Höhe für Screens
        // die mehr Content-Platz brauchen (z. B. Slot-Screen).
        let iconFrame: CGFloat = compact ? 48 : 64
        let titleSize: CGFloat = compact ? 20 : 24
        let verticalPad: CGFloat = compact ? 8 : 12
        return HStack(spacing: 14) {
            Group {
                if let customIcon {
                    customIcon
                } else if let icon {
                    HomeModuleIconView(icon: icon, size: iconFrame)
                } else if let iconSystemImage {
                    Image(systemName: iconSystemImage)
                        .font(.system(size: compact ? 28 : 36, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                }
            }
            .frame(width: iconFrame, height: iconFrame)
            Text(title)
                .font(.system(size: titleSize, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 1, x: 0, y: 1)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, verticalPad)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            accent.opacity(0.95),
                            accent.opacity(0.75)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .shadow(color: .black.opacity(0.20), radius: 5, x: 0, y: 3)
    }
}

struct ScreenHeaderCard: View {
    let style: AppSectionStyle
    let title: String
    let subtitle: String
    /// Optionales SF-Symbol für den Icon-Kreis rechts. Wenn `nil`, wird
    /// kein Icon-Kreis gezeichnet — der Header bekommt dann das klassische
    /// Navigation-Bar-Layout (Back links, Titel zentriert, rechts leer).
    let systemImage: String?
    var actionTitle: String? = nil
    var actionSystemImage: String = "house.fill"
    var action: (() -> Void)? = nil
    var secondaryActionTitle: String? = nil
    var secondaryActionSystemImage: String = "gearshape.fill"
    var secondaryAction: (() -> Void)? = nil
    /// Optionaler Back-Closure. Wenn gesetzt, erscheint links ein
    /// dezenter „< "-Button im gleichen Stil wie der Session-Setup-
    /// Header und der (unter globalChrome unsichtbare) `AppTopBar`.
    /// So wird die Zurück-Navigation bei „normalen" Screens (Listen,
    /// Lexikon, Info, Settings) sichtbar und konsistent — unabhängig
    /// davon, ob das globale Chrome aktiv ist.
    var onBack: (() -> Void)? = nil
    /// Wenn `true`, wird der Titel in der Mitte gesetzt (klassischer
    /// Nav-Bar-Look). Rechts wird bei fehlendem Icon ein unsichtbarer
    /// 34×34-Platzhalter gezeichnet, damit der Titel exakt mittig sitzt.
    var centeredTitle: Bool = false
    /// Optionales **Modul-Icon** (Home-Style, kartoon-SVG), das zwischen
    /// Back-Button und Titel sitzt. Wenn gesetzt, bekommt der Screen
    /// die gleiche Icon-Identität wie seine zugehörige Home-Card —
    /// konsistenter Übergang Home → Modul (Phase 7.6+ „Farb-System").
    /// Asset selbst bringt seine Farbe mit; wir zeichnen es in einer
    /// quadratischen 30×30-Bounding-Box.
    var leadingModuleIcon: HomeModuleIcon? = nil
    /// **2026-08-05** — Für längere Screen-Titel, die bei `lineLimit(1)`
    /// mit „…" abgeschnitten würden (App-Regel: **nirgends** wird Text
    /// per Ellipsis gekürzt). Bei `true` darf der Titel auf eine zweite
    /// Zeile umbrechen statt zu verkürzen. Default `false` — alle
    /// bestehenden Call-Sites mit kurzen Titeln bleiben unverändert.
    var allowsMultilineTitle: Bool = false
    /// **Elumi-Hilfe (2026-08-05)** — Hilfe-Abzeichen im Trailing-Slot.
    /// Hat Vorrang vor `systemImage`: ein Screen, der beides setzt, will
    /// den Hilfe-Einstieg, das dekorative Icon ist verzichtbar. Der
    /// 44-pt-Platzhalter für zentrierte Titel entfällt dann automatisch,
    /// weil das Abzeichen selbst dieselbe Mindestbreite hat.
    var onHelp: (() -> Void)? = nil

    private var titleParts: [String] {
        subtitle.isEmpty ? [title] : [title, subtitle]
    }

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            leadingSlot

            if centeredTitle {
                Spacer(minLength: 0)
            }

            VStack(alignment: centeredTitle ? .center : .leading, spacing: subtitle.isEmpty ? 0 : 4) {
                Text(title)
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(allowsMultilineTitle ? 2 : 1)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(centeredTitle ? .center : .leading)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .multilineTextAlignment(centeredTitle ? .center : .leading)
                }
            }

            if centeredTitle {
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: AppTheme.Spacing.sm)
            }

            trailingSlot
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: AppLayout.headerHeight)
        // Systemweites Padding unter dem Header — gleicher Abstand zum
        // nächsten Content-Block auf **jedem** Screen.
        .padding(.bottom, AppLayout.screenHeaderBottomPadding)
    }

    // MARK: - Slots

    @ViewBuilder
    private var leadingSlot: some View {
        HStack(spacing: 6) {
            if let onBack {
                // Systemweiter Back-Button — nackter Pfeil, kein Rahmen.
                // **Bug-Fix 2026-05-07** — expliziter Brand-Pink-Tint
                // statt Default (`textPrimary`). Konsistent zu allen
                // anderen Push-Screens, kein farbloser Default-Look.
                AppBackButton(action: onBack, tint: AppTheme.Colors.elumiPink)
            } else if centeredTitle {
                // Symmetric placeholder, damit der Titel bei fehlendem
                // Back-Button trotzdem sauber mittig sitzt. 44 pt = Breite
                // des AppBackButton-Touch-Targets.
                Color.clear.frame(width: 44, height: 44)
            }

            // Modul-Icon (Phase 7.6+): wenn gesetzt, sitzt es direkt
            // neben dem Back-Button — identische Optik wie auf der
            // Home-Card, damit der Übergang Home → Modul visuell
            // geschlossen wirkt. Size 38 pt, damit das Cartoon-Icon
            // klar lesbar neben dem 44-pt-Back-Target sitzt.
            if let moduleIcon = leadingModuleIcon {
                HomeModuleIconView(icon: moduleIcon, size: 38)
            }
        }
    }

    @ViewBuilder
    private var trailingSlot: some View {
        if let onHelp {
            ElumiHelpBadge(action: onHelp, size: 32)
        } else if let systemImage {
            ZStack {
                Circle()
                    .fill(style.accent.opacity(0.12))
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(style.accent)
            }
            .frame(width: 34, height: 34)
        } else if centeredTitle {
            // Ohne Trailing-Icon braucht der zentrierte Titel rechts
            // einen Platzhalter von 44×44 — exakt die Breite des
            // Back-Buttons links, damit der Text wirklich mittig sitzt.
            Color.clear.frame(width: 44, height: 44)
        }
    }
}

struct AppTopBar: View {
    @Environment(\.appOpenAccountAction) private var globalOpenAccountAction
    @ObservedObject private var profileStore = ProfileStore.shared
    @AppStorage(appDirectionKey) private var selectedDirectionRaw = Direction.frenchToGerman.rawValue
    var onBack: (() -> Void)? = nil
    var onInfo: (() -> Void)? = nil
    var onAccount: (() -> Void)? = nil
    /// Optionales **Modul-Icon**, sitzt direkt neben dem Back-Button
    /// (Phase 7.6+). Dieselbe Komponente wie im `ScreenHeaderCard` —
    /// Modul-Screens, die direkt `AppTopBar` nutzen (Flashcards, Quiz,
    /// Scan), bekommen damit konsistent die gleiche Modul-Identität.
    var leadingModuleIcon: HomeModuleIcon? = nil

    private var selectedDirection: Direction {
        (Direction(rawValue: selectedDirectionRaw) ?? .frenchToGerman).sanitizedForFrenchOnly
    }

    private var resolvedAccountAction: (() -> Void)? {
        onAccount ?? globalOpenAccountAction
    }

    private func sourceCountryCode(for direction: Direction) -> String {
        switch direction {
        case .frenchToGerman:
            return "FR"
        case .germanToFrench:
            return "DE"
        case .englishToGerman:
            return "GB"
        case .germanToEnglish:
            return "DE"
        }
    }

    private func targetCountryCode(for direction: Direction) -> String {
        switch direction {
        case .frenchToGerman:
            return "DE"
        case .germanToFrench:
            return "FR"
        case .englishToGerman:
            return "DE"
        case .germanToEnglish:
            return "GB"
        }
    }

    var body: some View {
        HStack {
            if let onBack {
                // Systemweiter Back-Button — kein Rahmen mehr, einheitlich
                // mit allen anderen Screens und Headern.
                // **Bug-Fix 2026-05-07** — expliziter Brand-Pink-Tint
                // statt Default (`textPrimary`).
                AppBackButton(action: onBack, tint: AppTheme.Colors.elumiPink)
            }

            // Modul-Icon, sitzt direkt neben dem Back-Button.
            // Dieselbe Größe (38 pt) wie im `ScreenHeaderCard`, damit
            // Screens, die entweder direkt `AppTopBar` oder über
            // `ScreenHeaderCard` gerendert werden, identisch wirken.
            if let leadingModuleIcon {
                HomeModuleIconView(icon: leadingModuleIcon, size: 38)
                    .padding(.leading, 2)
            }

            Spacer(minLength: 0)

            Menu {
                ForEach(Direction.frenchOnlyCases) { direction in
                    Button {
                        selectedDirectionRaw = direction.rawValue
                    } label: {
                        Text("\(direction.sourceFlag) → \(direction.targetFlag)  \(direction.compactLabel)")
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    StraightFlagBadge(countryCode: sourceCountryCode(for: selectedDirection))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    StraightFlagBadge(countryCode: targetCountryCode(for: selectedDirection))
                }
                .frame(minWidth: 62, minHeight: 30)
                .padding(.horizontal, 8)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .background(AppTheme.Colors.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                .accessibilityLabel(Text(selectedDirection.compactLabel))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 10)
                .frame(width: 10)

            if let onInfo {
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16, weight: .bold))
                        .frame(width: 30, height: 30)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .background(AppTheme.Colors.secondarySurface)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                        .accessibilityLabel(Text("Info"))
                }
                .buttonStyle(.plain)

                Spacer(minLength: 10)
                    .frame(width: 10)
            }

            if let resolvedAccountAction {
                // Profil-Zugang: runder Avatar-Badge statt neutralem Icon.
                // Zeigt Initialen, sobald ein Name gesetzt ist — sonst
                // Personen-Icon. Sichtbar-aber-dezent, matcht Top-Bar-Look.
                Button(action: resolvedAccountAction) {
                    ProfileAvatarBadge(store: profileStore, size: 30)
                }
                .buttonStyle(.plain)
            }
        }
        .modifier(AppTopBarSurfaceModifier())
    }
}

struct StraightFlagBadge: View {
    let countryCode: String
    var width: CGFloat = 18
    var height: CGFloat = 12
    var labelFontSize: CGFloat = 8

    private var cornerRadius: CGFloat {
        max(3, height * 0.25)
    }

    var body: some View {
        ZStack {
            switch countryCode {
            case "FR":
                HStack(spacing: 0) {
                    Color(red: 0.02, green: 0.22, blue: 0.67)
                    Color.white
                    Color(red: 0.88, green: 0.16, blue: 0.22)
                }
            case "DE":
                VStack(spacing: 0) {
                    Color.black
                    Color(red: 0.78, green: 0.0, blue: 0.07)
                    Color(red: 1.0, green: 0.81, blue: 0.0)
                }
            case "GB":
                ZStack {
                    Color(red: 0.05, green: 0.16, blue: 0.45)
                    Text("GB")
                        .font(.system(size: labelFontSize, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
            default:
                ZStack {
                    AppTheme.Colors.secondarySurface
                    Text(countryCode)
                        .font(.system(size: labelFontSize, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.black.opacity(0.08), lineWidth: 0.8)
        )
        .shadow(color: .black.opacity(0.05), radius: 1.5, x: 0, y: 1)
        .accessibilityHidden(true)
    }
}
