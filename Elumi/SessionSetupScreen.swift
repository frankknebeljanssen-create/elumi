import SwiftUI

/// Generische Screen-Hülle für **alle** Session-Setup-Screens.
/// (Karteikarten, Quiz, Nomen, Artikel, Verben, Verbformen, Vokabeln.)
///
/// Die Ebenen — und ihre Reihenfolge — sind **verbindlich**:
///   1. `SessionSetupHeader`
///   2. Context-Slot (Standard: `SessionContextCard`; kann überschrieben
///      werden, z. B. wenn ein Modul mit `ListCategoryPickerView` arbeitet
///      oder einen eigenen Composer-Trigger braucht)
///   3. `SessionDirectionRow` — globale Lernrichtung, sichtbar und änderbar
///      (System-Wahrheit, identisch zu Home; pro Modul opt-out möglich
///      über `showsDirection: false`)
///   4. `optionsContent` (modul-spezifisch, per `@ViewBuilder` übergeben)
///   5. `SessionGamificationBar`
///   6. `SessionPrimaryCTA`
///
/// Zwei Initializer-Varianten:
///   • **Data-driven**: Modul liefert `SessionContextData` + `onEditContext`;
///     die Hülle rendert daraus eine `SessionContextCard`. Ideal wenn das
///     Modul eine simple Icon+Titel+Subtitle-Zusammenfassung will.
///   • **View-builder**: Modul liefert seinen eigenen Context-Header (z. B.
///     `ListCategoryPickerView` mit POS-Breakdown) via `@ViewBuilder`.
///     Konsistenz bleibt über Header/Spacing/CTA erhalten; modul-eigene
///     Reich-Infos bleiben erhalten.
struct SessionSetupScreen<ContextContent: View, OptionsContent: View>: View {
    let title: String
    let accent: Color
    let estimate: SessionEstimate
    let primaryButtonTitle: String
    /// Optionale Subline unter dem Start-Button. Default `nil` — klassisch
    /// single-line, so bleibt jede andere Setup-Hülle visuell unberührt.
    /// Genutzt vom Vokabel-Setup („Viel Erfolg beim Lernen!"), da dessen
    /// Gamification-Bar in die Speed-Round-Card integriert ist und der CTA
    /// dadurch optisch kürzer wirkt — die Subline gibt ihm Wärme zurück.
    var primarySubtitle: String? = nil
    var isPrimaryEnabled: Bool = true
    /// Sichtbarkeit der globalen Lernrichtung im Setup. Default `true` —
    /// der Nutzer kann in jedem Modul sehen und ändern, in welche
    /// Richtung gelernt wird. Für spezielle Screens, die den Schalter
    /// nicht anzeigen sollen, auf `false` setzen.
    var showsDirection: Bool = true
    /// Sichtbarkeit der Gamification-Bar über dem CTA. Default `true` —
    /// Karteikarten/Quiz/Training(Nomen/Artikel/Verben/Verbformen) zeigen
    /// die Bar weiterhin. Auf `false` setzen, wenn die Metriken woanders
    /// im Screen integriert sind (Vokabel-Setup: XP/Zeit/Credits stecken
    /// in der Speed-Round-Mode-Card, die zentrale Bar wäre redundant).
    var showsGamificationBar: Bool = true
    /// Optionaler Hint-Text, der **in** der Gamification-Bar statt der
    /// XP/Dauer-Zeile erscheint. Genutzt z. B. vom Verbformen-Setup,
    /// wenn aus der gewählten Liste keine Verben erkannt werden — der
    /// Hinweis landet dadurch **im** Preview-Card-Block (wo sonst die
    /// XP stehen), statt als lose Text-Zeile darüber.
    var gamificationBarHintText: String? = nil
    let onBack: () -> Void
    let onStart: () -> Void
    /// Optionales Modul-Icon (Phase 7.6+), rendert den Header als
    /// farbige `ModuleHeaderCard`. Kompatibel zu bestehenden Aufrufen —
    /// Default `nil` lässt alles beim Standard-Text-Header.
    var moduleIcon: HomeModuleIcon? = nil
    /// FR-DE-Richtungs-Toggle in der Back-Chevron-Row (Phase 7.6+).
    /// Wenn `true`, wird die dedizierte `SessionDirectionRow` im Body
    /// automatisch ausgeblendet — der Switch lebt dann oben rechts
    /// neben dem Back-Button.
    var showsDirectionToggle: Bool = false
    /// **Elumi-Hilfe (2026-08-05)** — Hilfe-Thema für den Knopf im
    /// Header. `nil` = kein Knopf.
    var helpTopic: ElumiHelpTopic? = nil
    @ViewBuilder let contextContent: () -> ContextContent
    @ViewBuilder let optionsContent: () -> OptionsContent

