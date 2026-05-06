// TrainingHubView.swift
// **2026-05-06** — Sub-Screen für die fünf Lern-Modi, erreichbar
// über die „Training"-Card auf Home (Hybrid-γ-v3-Refactor).
// Vorher lagen Vokabeln + die vier Spezial-Modi direkt auf Home als
// Tiles verteilt; mit dem Refactor sind sie hinter einer Card
// gebündelt, damit Home auf vier zentrale Methoden fokussiert ist
// (Karteikarten / Quiz / Mix-Training / Training).
//
// Layout (Spec-konform):
//   ‹ Training
//
//   ALLGEMEIN
//   [Vokabeln]                           ← ModuleCard, full-width
//
//   SPEZIAL
//   [Nomen]    [Verben]                  ← ModuleCard 2×2
//   [Artikel]  [Verbformen]
//   [Akzente]                            ← WideCard 56pt, am Ende

import SwiftUI

struct TrainingHubView: View {
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let openScreen: (AppScreen) -> Void
    let goHome: () -> Void
    let openSettings: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome

    private let sectionStyle: AppSectionStyle = .home

    /// **Polish 2026-05-06** — Aktuell sichtbarer Lern-Tipp aus
    /// `TrainingHubTips.pool`. Wird beim Mount/Re-Visit (`.onAppear`)
    /// neu gewürfelt. Initial-Wert ist ein Random-Pick, damit beim
    /// ersten Build schon ein Tipp da ist.
    @State private var currentTip: String = TrainingHubTips.random()

    /// Footer-Clearance — derselbe Pattern wie HomeView/AccentsEntryView.
    private var footerClearance: CGFloat {
        usesGlobalChrome
            ? AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.sm
            : AppTheme.Spacing.lg
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                // Screen-Title — analog Sub-Screens wie Akzente, mit
                // Back-Chevron oben links. Style: 16pt .medium weiß
                // gemäß User-Spec; Back-Chevron via AppBackButton-
                // Pattern aus dem App-Designsystem.
                titleHeader
                    .padding(.bottom, 18)

                // ALLGEMEIN — Vokabeln allein, full-width.
                SectionLabel(text: "Allgemein")

                ModuleCard(
                    title: "Vokabeln",
                    accent: AppTheme.Colors.moduleVocabulary,
                    icon: { HomeModuleIconView(icon: .vokabeln, size: 36, glyphTint: .white) },
                    onTap: {
                        feedbackPlayer.playTabSwitch()
                        openScreen(.train(TrainingLaunchContext(preferredMode: .vocabulary)))
                    }
                )
                .padding(.bottom, 22)

                // SPEZIAL — 2×2 (Nomen, Verben, Artikel, Verbformen).
                SectionLabel(text: "Spezial")

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ModuleCard(
                        title: "Nomen",
                        accent: AppTheme.Colors.moduleNomen,
                        icon: { HomeModuleIconView(icon: .nomen, size: 36, glyphTint: .white) },
                        onTap: {
                            feedbackPlayer.playTabSwitch()
                            openScreen(.train(TrainingLaunchContext(preferredMode: .nouns)))
                        }
                    )
                    ModuleCard(
                        title: "Verben",
                        accent: AppTheme.Colors.moduleVerbs,
                        icon: { HomeModuleIconView(icon: .verben, size: 36, glyphTint: .white) },
                        onTap: {
                            feedbackPlayer.playTabSwitch()
                            openScreen(.train(TrainingLaunchContext(preferredMode: .verbs)))
                        }
                    )
                    ModuleCard(
                        title: "Artikel",
                        accent: AppTheme.Colors.moduleArticles,
                        icon: { HomeModuleIconView(icon: .artikel, size: 36, glyphTint: .white) },
                        onTap: {
                            feedbackPlayer.playTabSwitch()
                            openScreen(.train(TrainingLaunchContext(preferredMode: .articles)))
                        }
                    )
                    ModuleCard(
                        title: "Verbformen",
                        accent: AppTheme.Colors.moduleVerbforms,
                        icon: { HomeModuleIconView(icon: .verbformen, size: 36, glyphTint: .white) },
                        onTap: {
                            feedbackPlayer.playTabSwitch()
                            openScreen(.train(TrainingLaunchContext(preferredMode: .verbforms)))
                        }
                    )
                }
                .padding(.bottom, 16)

