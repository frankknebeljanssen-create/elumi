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
                // sind Werkzeuge, keine Lernmodule).
                //
                // **Iteration 3 (User-Spec „trenne etwas weniger
                // sichtbar und links und recht bis zum rand, so wie
                // die linie über dem footer")**: visuelle Angleichung
                // an die Footer-Top-Border in `AppBottomBarSurface-
                // Modifier`. Dort: `Rectangle().fill(AppTheme.Colors.
                // border).frame(height: 1)` — `border` ist
                // `elumiCream.opacity(0.12)`, also dezenter als die
                // vorherigen 22 % Weiß. Edge-to-edge erreichen wir
                // mit negativem Horizontal-Padding, das das
                // VStack-Wrapper-Padding (`AppLayout.screenPadding`)
                // negiert — der Strich läuft jetzt durch die ganze
                // Bildschirmbreite, identisch zur Footer-Linie.
                //
                // **Iteration 2 (Position)**: Top-Padding 22 → 34 pt —
                // der Strich rutscht weiter nach unten, der Cut sitzt
                // tiefer im Layout. „Deine Tools" rutscht durch den
                // erhöhten Padding-Below ebenfalls mit (siehe unten).
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(height: 1)
                    .padding(.horizontal, -AppLayout.screenPadding)
                    .padding(.top, 34)
                    .appEntryTransition(delay: 0.15)

                HomeToolsSection(
                    onSelectScan: { openHomeScreen(.scan) },
                    onSelectLists: { openHomeScreen(.lists(nil)) }
                )
                // **Home-Polish 2026-04-30 — Iteration 4 (User-Spec
                // „listen und tools mittig zwischen dem oberen trenner
                // und der linie am footer (also ein bisschen nach
                // oben)")**: top 20 → 12 pt, bottom 24 → 32 pt. Der
                // Tools-Block (Headline + Card-Reihe, ~84 pt) rutscht
                // dadurch um 8 pt nach oben, und die Card-Reihe sitzt
                // jetzt visuell mittig zwischen dem oberen Querstrich
                // und der Footer-Top-Linie. Der Divider selbst (mit
                // `padding(.top, 34)`) bleibt unverändert — User
                // explizit „oberer trenner bliebt auch wo er ist".
                .padding(.top, 12)
                .padding(.bottom, 32)
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
