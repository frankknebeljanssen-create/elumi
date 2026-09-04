// TrainingHubView.swift
// **2026-05-06** — Sub-Screen für die fünf Lern-Modi, erreichbar
// über die „Training"-Card auf Home (Hybrid-γ-v3-Refactor).
// Vorher lagen Vokabeln + die vier Spezial-Modi direkt auf Home als
// Tiles verteilt; mit dem Refactor sind sie hinter einer Card
// gebündelt, damit Home auf vier zentrale Methoden fokussiert ist
// (Karteikarten / Quiz / Mix-Training / Training).
//
// **Umbau 2026-09-03** — Quiz ist von Home hierher gezogen und der
// Screen ist entlang der Frage gegliedert, was das Kind gerade tut:
// üben oder nachsehen, ob es sitzt. Details im Kommentar an der
// „Üben"-Sektion unten.
//
// Layout:
//   ‹ Training
//
//   ÜBEN
//   [Karteikarten]                       ← WideCard 72pt
//   [Alle Vokabeln]                      ← WideCard 72pt
//   [Nomen]    [Verben]                  ← ModuleCard 2×3, 78pt
//   [Artikel]  [Verbformen]
//   [Akzente]  [Zufall]                  ← Zufall = Platzhalter
//   ──────────────────────────────────
//   PRÜFEN
//   [Quiz]                               ← WideCard 72pt

import SwiftUI

struct TrainingHubView: View {
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let openScreen: (AppScreen) -> Void
    let goHome: () -> Void
    let openSettings: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome

    private let sectionStyle: AppSectionStyle = .home

    /// Footer-Clearance — derselbe Pattern wie HomeView/AccentsEntryView.
    ///
    /// **2026-05-08 Padding-Cleanup** — Footer-Migration zu
    /// `.safeAreaInset(.bottom)` reserviert die Footer-Höhe systemweit;
    /// das frühere `footerHeight + insetBottom + sm` schob den
    /// Mascot-Block sichtbar nach oben weg.
    private var footerClearance: CGFloat {
        AppTheme.Spacing.sm
    }

    /// Höhe einer Drill-Kachel im Raster.
    ///
    /// **2026-09-03** — 88 → 78 pt. Das Raster ist von zwei auf drei
    /// Reihen gewachsen (Akzente kam aus der Quer-Card dazu, plus die
    /// Zufalls-Zelle) und darunter steht jetzt die Quiz-Card. Bei 88 pt
    /// rutschte genau die unter den Footer — also die Karte, auf die
    /// der Screen hinführt. Die 10 pt kommen aus dem Raster, weil die
    /// Kacheln nur Icon plus ein Wort tragen und den Platz am
    /// wenigsten brauchen.
    private let gridCardHeight: CGFloat = 78

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
                // **Elumi-Hilfe (2026-08-05)** — dieser Screen hatte gar
                // keinen Hilfe-Einstieg, obwohl hier die Frage "welchen
                // Modus nehm ich?" am dringendsten ist. Eigener Header
                // (kein `ModuleHeaderCard`), deshalb das Abzeichen hier
                // direkt in die Chevron-Zeile.
                ElumiHelpBadge(action: { ElumiHelpPresenter.shared.show(.training) })
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

                // **Hub-Umbau 2026-09-03** — „Basics"/„Specials" →
                // „Üben"/„Prüfen". Auslöser war der Umzug des Quiz von
                // Home hierher (User-Spec: Home ist zu voll). Das Quiz
                // ist kein Geschwister von Nomen und Verben, sondern
                // eines von Karteikarten und Alle Vokabeln — die drei
                // unterscheiden sich darin, wieviel das Kind selbst
                // produzieren muss (erkennen → produzieren → geprüft
                // werden). Deshalb steht es jetzt allein unter „Prüfen"
                // am Ende des Screens: erst üben, dann nachsehen, ob es
                // sitzt. Das ist auch die Reihenfolge, in der man es
                // sinnvoll benutzt.
                SectionLabel(text: "Üben", size: 15, weight: .bold)

