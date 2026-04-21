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
                showsDirectionToggle: showsDirectionToggle
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
                .padding(.bottom, 140) // Platz für den safeAreaInset-CTA
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            // Spacing Gamification-Bar ↔ CTA über zentrale Konstante —
            // alle Setup-Screens rendern mit demselben Rhythmus.
            VStack(spacing: AppLayout.gamificationBarToCTASpacing) {
                // GamificationBar + CTA nutzen dasselbe Horizontal-Padding
                // → garantiert identische Breite. Systemweite Konstante.
                if showsGamificationBar {
                    SessionGamificationBar(estimate: estimate)
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
