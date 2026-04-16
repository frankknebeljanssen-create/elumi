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
    var isPrimaryEnabled: Bool = true
    /// Sichtbarkeit der globalen Lernrichtung im Setup. Default `true` —
    /// der Nutzer kann in jedem Modul sehen und ändern, in welche
    /// Richtung gelernt wird. Für spezielle Screens, die den Schalter
    /// nicht anzeigen sollen, auf `false` setzen.
    var showsDirection: Bool = true
    let onBack: () -> Void
    let onStart: () -> Void
    @ViewBuilder let contextContent: () -> ContextContent
    @ViewBuilder let optionsContent: () -> OptionsContent

    // MARK: - Init (View-Builder-Variante, voll flexibel)

    init(
        title: String,
        accent: Color,
        estimate: SessionEstimate,
        primaryButtonTitle: String,
        isPrimaryEnabled: Bool = true,
        showsDirection: Bool = true,
        onBack: @escaping () -> Void,
        onStart: @escaping () -> Void,
        @ViewBuilder contextContent: @escaping () -> ContextContent,
        @ViewBuilder optionsContent: @escaping () -> OptionsContent
    ) {
        self.title = title
        self.accent = accent
        self.estimate = estimate
        self.primaryButtonTitle = primaryButtonTitle
        self.isPrimaryEnabled = isPrimaryEnabled
        self.showsDirection = showsDirection
        self.onBack = onBack
        self.onStart = onStart
        self.contextContent = contextContent
        self.optionsContent = optionsContent
    }

    var body: some View {
        VStack(spacing: 0) {
            SessionSetupHeader(title: title, accent: accent, onBack: onBack)

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
            VStack(spacing: 14) {
                // GamificationBar + CTA nutzen dasselbe Horizontal-Padding
                // → garantiert identische Breite. Systemweite Konstante.
                SessionGamificationBar(estimate: estimate)
                    .padding(.horizontal, AppLayout.sessionCTAHorizontalPadding)

                SessionPrimaryCTA(
                    title: primaryButtonTitle,
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
            onBack: onBack,
            onStart: onStart,
            contextContent: { SessionContextCard(data: context, onEditTapped: onEditContext) },
            optionsContent: optionsContent
        )
    }
}