                // **Home-Rebuild 2026-06-09** — Karteikarten ist von
                // Home in den Hub gewandert und liegt hier als erste
                // Basics-Option (App-Kern-Methode), vor Vokabeln. Route
                // unverändert: bestehender FlashcardsView-Flow (Setup-
                // Sheet etc.) via `AppScreen.flashcards(nil)`.
                // **Hub-Umbau 2026-09-03** — beide von `ModuleCard`
                // (Icon oben, Text darunter, 88 pt) auf `WideCard`
                // (Icon links, 72 pt) umgestellt. Zwei Gründe: Die
                // gestapelte Variante verschenkt über die volle Breite
                // viel Luft, und jetzt sehen alle drei Vollbreite-
                // Karten des Screens gleich aus — Karteikarten, Alle
                // Vokabeln und das Quiz unten. Das ist auch die
                // Aussage: drei Modi derselben Klasse, die kleinen
                // Kacheln dazwischen sind etwas anderes.
                WideCard(
                    title: "Karteikarten",
                    accent: AppTheme.Colors.moduleFlashcards,
                    height: 72,
                    titleSize: 20,
                    showsChevron: true,
                    iconFrameSize: 44,
                    icon: { HomeModuleIconView(icon: .karteikarten, size: 40, glyphTint: .white) },
                    onTap: {
                        feedbackPlayer.playTabSwitch()
                        openScreen(.flashcards(nil))
                    }
                )
                .padding(.bottom, 10)

                WideCard(
                    title: "Alle Vokabeln",
                    accent: AppTheme.Colors.moduleVocabulary,
                    height: 72,
                    titleSize: 20,
                    showsChevron: true,
                    iconFrameSize: 44,
                    icon: { HomeModuleIconView(icon: .vokabeln, size: 40, glyphTint: .white) },
                    onTap: {
                        feedbackPlayer.playTabSwitch()
                        openScreen(.train(TrainingLaunchContext(preferredMode: .vocabulary)))
                    }
                )
                // Bottom 10 → 6 pt (Spacing-Trim 2026-05-07).
                .padding(.bottom, 10)

