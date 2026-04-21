import Foundation
import SwiftUI

/// Home-Screen (2×2-Hero-Rebuild).
///
/// Blöcke von oben nach unten:
///   1. Greeting + Maskottchen (`HomeHeader`)
///   2. Kompakte Status-Card (`HomeCompactStatusCard`) — Streak + „Du bist dran"
///   3. Hero-Lernsektion als 2×2 Grid (`HomeHeroLearningSection`) —
///      Karteikarten · Nomen · Verben · Quiz, feste Reihenfolge, kein Scroll
///   4. Weitere Übungen (`HomeMoreExercisesSection`) — horizontale Scroll-Reihe,
///      gefiltert gegen die Hero-Module (keine Dopplungen)
///   5. Deine Tools (`HomeToolsSection`) — Scannen + Listen
///   6. Footer-Clearance
///
/// Navigation ist über `openScreen` injiziert — Home selbst kennt keine
/// konkrete Route-Logik, nur das Mapping Modul → `AppScreen`.
struct HomeView: View {
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let openScreen: (AppScreen) -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let openAccount: () -> Void
    let replaySplash: () -> Void

    // Die Lernrichtung wird ausschließlich über den globalen
    // `LanguageDirectionSwitch` gelesen/geschrieben — HomeView beobachtet
    // sie nicht mehr direkt.
    @AppStorage(appElumiCurrentStreakKey) private var currentStreak = 0

    private let sectionStyle: AppSectionStyle = .home
    @State private var isHomeNavigationLocked = false

    @ObservedObject private var profileStore = ProfileStore.shared

    // MARK: - Layout helpers

    private var homeFooterClearance: CGFloat {
        usesGlobalChrome
            ? AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.sm
            : AppTheme.Spacing.lg
    }

    // MARK: - Navigation

    private func openHomeScreen(_ screen: AppScreen) {
        guard !isHomeNavigationLocked else { return }
        isHomeNavigationLocked = true
        feedbackPlayer.playTabSwitch()
        openScreen(screen)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            isHomeNavigationLocked = false
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                HomeHeader(
                    greeting: Personalization.homeGreeting(for: profileStore.profile?.displayName)
                )

                // Kompakte Status-Card direkt unter dem Greeting — nur
                // Streak, keine Lernstand-Phrase mehr.
                HomeCompactStatusCard(
                    streakDays: currentStreak,
                    onTap: { openHomeScreen(.trophy) }
                )
                .padding(.top, -22)

                // Hero-Grid (2×2) — Hauptentscheidung des Screens.
                // Abstand zur Status-Card auf `setupMainSectionSpacing`
                // (16 pt) reduziert — vorher +8 pt extra, jetzt eng.
                HomeHeroLearningSection(
                    onSelect: { module in openHomeScreen(module.screen) }
                )
                .padding(.top, AppLayout.setupMainSectionSpacing)

                HomeMoreExercisesSection(
                    onSelect: { module in openHomeScreen(module.screen) }
                )
                .padding(.top, AppLayout.setupMainSectionSpacing + 4)

                HomeToolsSection(
                    onSelectScan: { openHomeScreen(.scan) },
                    onSelectLists: { openHomeScreen(.lists(nil)) }
                )
                // +6 → 0: Abstand über „Deine Tools" kleiner
                // (User-Wunsch).
                .padding(.top, AppLayout.setupMainSectionSpacing)

                Color.clear.frame(height: homeFooterClearance)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.contentTopPadding)
            .padding(.bottom, AppTheme.Spacing.sm)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
        .dismissKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onInfo: openInfo, onAccount: openAccount)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.topBarInsetTop)
        } bottomBar: {
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: {},
                onFavorite: nil,
                onScan: nil,
                onSettings: openSettings,
                onScanCamera: { openHomeScreen(.scan) },
                onTrophy: { openHomeScreen(.trophy) },
                isSettingsActive: false
            )
        }
    }
}
