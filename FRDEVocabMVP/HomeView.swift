import Foundation
import SwiftUI

/// Home-Screen (2×2-Hero-Rebuild).
///
/// Blöcke von oben nach unten:
///   1. Greeting + Streak-Inline + Maskottchen (`HomeHeader`)
///   2. Hero-Lernsektion als 2×2 Grid (`HomeHeroLearningSection`) —
///      Karteikarten · Nomen · Verben · Quiz, feste Reihenfolge, kein Scroll
///   3. Weitere Übungen (`HomeMoreExercisesSection`) — 4 gleich-breite
///      Tiles, gefiltert gegen die Hero-Module (keine Dopplungen)
///   4. Deine Tools (`HomeToolsSection`) — Scannen + Listen
///   5. Footer-Clearance
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
            // Basis-VStack-Spacing 0 — jeder Block bekommt sein eigenes
            // `padding(.top, …)`. Klare Gap-Hierarchie:
            //   Header → Hero:              12 pt (eng, Hero an Header)
            //   Hero → Weitere Übungen:     22 pt (klar abgesetzt)
            //   Weitere Übungen → Tools:    20 pt (klar abgesetzt)
            //   Tools → Footer:             +24 pt unten (Tools „klebt"
            //                               nicht mehr am Footer)
            VStack(alignment: .leading, spacing: 0) {
                // **Entry-Stagger** (Phase 7.6 — App-weites Micro-
                // Interaction-System): Header → Hero → Weitere →
                // Tools blenden nacheinander ein (Fade + 8 pt Slide-
                // Up, je +50 ms Delay). Insgesamt < 400 ms — „leicht
                // lebendig, nicht lang".
                HomeHeader(
                    greeting: Personalization.homeGreeting(for: profileStore.profile?.displayName),
                    streakDays: currentStreak
                )
                .appEntryTransition()

                // Hero-Grid (2×2) — Hauptentscheidung des Screens.
                // Näher an den Header gerückt, weil die frühere
                // Status-Card entfallen ist.
                HomeHeroLearningSection(
                    onSelect: { module in openHomeScreen(module.screen) }
                )
                .padding(.top, 12)
                .appEntryTransition(delay: 0.05)

                HomeMoreExercisesSection(
                    onSelect: { module in openHomeScreen(module.screen) }
                )
                .padding(.top, 22)
                .appEntryTransition(delay: 0.1)

                // **Home-Polish 2026-04-30 (User-Spec)**: leichter
                // Querstrich als visueller Trenner zwischen den
                // Übungs-Sektionen und den Tools („Scannen"/„Listen"
                // sind Werkzeuge, keine Lernmodule). Dezent
                // gehalten — Weiß bei 22 % Opacity (dunkler Home-BG
                // verlangt einen helleren Ton als das pink-getönte
                // `textSecondary`, das auf Dark zu warm/dunkel rüber-
                // kommt), 1 pt dünn — fürs Auge ein klarer Schnitt,
                // ohne dass die Linie selbst Aufmerksamkeit zieht.
                // Padding-top matcht den Tools-Top-Padding-Wert davor
                // (22 pt) für gleichmäßiges Atmen über und unter dem
                // Strich.
                Rectangle()
                    .fill(Color.white.opacity(0.22))
                    .frame(height: 1)
                    .padding(.top, 22)
                    .appEntryTransition(delay: 0.15)

                HomeToolsSection(
                    onSelectScan: { openHomeScreen(.scan) },
                    onSelectLists: { openHomeScreen(.lists(nil)) }
                )
                // **Home-Polish 2026-04-30**: Top-Padding 22 → 14 pt.
                // Der vorgelagerte Divider hat selbst 22 pt nach oben;
                // unter dem Strich reichen 14 pt damit die „Deine
                // Tools"-Headline sauber aber nicht zu locker auf den
                // Trenner folgt. Insgesamt liegt damit jetzt mehr Luft
                // (22 + 1 + 14 = 37 pt) zwischen MoreExercises und
                // Tools-Headline als zuvor (22 pt) — der Cut ist
                // visuell präsenter, wie vom User gewünscht.
                .padding(.top, 14)
                // Klarer Abstand zum Footer — Tools klebt nicht mehr.
                .padding(.bottom, 24)
                .appEntryTransition(delay: 0.2)

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