                // **Hub-Umbau 2026-09-03** — die gezielten Drills
                // gehören inhaltlich weiter zu „Üben" und stehen
                // deshalb ohne eigenen Trennstrich direkt darunter.
                // Der Hairline-Divider markiert jetzt nur noch den
                // einen Schnitt, der eine Bedeutung hat: üben vs.
                // prüfen.
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                    spacing: 10
                ) {
                    ModuleCard(
                        title: "Nomen",
                        accent: AppTheme.Colors.moduleNomen,
                        height: gridCardHeight,
                        icon: { HomeModuleIconView(icon: .nomen, size: 44, glyphTint: .white) },
                        onTap: {
                            feedbackPlayer.playTabSwitch()
                            openScreen(.train(TrainingLaunchContext(preferredMode: .nouns)))
                        }
                    )
                    ModuleCard(
                        title: "Verben",
                        accent: AppTheme.Colors.moduleVerbs,
                        height: gridCardHeight,
                        icon: { HomeModuleIconView(icon: .verben, size: 44, glyphTint: .white) },
                        onTap: {
                            feedbackPlayer.playTabSwitch()
                            openScreen(.train(TrainingLaunchContext(preferredMode: .verbs)))
                        }
                    )
                    ModuleCard(
                        title: "Artikel",
                        accent: AppTheme.Colors.moduleArticles,
                        height: gridCardHeight,
                        icon: { HomeModuleIconView(icon: .artikel, size: 44, glyphTint: .white) },
                        onTap: {
                            feedbackPlayer.playTabSwitch()
                            openScreen(.train(TrainingLaunchContext(preferredMode: .articles)))
                        }
                    )
                    ModuleCard(
                        title: "Verbformen",
                        accent: AppTheme.Colors.moduleVerbforms,
                        height: gridCardHeight,
                        icon: { HomeModuleIconView(icon: .verbformen, size: 44, glyphTint: .white) },
                        onTap: {
                            feedbackPlayer.playTabSwitch()
                            openScreen(.train(TrainingLaunchContext(preferredMode: .verbforms)))
                        }
                    )
                    // **Hub-Umbau 2026-09-03** — Akzente lag vorher als
                    // WideCard quer unter dem 2×2-Grid. Das war kein
                    // Design-Statement, sondern ein Rest: fünf Kacheln
                    // füllen kein Zweispalten-Raster, also wurde die
                    // letzte breit gezogen — und wirkte dadurch
                    // wichtiger als Nomen oder Artikel, was sie nicht
                    // ist. Jetzt sitzt sie als gleich große Kachel im
                    // Raster, die sechste Zelle füllt der Zufalls-
                    // Platzhalter.
                    ModuleCard(
                        title: "Akzente",
                        accent: AppTheme.Colors.moduleAccents,
                        height: gridCardHeight,
                        icon: { HomeModuleIconView(icon: .akzente, size: 44, glyphTint: .white) },
                        onTap: {
                            feedbackPlayer.playTabSwitch()
                            openScreen(.accents(nil))
                        }
                    )
                    placeholderCard
                }
                // LazyVGrid bottom 16 → 8 pt.
                .padding(.bottom, 10)

                // Der einzige Schnitt mit Bedeutung: alles darüber ist
                // Übung, darunter kommt die Prüfung.
                Rectangle()
                    .fill(AppTheme.Colors.border)
                    .frame(height: 0.5)
                    .padding(.horizontal, -AppLayout.screenPadding)
                    .padding(.bottom, 10)

                SectionLabel(text: "Check", size: 15, weight: .bold)

                // **Quiz-Umzug 2026-09-03** — von Home hierher. Route
                // unverändert (`.quiz(nil)`), nur der Einstiegspunkt
                // wandert. Volle Breite, weil das Quiz ein ganzer
                // Modus ist und kein Einzeldrill wie Nomen oder
                // Artikel — und weil es allein in seiner Sektion steht.
                WideCard(
                    title: "Quiz",
                    accent: AppTheme.Colors.moduleQuiz,
                    height: 72,
                    titleSize: 20,
                    showsChevron: true,
                    cornerRadius: 18,
                    horizontalPadding: 14,
                    verticalPadding: 8,
                    iconFrameSize: 44,
                    icon: { HomeModuleIconView(icon: .quiz, size: 40, glyphTint: .white) },
                    onTap: {
                        feedbackPlayer.playTabSwitch()
                        openScreen(.quiz(nil))
                    }
                )
                // **2026-09-03** — der Maskottchen-Tipp-Block stand
                // hier und ist entfallen. Mit Quiz, sechs Drills und
                // den beiden Übungs-Karten trägt der Screen jetzt neun
                // Auswahlmöglichkeiten; der Tipp war das einzige
                // Element ohne Funktion und wurde vom Footer
                // angeschnitten. Lieber ganz weg als halb sichtbar.
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
        // **Erstnutzer-Hint (2026-06-09)** — erklärt die Aufteilung des
        // Screens und fordert zur Auswahl auf.
        // **2026-09-03** — an den Umbau Üben/Prüfen angepasst; der
        // Begriff „Specials" kommt auf dem Screen nicht mehr vor.
        .hintBubble(
            id: "training_intro",
            text: """
            Hier suchst du dir selbst aus, was du übst.
            „Karteikarten" zeigt dir ein Wort — du überlegst und drehst um.
            „Alle Vokabeln" fragt dich ab, per Tippen oder Sprechen.
            Die kleinen Kacheln trainieren gezielt eine Sache: Nomen, Verben, Artikel, Verbformen oder Akzente.
            Du bestimmst vorher, wie viel du machen willst.
            """
        )
    }

    // MARK: - Zufalls-Platzhalter

    /// Sechste Zelle im Drill-Raster — reserviert, noch ohne Funktion.
    ///
    /// **2026-09-03** — Das Raster hat fünf echte Drills (Nomen, Verben,
    /// Artikel, Verbformen, Akzente) und braucht eine sechste Zelle,
    /// damit keine der fünf durch Breite künstlich aufgewertet wird
    /// (vorher zog Akzente quer über die volle Breite). Statt die Lücke
    /// leer zu lassen, steht hier der reservierte Platz für „Zufall" —
    /// Elumi würfelt einen Drill aus. Bewusst als sichtbarer, aber
    /// nicht tippbarer Platzhalter: Der Screen ist dann schon in seiner
    /// Endform, wenn die Funktion nachgezogen wird.
    ///
    /// Höhe und Radius spiegeln `ModuleCard` (88 pt / 16 pt), damit die
    /// Zelle exakt im Raster sitzt.
    private var placeholderCard: some View {
        VStack(spacing: 4) {
            Image(systemName: "dice.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.45))
            Text("Zufall")
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .frame(height: gridCardHeight)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    AppTheme.Colors.border,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
        )
        .accessibilityHidden(true)
    }

    // MARK: - Header

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
