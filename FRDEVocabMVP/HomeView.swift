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

    // MARK: - Methoden-Cards (Typ A 110pt, 2×2)

    /// Vier Methoden-Cards (Karteikarten / Quiz / Mix-Training /
    /// Training). Layout: LazyVGrid mit zwei flexiblen Spalten,
    /// Spacing 12 pt horizontal und vertikal.
    @ViewBuilder
    private var methodCardsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
            spacing: 12
        ) {
            // Karteikarten — Asset-Icon, Modul-Blau.
            MethodCard(
                title: "Karteikarten",
                subtitle: "Selbst gemacht",
                accent: AppTheme.Colors.moduleFlashcards,
                icon: { HomeModuleIconView(icon: .karteikarten, size: 52, glyphTint: .white) },
                onTap: { openHomeScreen(.flashcards(nil)) }
            )

            // Quiz — Asset-Icon, Modul-Amber.
            MethodCard(
                title: "Quiz",
                subtitle: "Teste dich!",
                accent: AppTheme.Colors.moduleQuiz,
                icon: { HomeModuleIconView(icon: .quiz, size: 52, glyphTint: .white) },
                onTap: { openHomeScreen(.quiz(nil)) }
            )

            // Mix-Training — SF-Symbol „sparkles" (matches ELUMI-Tab-
            // Vibe). Tap → AppScreen.elumi → ElumiTabView mit dem
            // existierenden Slot-Pop-up + Slot-Maschine.
            MethodCard(
                title: "Mix-Training",
                subtitle: "Surprise!",
                accent: AppTheme.Colors.elumiPinkDeep,
                icon: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.white)
                },
                onTap: { openHomeScreen(.elumi) }
            )

            // Training — SF-Symbol „graduationcap.fill" als Umbrella-
            // Icon für die fünf Lern-Modi (Vokabeln + Spezifika).
            // Tap → TrainingHubView (Sub-Screen).
            MethodCard(
                title: "Training",
                subtitle: "Vokabeln & mehr",
                accent: AppTheme.Colors.moduleVocabulary,
                icon: {
                    Image(systemName: "graduationcap.fill")
                        .font(.system(size: 42, weight: .bold))
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

                // **4 Methoden-Cards** im 2×2-Grid (Typ A, je 110 pt).
                // Karteikarten/Quiz nutzen Asset-Icons; Mix-Training
                // und Training nutzen SF-Symbole, weil keine eigenen
                // Asset-Icons existieren (vgl. HomeModuleIcon-Enum —
                // dort gibt es nur die Per-Modul-Assets).
                methodCardsGrid
                    .padding(.top, 4)
                    .appEntryTransition(delay: 0.1)

                // Sub-Section-Label „DEINE TOOLS" (CAPS, klein, grau)
                // gemäß Hybrid-γ-v3-Spec. Trennt visuell die Methoden-
                // Sektion von den Tools (Scannen, Listen).
                SectionLabel(text: "Deine Tools")
                    .padding(.top, 22)
                    .appEntryTransition(delay: 0.15)

                // **2 Tools-Cards quer** (Typ C, je 76 pt).
                toolsRow
                    .padding(.top, 0)
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