    // MARK: - Init (View-Builder-Variante, voll flexibel)

    init(
        title: String,
        accent: Color,
        estimate: SessionEstimate,
        primaryButtonTitle: String,
        primarySubtitle: String? = nil,
        isPrimaryEnabled: Bool = true,
        showsDirection: Bool = true,
        showsGamificationBar: Bool = true,
        moduleIcon: HomeModuleIcon? = nil,
        showsDirectionToggle: Bool = false,
        helpTopic: ElumiHelpTopic? = nil,
        gamificationBarHintText: String? = nil,
        onBack: @escaping () -> Void,
        onStart: @escaping () -> Void,
        @ViewBuilder contextContent: @escaping () -> ContextContent,
        @ViewBuilder optionsContent: @escaping () -> OptionsContent
    ) {
        self.title = title
        self.accent = accent
        self.estimate = estimate
        self.primaryButtonTitle = primaryButtonTitle
        self.primarySubtitle = primarySubtitle
        self.isPrimaryEnabled = isPrimaryEnabled
        // Toggle im Header → automatisch keine Direction-Row im Body
        // (sonst hätten wir zwei gleiche Switcher parallel).
        self.showsDirection = showsDirectionToggle ? false : showsDirection
        self.showsGamificationBar = showsGamificationBar
        self.moduleIcon = moduleIcon
        self.showsDirectionToggle = showsDirectionToggle
        self.helpTopic = helpTopic
        self.gamificationBarHintText = gamificationBarHintText
        self.onBack = onBack
        self.onStart = onStart
        self.contextContent = contextContent
        self.optionsContent = optionsContent
    }

