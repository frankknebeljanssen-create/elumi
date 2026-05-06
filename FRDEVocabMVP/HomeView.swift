import Foundation
import SwiftUI

/// Home-Screen (Hybrid γ v3 Refactor, 2026-05-06).
///
/// Blöcke von oben nach unten:
///   1. Greeting + Streak-Inline + Maskottchen (`HomeHeader`) — unverändert
///   2. Headline „Was möchtest du heute lernen?"
///   3. **4 Methoden-Cards 2×2** (Typ A, je 110 pt):
///      • Karteikarten („Selbst gemacht")
///      • Quiz („Teste dich!")
///      • Mix-Training („Surprise!") — öffnet Slot-Pop-up via
///        `AppScreen.elumi`
///      • Training („Vokabeln & mehr") — führt zu `TrainingHubView`
///        mit Vokabeln + 4 Spezial-Modi + Akzente
///   4. Sub-Section-Label „DEINE TOOLS" (CAPS, klein, grau)
///   5. **2 Tools-Cards quer** (Typ C, je 76 pt): Scannen, Listen
///   6. Footer-Clearance
///
/// Vorher (vor Refactor): 2×2-Hero (Karteikarten/Nomen/Verben/Quiz) +
/// Weitere-Übungen-Reihe (Artikel/Verbformen/Akzente/Vokabeln) + Tools.
/// Mit dem Refactor sind Vokabeln + die vier Spezial-Modi hinter der
/// Training-Card gebündelt; der Slot/ELUMI-Tab entfällt als eigener
/// Tab und wandert hinter die Mix-Training-Card.
///
/// Navigation ist über `openScreen` injiziert — Home selbst kennt keine
/// konkrete Route-Logik, nur das Mapping Card → `AppScreen`.
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

    // MARK: - Hero-Methoden-Cards (Typ A 135pt, 2×1)

    /// **2026-05-06 Hybrid-γ-v3 Iteration 3** — Karteikarten + Quiz
    /// als Hero-Reihe oben (zwei Cards in einer Zeile). Vorher waren
    /// vier Cards in einem 2×2-Grid; jetzt sind nur die zwei
    /// „Identitäts-Methoden" hier oben — Mix-Training und Training
    /// wandern als Vollbreite-Cards drunter (`wideMethodCards`).
    /// Karteikarten bleibt emphasized (App-Grundidee).
    @ViewBuilder
    private var heroCardsRow: some View {
        HStack(spacing: 12) {
            MethodCard(
                title: "Karteikarten",
                subtitle: "Selbst gemacht",
                accent: AppTheme.Colors.moduleFlashcards,
                emphasized: true,
                icon: { HomeModuleIconView(icon: .karteikarten, size: 60, glyphTint: .white) },
                onTap: { openHomeScreen(.flashcards(nil)) }
            )

            MethodCard(
                title: "Quiz",
                subtitle: "Teste dich!",
                accent: AppTheme.Colors.moduleQuiz,
                icon: { HomeModuleIconView(icon: .quiz, size: 52, glyphTint: .white) },
                onTap: { openHomeScreen(.quiz(nil)) }
            )
        }
    }

    // MARK: - Wide-Methoden-Cards (Typ Wide ~86pt, untereinander)

    /// **2026-05-06 Hybrid-γ-v3 Iteration 3** — Mix-Training + Training
    /// als Vollbreite-Cards untereinander. Vorher Teil des 2×2-Grids
    /// oben; jetzt eigener Block mit Icon-links + Title + Subtitle +
    /// Chevron-rechts. Visuell kleiner als die Hero-Cards (App-
    /// Identität bleibt oben), aber prominenter als die Tools-Reihe
    /// (Scannen/Listen).
    @ViewBuilder
    private var wideMethodCards: some View {
        VStack(spacing: 12) {
            WideMethodCard(
                title: "Mix-Training",
                subtitle: "Surprise!",
                accent: AppTheme.Colors.elumiPinkDeep,
                icon: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                },
                onTap: { openHomeScreen(.elumi) }
            )

            WideMethodCard(
                title: "Training",
                subtitle: "Vokabeln & Spezial",
                accent: AppTheme.Colors.moduleVocabulary,
                icon: {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(.white)
                },
                onTap: { openHomeScreen(.trainingHub) }
            )
        }
    }

    // MARK: - Tools-Cards (Typ C 76pt, quer)

    /// Zwei Tools-Cards nebeneinander (Scannen + Listen). Layout:
    /// HStack mit Spacing 10 pt (matched die alte HomeToolsSection-
    /// Geometrie, damit der visuelle Rhythmus konsistent bleibt).
    @ViewBuilder
    private var toolsRow: some View {
        HStack(spacing: 10) {
            WideCard(
                title: "Scannen",
                accent: AppTheme.Colors.moduleScan,
                height: 76,
                icon: { HomeModuleIconView(icon: .scan, size: 48, glyphTint: AppTheme.Colors.moduleScan) },
                onTap: { openHomeScreen(.scan) }
            )

            WideCard(
                title: "Listen",
                accent: AppTheme.Colors.moduleLists,
                height: 76,
                icon: { HomeModuleIconView(icon: .listen, size: 48, glyphTint: AppTheme.Colors.moduleLists) },
                onTap: { openHomeScreen(.lists(nil)) }
            )
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // **Entry-Stagger** (Phase 7.6 — App-weites Micro-
                // Interaction-System): Header → Methoden → Tools
                // blenden nacheinander ein (Fade + 8 pt Slide-Up,
                // je +50 ms Delay).
                HomeHeader(
                    greeting: Personalization.homeGreeting(for: profileStore.profile?.displayName),
                    streakDays: currentStreak
                )
                .appEntryTransition()

                // Section-Header über den Methoden-Cards. Style
                // identisch zum bisherigen Hero-Header (16 pt
                // .medium, textSecondary, sentence-case).
                Text("Was möchtest du heute lernen?")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .padding(.top, 12)
                    .padding(.bottom, 4)
                    .appEntryTransition(delay: 0.05)

                // **2026-05-06 Hybrid-γ-v3 Iteration 3** — Layout-
                // Refactor: Karteikarten + Quiz oben als Hero-Reihe
                // (2×1, MethodCards 135 pt), Mix-Training und Training
                // drunter als Vollbreite-WideMethodCards (~86 pt).
                // Vorher: alle vier in einem uniformen 2×2-Grid.
                heroCardsRow
                    .padding(.top, 4)
                    .appEntryTransition(delay: 0.1)

                wideMethodCards
                    .padding(.top, 12)
                    .appEntryTransition(delay: 0.15)

                // Sub-Section-Label „DEINE TOOLS" (CAPS, klein, grau)
                // gemäß Hybrid-γ-v3-Spec. Trennt visuell die Methoden-
                // Sektion von den Tools (Scannen, Listen). Spacer
                // 32 pt darüber damit die Tools klar abgesetzt wirken.
                SectionLabel(text: "Deine Tools")
                    .padding(.top, 32)
                    .appEntryTransition(delay: 0.2)

                // **2 Tools-Cards quer** (Typ C, je 76 pt).
                toolsRow
                    .padding(.top, 0)
                    .padding(.bottom, 32)
                    .appEntryTransition(delay: 0.25)

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
