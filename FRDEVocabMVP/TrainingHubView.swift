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
    ///
    /// **2026-05-08 Padding-Cleanup** — Footer-Migration zu
    /// `.safeAreaInset(.bottom)` reserviert die Footer-Höhe systemweit;
    /// das frühere `footerHeight + insetBottom + sm` schob den
    /// Mascot-Block sichtbar nach oben weg.
    private var footerClearance: CGFloat {
        AppTheme.Spacing.sm
    }

    var body: some View {
        // **Bug-Fix 2026-05-06 Iteration 4** — Chevron-Position-
        // Konsistenz mit Quiz/Karteikarten-Setup. Vorher saß die
        // Back-Chevron-Row INNERHALB des ScrollView und wurde durch
        // dessen Top-Padding nach unten gedrückt. Jetzt: Outer-
        // VStack(spacing: 0) am Body-Top mit Chevron direkt am
        // Safe-Area-Rand (analog `SessionSetupScreen` →
        // `SessionSetupHeader` → `ModuleHeaderCard`-Pattern). Der
        // Chevron sitzt damit auf identischer Höhe wie auf allen
        // anderen Push-Setup-Screens; das Maskottchen-Tipp-Block
        // am Ende hat wieder Atemraum bis zum Footer.
        VStack(spacing: 0) {
            HStack {
                // **Bug-Fix 2026-05-07** — Tint von `textPrimary`
                // (weiß-grau auf dark-bg) auf `elumiPink` (Brand-
                // Akzent). Vorher wirkte der Hub-Chevron wie der
                // System-Default; jetzt klar Brand-Pink, konsistent
                // zu Quiz/KK/Setup-Screens.
                AppBackButton(action: { dismiss() }, tint: AppTheme.Colors.elumiPink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppLayout.screenPadding)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    titleHeader
                        // **Polish 2026-05-07 Iteration 2** — Title-
                        // Bottom 32 → 18 pt nach Cards-Bumps. Cards
                        // wurden +12 pt höher; um Mascot ohne Scroll
                        // sichtbar zu halten, wandert das Spacing-
                        // Budget vom Title-Block weg.
                        .padding(.bottom, 18)

                // **Naming-Sweep 2026-05-06** — „Allgemein" → „Basics"
                // (Game-Sprache, kürzer, kindgerechter).
                SectionLabel(text: "Basics", size: 15, weight: .bold)

                // **Home-Rebuild 2026-06-09** — Karteikarten ist von
                // Home in den Hub gewandert und liegt hier als erste
                // Basics-Option (App-Kern-Methode), vor Vokabeln. Route
                // unverändert: bestehender FlashcardsView-Flow (Setup-
                // Sheet etc.) via `AppScreen.flashcards(nil)`.
                ModuleCard(
                    title: "Karteikarten",
                    accent: AppTheme.Colors.moduleFlashcards,
                    icon: { HomeModuleIconView(icon: .karteikarten, size: 44, glyphTint: .white) },
                    onTap: {
                        feedbackPlayer.playTabSwitch()
                        openScreen(.flashcards(nil))
                    }
                )
                .padding(.bottom, 10)

                ModuleCard(
                    title: "Alle Vokabeln",
                    accent: AppTheme.Colors.moduleVocabulary,
                    icon: { HomeModuleIconView(icon: .vokabeln, size: 44, glyphTint: .white) },
                    onTap: {
                        feedbackPlayer.playTabSwitch()
                        openScreen(.train(TrainingLaunchContext(preferredMode: .vocabulary)))
                    }
                )
                // Bottom 10 → 6 pt (Spacing-Trim 2026-05-07).
                .padding(.bottom, 6)

                // Hairline-Divider zwischen Allgemein und Spezial,
                // 0.5pt edge-to-edge. Bottom 10 → 6 pt.
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(height: 0.5)
                    .padding(.horizontal, -AppLayout.screenPadding)
                    .padding(.bottom, 6)

                // SPEZIAL — 2×2 (Nomen, Verben, Artikel, Verbformen)
                // mit 13pt Sub-Label.
                // **Naming-Sweep 2026-05-06** — „Spezial" → „Specials"
                // (parallel zu „Basics", konsistent in der
                // Game-Sprache).
                SectionLabel(text: "Specials", size: 15, weight: .bold)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ModuleCard(
                        title: "Nomen",
                        accent: AppTheme.Colors.moduleNomen,
                        icon: { HomeModuleIconView(icon: .nomen, size: 44, glyphTint: .white) },
                        onTap: {
                            feedbackPlayer.playTabSwitch()
                            openScreen(.train(TrainingLaunchContext(preferredMode: .nouns)))
                        }
                    )
                    ModuleCard(
                        title: "Verben",
                        accent: AppTheme.Colors.moduleVerbs,
                        icon: { HomeModuleIconView(icon: .verben, size: 44, glyphTint: .white) },
                        onTap: {
                            feedbackPlayer.playTabSwitch()
                            openScreen(.train(TrainingLaunchContext(preferredMode: .verbs)))
                        }
                    )
                    ModuleCard(
                        title: "Artikel",
                        accent: AppTheme.Colors.moduleArticles,
                        icon: { HomeModuleIconView(icon: .artikel, size: 44, glyphTint: .white) },
                        onTap: {
                            feedbackPlayer.playTabSwitch()
                            openScreen(.train(TrainingLaunchContext(preferredMode: .articles)))
                        }
                    )
                    ModuleCard(
                        title: "Verbformen",
                        accent: AppTheme.Colors.moduleVerbforms,
                        icon: { HomeModuleIconView(icon: .verbformen, size: 44, glyphTint: .white) },
                        onTap: {
                            feedbackPlayer.playTabSwitch()
                            openScreen(.train(TrainingLaunchContext(preferredMode: .verbforms)))
                        }
                    )
                }
                // LazyVGrid bottom 16 → 8 pt.
                .padding(.bottom, 8)

                // Akzente quer am Ende der Spezial-Sektion.
                // **Polish 2026-05-07** — Hub-Cards-Polish-Sweep:
                // height 56 → 68 (+12 pt) und titleSize 18 → 20 (+2 pt),
                // synchron zu den ModuleCards in BASICS/SPECIALS. Akzente
                // bleibt visuell balanced mit Nomen/Verben/Artikel/
                // Verbformen — dieselbe Größenklasse, nur quer.
                WideCard(
                    title: "Akzente",
                    accent: AppTheme.Colors.moduleAccents,
                    height: 68,
                    titleSize: 20,
                    icon: { HomeModuleIconView(icon: .akzente, size: 44, glyphTint: .white) },
                    onTap: {
                        feedbackPlayer.playTabSwitch()
                        openScreen(.accents(nil))
                    }
                )
                // Bottom 24 → 8 pt — Mascot rückt direkt an Akzente
                // ran, damit der Block ohne Scroll im Viewport sitzt.
                // **Polish 2026-05-07 Iteration 2** — Trennstrich-
                // Hairline zwischen Akzente und mascotTipBlock entfernt
                // (User-Feedback „kann weg"). Reduziert visuelles
                // Rauschen und spart die 0.5 pt + Padding-Bottom-Linie.
                .padding(.bottom, 8)

                mascotTipBlock
                    // Top 24 → 4 pt: Mascot rückt nahe an die Cards
                    // ran, damit der Block ohne Scroll sichtbar bleibt.
                    .padding(.top, 4)
                    // Bottom-Atemraum reduziert auf 8 pt — Tipp atmet
                    // weiterhin zum Footer hin, ohne den Block aus
                    // dem Viewport zu schieben.
                    .padding(.bottom, 8)

                Color.clear.frame(height: footerClearance)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            // **Bug-Fix 2026-05-06 Iteration 3** — Chevron sitzt
            // jetzt auf gleicher Höhe wie bei Quiz/Karteikarten-
            // Setup. Vorher Top-Padding `contentTopPadding` (24pt)
            // → Chevron tief im Screen. Jetzt `screenHeaderTopPadding`
            // (4pt) wie bei `SessionSetupScreen` — der Chevron sitzt
            // direkt an der Top-Safe-Area, der Title rutscht
            // entsprechend hoch und das Maskottchen-Tipp-Block am
            // Ende hat wieder Atemraum bis zum Footer.
            .padding(.top, AppLayout.screenHeaderTopPadding)
            .padding(.bottom, AppTheme.Spacing.sm)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
        .navigationBarBackButtonHidden(true)
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
        // **Erstnutzer-Hint (2026-06-09)** — erklärt die Aufteilung
        // Basics/Specials und fordert zur Auswahl auf.
        .hintBubble(
            id: "training_intro",
            text: """
            Hier suchst du dir selbst aus, was du übst.
            „Karteikarten" zeigt dir ein Wort — du überlegst und drehst um.
            „Alle Vokabeln" fragt dich ab, per Tippen oder Sprechen.
            Bei den „Specials" trainierst du gezielt eine Sache: Nomen, Verben, Artikel oder Akzente.
            Du bestimmst vorher, wie viel du machen willst.
            """
        )
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
        // **Polish 2026-05-07 Iteration 2** — Mascot kompakter
        // (86 → 72 pt) + internal VStack-spacing (10 → 6 pt), damit
        // der Block ohne Scroll in den Hub-Viewport passt nach den
        // Card-Bumps von 76 → 88 pt. Tipp-Text-Größe unverändert.
        //
        // **2026-06-09** — 72 → 52 pt. Nach dem neuen „Alle Vokabeln"-
        // Titel und dem Karteikarten-Eintrag in den Basics wurde der
        // Tipp-Text unter dem Maskottchen aus dem Viewport gedrückt;
        // mit dem kleineren Mascot ist er wieder sichtbar.
        VStack(spacing: 6) {
            ZStack {
                Image("SplashCharacter")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 52, height: 52)
                SplashCharacterBlinkOverlay(
                    size: 52,
                    startDate: .now
                )
                .frame(width: 52, height: 52)
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

    /// **2026-06-09** — „Worauf hast Du Bock?" ist jetzt der Haupt-
    /// Titel (vorher Subline unter „Dein Training"). Die kleine
    /// Subline wurde entfernt — der Titel steht allein. Style: 32pt
    /// black Pink (analog Home-Greeting).
    private var titleHeader: some View {
        // **Bug-Fix 2026-05-06 Iteration 2** — Chevron ist im Body
        // jetzt eine separate Row über dieser VStack (siehe oben).
        VStack(alignment: .leading, spacing: 14) {
            Text("Worauf hast Du Bock?")
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.elumiPink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