                // Akzente quer am Ende — eigenständige Spezial-Modus-
                // Card (kein Training-Modus-Engine, eigenes
                // AccentSessionEngine), darum visuell separat.
                WideCard(
                    title: "Akzente",
                    accent: AppTheme.Colors.moduleAccents,
                    height: 56,
                    icon: { HomeModuleIconView(icon: .akzente, size: 36, glyphTint: .white) },
                    onTap: {
                        feedbackPlayer.playTabSwitch()
                        openScreen(.accents(nil))
                    }
                )

                // **Polish 2026-05-06** — Maskottchen + Lern-Tipp
                // unter den Sektionen, füllt den vorher freien Raum
                // zwischen dem letzten Card-Block und dem Footer.
                // Maskottchen-Asset (`SplashCharacter`) ist
                // wiederverwendet aus Footer/Home — kein neues
                // Asset nötig. Tipp rotiert pro Tab-Visit aus dem
                // `TrainingHubTips`-Pool.
                mascotTipBlock
                    .padding(.top, 28)

                Color.clear.frame(height: footerClearance)
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
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: { dismiss() }, onInfo: nil)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.topBarInsetTop)
        } bottomBar: {
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: { goHome() },
                onFavorite: nil,
                onScan: nil,
                onSettings: openSettings
            )
        }
        .onAppear {
            // **Polish 2026-05-06** — Lern-Tipp pro Hub-Visit neu
            // würfeln. `.onAppear` feuert beim ersten Mount und bei
            // jedem Re-Visit nach dem Zurückkehren von einem Modul
            // (Sub-Screen-Lifecycle re-mountet den Hub-Body).
            currentTip = TrainingHubTips.random()
        }
    }

    // MARK: - Header

    // MARK: - Mascot + Lern-Tipp Block

    /// **Polish 2026-05-06** — Dekorativer Maskottchen-Block am Ende
    /// des Hubs: SplashCharacter-Asset zentriert mit Blink-Overlay,
    /// darunter ein wechselnder Lern-Tipp aus `TrainingHubTips.pool`.
    /// Kein Tap-Behavior (rein dekorativ). Der freie Raum zwischen
    /// der letzten Card und dem Footer wirkt jetzt absichtlich
    /// gestaltet statt leer.
    private var mascotTipBlock: some View {
        VStack(spacing: 10) {
            ZStack {
                Image("SplashCharacter")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 86, height: 86)
                SplashCharacterBlinkOverlay(
                    size: 86,
                    startDate: .now
                )
                .frame(width: 86, height: 86)
            }
            // Subtiler Drop-Shadow, identisch zur Footer-Maskottchen-
            // Behandlung — Maskottchen liegt visuell „auf" dem
            // Background, nicht dahinter.
            .shadow(color: .black.opacity(0.18), radius: 4, x: 0, y: 2)

            Text(currentTip)
                // **Polish-Iteration 2026-05-06**: 13 → 16 pt + medium-
                // Weight (User-Feedback „Lerntipp Font viel zu klein").
                // Liest jetzt als bewusster Hint, nicht als Caption.
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Title-Header

    /// Title-Row — „Training" zentriert, Back-Chevron links, plus
    /// Sub-Hint „Wähle deinen Schwerpunkt" darunter (Polish 2026-05-06).
    /// Style: 16pt .medium weiß für den Title (matched die Konvention
    /// der anderen Sub-Screens), 13pt .regular textSecondary für die
    /// Subline (kindgerecht-einleitender Ton).
    private var titleHeader: some View {
        VStack(spacing: 4) {
            ZStack {
                Text("Training")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    AppBackButton(action: { dismiss() }, tint: .white)
                    Spacer(minLength: 0)
                }
            }

            Text("Wähle deinen Schwerpunkt")
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 4)
    }
}
