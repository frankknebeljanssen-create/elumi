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
                // **Polish 2026-05-06 Iteration 4 — Hub-Look an Home
                // angeglichen.** Vorher: 16pt .medium zentriert mit
                // Back-Chevron-ZStack. Jetzt: 32pt black linksbündig
                // (analog Home-Greeting), 14pt Spacing zur 14pt-
                // Subline. Back-Chevron läuft weiterhin über die
                // AppLocalChrome-TopBar oben (siehe `appLocalChrome`-
                // Modifier am Ende des body) — kein eigener Inline-
                // Back-Chevron mehr, wäre dann doppelt.
                titleHeader
                    .padding(.top, 24)
                    .padding(.bottom, 16)

                // ALLGEMEIN-Section — Sub-Label 13pt CAPS (analog
                // Home „DEINE TOOLS").
                SectionLabel(text: "Allgemein", size: 13)

                ModuleCard(
                    title: "Vokabeln",
                    accent: AppTheme.Colors.moduleVocabulary,
                    icon: { HomeModuleIconView(icon: .vokabeln, size: 36, glyphTint: .white) },
                    onTap: {
                        feedbackPlayer.playTabSwitch()
                        openScreen(.train(TrainingLaunchContext(preferredMode: .vocabulary)))
                    }
                )
                .padding(.bottom, 24)

                // **Polish-Divider** — Hairline zwischen Allgemein
                // und Spezial, 0.5pt edge-to-edge wie auf Home vor
                // der Tools-Section.
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(height: 0.5)
                    .padding(.horizontal, -AppLayout.screenPadding)
                    .padding(.bottom, 16)

                // SPEZIAL — 2×2 (Nomen, Verben, Artikel, Verbformen)
                // mit 13pt Sub-Label.
                SectionLabel(text: "Spezial", size: 13)

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

                // Akzente quer am Ende der Spezial-Sektion.
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
                .padding(.bottom, 24)

                // **Polish-Divider 2** — Hairline vor dem
                // Maskottchen-Tipp-Block, trennt visuell die
                // Card-Sektionen vom dekorativen Footer-Element.
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(height: 0.5)
                    .padding(.horizontal, -AppLayout.screenPadding)

                mascotTipBlock
                    .padding(.top, 24)

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

    /// **Polish 2026-05-06 Iteration 4** — Title-Block analog zum
    /// Home-Greeting: 32pt black linksbündig, 14pt VStack-Spacing
    /// zur Subline. Back-Chevron sitzt nicht mehr inline — er wird
    /// schon vom `appLocalChrome`-AppTopBar oben gerendert
    /// (`AppTopBar(onBack: { dismiss() })`); ein zweiter Inline-
    /// Back-Chevron wäre redundant. Subline 14pt textSecondary
    /// sentence-case (analog Streak-Pill-Position auf Home, aber
    /// als reiner Text — der Hub hat keinen Streak-Indikator).
    private var titleHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Training")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.elumiPink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text("Wähle deinen Schwerpunkt")
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
