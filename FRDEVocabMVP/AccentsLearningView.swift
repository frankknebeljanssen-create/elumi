import SwiftUI

/// Lernen-Modus: ein sanfter Einstieg in die vier MVP-Akzente.
///
/// Bewusst pure Info-Ansicht — keine Übungen mehr im Intro. Der User
/// swiped / scrollt durch die Akzenttypen (é, è, ê, ç), tippt unten
/// auf „Jetzt üben" und **erst dann** startet die eigentliche Übung.
struct AccentsLearningView: View {
    let cards: [AccentContentBuilder.LearningCard]
    let accentColor: Color
    let onClose: () -> Void
    /// Direkt in eine Üben-Session springen.
    let onStartPractice: () -> Void
    /// System-Chrome-Requisiten für den AppBottomBar.
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let onHome: () -> Void
    let onSettings: () -> Void

    @State private var pageIndex: Int = 0

    var body: some View {
        ZStack {
            AppTheme.Colors.background.ignoresSafeArea()

            VStack(spacing: 0) {
                sessionHeader

                if cards.isEmpty {
                    emptyState
                } else {
                    TabView(selection: $pageIndex) {
                        ForEach(Array(cards.enumerated()), id: \.offset) { idx, card in
                            cardView(card: card)
                                .tag(idx)
                                .padding(.horizontal, AppLayout.screenPadding)
                                .padding(.vertical, AppTheme.Spacing.sm)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                    .frame(maxHeight: .infinity)
                }

                footer

                // Systemkonformer Bottom-Bar — immer sichtbar.
                AppBottomBar(
                    feedbackPlayer: feedbackPlayer,
                    onHome: onHome,
                    onFavorite: nil,
                    onScan: nil,
                    onSettings: onSettings
                )
            }
        }
    }

    // MARK: - Header (systemkonform: AppBackButton + „Akzente" mittig)

    private var sessionHeader: some View {
        AccentsSessionHeader(onBack: onClose, trailing: nil)
    }

    // MARK: - Card

    /// Lernen-Karte — pure Info-Ansicht (Glyph + Titel + Beispielwörter).
    /// Keine Mini-Übung mehr — der User scrollt ruhig durch, die echte
    /// Übung startet erst bei Tap auf „Jetzt üben".
    private func cardView(card: AccentContentBuilder.LearningCard) -> some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            Spacer()

            Text(card.headlineGlyph)
                .font(.system(size: 96, weight: .black, design: .rounded))
                .foregroundStyle(accentColor)

            Text(card.title)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            VStack(spacing: 6) {
                Text("Typische Beispiele")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .textCase(.uppercase)

                ForEach(card.exampleWords, id: \.self) { example in
                    Text(example)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.lg)
        .appCardBackground(.accents, intensity: AppTheme.CardIntensity.soft)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Spacer()
            Image(systemName: "textformat")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Text("Keine Lern-Karten verfügbar")
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            Spacer()
        }
    }

    // MARK: - Footer — system-konforme CTAs

    private var footer: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Button("Jetzt üben", action: onStartPractice)
                .buttonStyle(AppPrimaryButtonStyle())
            Button("Schließen", action: onClose)
                .buttonStyle(AppSecondaryButtonStyle(tint: accentColor))
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.vertical, AppTheme.Spacing.md)
    }
}
