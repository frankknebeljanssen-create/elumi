import SwiftUI

/// Generische Screen-Hülle für **alle** Session-Setup-Screens.
/// (Karteikarten, Quiz, Nomen, Artikel, Verben, Verbformen, Vokabeln.)
///
/// Die Ebenen — und ihre Reihenfolge — sind **verbindlich**:
///   1. `SessionSetupHeader`
///   2. `SessionContextCard`
///   3. `optionsContent` (modul-spezifisch, per `@ViewBuilder` übergeben)
///   4. `SessionGamificationBar`
///   5. `SessionPrimaryCTA`
///
/// Jedes Modul liefert nur noch:
///   • Titel, Context-Daten, Estimate, CTA-Label
///   • seine Options-Inhalte (z. B. `OptionChipGrid` + `CountSliderCard`)
/// und bekommt dafür automatisch die gemeinsame Struktur, Abstände,
/// Typografie und Gamification-Preview.
struct SessionSetupScreen<OptionsContent: View>: View {
    let title: String
    let context: SessionContextData
    let estimate: SessionEstimate
    let primaryButtonTitle: String
    var isPrimaryEnabled: Bool = true
    let onBack: () -> Void
    let onEditContext: () -> Void
    let onStart: () -> Void
    @ViewBuilder let optionsContent: () -> OptionsContent

    var body: some View {
        VStack(spacing: 0) {
            SessionSetupHeader(title: title, accent: context.accentColor, onBack: onBack)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 24) {
                    SessionContextCard(data: context, onEditTapped: onEditContext)

                    optionsContent()
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 140) // Platz für den safeAreaInset-CTA
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                SessionGamificationBar(estimate: estimate)
                    .padding(.horizontal, 16)

                SessionPrimaryCTA(
                    title: primaryButtonTitle,
                    isEnabled: isPrimaryEnabled,
                    action: onStart
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + 4)
            }
        }
    }
}