    var body: some View {
        VStack(spacing: 0) {
            SessionSetupHeader(
                title: title,
                accent: accent,
                onBack: onBack,
                moduleIcon: moduleIcon,
                showsDirectionToggle: showsDirectionToggle,
                helpTopic: helpTopic
            )

            ScrollView(showsIndicators: false) {
                // Spacing = `sessionContextToDirectionSpacing` — verbindlich
                // für den Abstand **Ausgewählte Listen ↔ Richtung**. Ändern
                // der Konstante in `AppLayout` verschiebt den Abstand
                // systemweit auf allen Setup-Screens synchron.
                VStack(spacing: AppLayout.sessionContextToDirectionSpacing) {
                    contextContent()
                    if showsDirection {
                        SessionDirectionRow()
                    }
                    optionsContent()
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                // **Bottom-Inset-Migration 2026-05-09** — vorher
                // `padding(.bottom, 140)` als Manual-Workaround, weil
                // `.safeAreaInset(.bottom)` auf den OuterVStack
                // gehängt war und nicht zuverlässig zum ScrollView-
                // Content propagiert hat. Jetzt sitzt der Inset
                // direkt auf der ScrollView (siehe `.safeAreaInset`-
                // Modifier unten) — der Inset-Platz wird automatisch
                // im `contentInset.bottom` reserviert. Hier nur noch
                // ein kleiner Atemraum-Buffer am Content-Ende.
                .padding(.bottom, AppTheme.Spacing.lg)
            }
            // **Bottom-Inset-Migration 2026-05-09** — `.safeAreaInset(
            // edge: .bottom)` von OuterVStack auf ScrollView verschoben.
            //
            // **Bug vorher**: SwiftUI's `.safeAreaInset` auf einer
            // OuterVStack rendert das Inset visuell unten, aber der
            // resultierende safe-area-Reduce propagiert nicht zuverlässig
            // zur darin liegenden ScrollView. Die ScrollView füllt
            // weiterhin ihren VStack-Slot vollständig (contentInset.bottom
            // bleibt 0), und der GamBar/CTA-Block z-stackt visuell über
            // sichtbare Items am ScrollView-Bottom — User-Befund auf
            // Karteikarten-Setup: ANTWORTEN-MIT-Cards-Labels werden vom
            // GamBar-Oberkante verdeckt, EIGENE-STAPEL-Section wird vom
            // CTA überdeckt.
            //
            // **Bug jetzt**: Inset direkt auf der ScrollView → SwiftUI
            // erhöht den `contentInset.bottom` automatisch um die
            // Inset-Höhe, Content scrollt sauber **unter** dem Inset
            // vorbei statt von ihm verdeckt zu werden. Wirkt für ALLE
            // 7 Module die `SessionSetupScreen` nutzen (Karteikarten,
            // Quiz, Vokabeln, Nomen, Verben, Verbformen, Akzente).
            .safeAreaInset(edge: .bottom) {
                // Spacing Gamification-Bar ↔ CTA über zentrale Konstante —
                // alle Setup-Screens rendern mit demselben Rhythmus.
                VStack(spacing: AppLayout.gamificationBarToCTASpacing) {
                    // GamificationBar + CTA nutzen dasselbe Horizontal-Padding
                    // → garantiert identische Breite. Systemweite Konstante.
                    if showsGamificationBar {
                        SessionGamificationBar(estimate: estimate, hintText: gamificationBarHintText)
                            .padding(.horizontal, AppLayout.sessionCTAHorizontalPadding)
                    }

                    SessionPrimaryCTA(
                        title: primaryButtonTitle,
                        subtitle: primarySubtitle,
                        isEnabled: isPrimaryEnabled,
                        action: onStart
                    )
                    .padding(.horizontal, AppLayout.sessionCTAHorizontalPadding)
                    // Systemweites Bottom-Padding bis zum Footer — auf
                    // **jedem** Setup-Screen identisch (Vorlage: Karteikarten).
                    .padding(.bottom, AppLayout.sessionCTABottomClearance)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
    }
}

// MARK: - Convenience-Init (Data-driven, mit SessionContextCard)

extension SessionSetupScreen where ContextContent == SessionContextCard {
    /// Convenience: Modul liefert `SessionContextData` + `onEditContext`;
    /// die Hülle baut daraus eine Standard-`SessionContextCard`.
    init(
        title: String,
        context: SessionContextData,
        estimate: SessionEstimate,
        primaryButtonTitle: String,
        isPrimaryEnabled: Bool = true,
        showsDirection: Bool = true,
        moduleIcon: HomeModuleIcon? = nil,
        onBack: @escaping () -> Void,
        onEditContext: @escaping () -> Void,
        onStart: @escaping () -> Void,
        @ViewBuilder optionsContent: @escaping () -> OptionsContent
    ) {
        self.init(
            title: title,
            accent: context.accentColor,
            estimate: estimate,
            primaryButtonTitle: primaryButtonTitle,
            isPrimaryEnabled: isPrimaryEnabled,
            showsDirection: showsDirection,
            moduleIcon: moduleIcon,
            onBack: onBack,
            onStart: onStart,
            contextContent: { SessionContextCard(data: context, onEditTapped: onEditContext) },
            optionsContent: optionsContent
        )
    }
}
