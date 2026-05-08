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
    /// **Daily-Drop-Habit-State 2026-05-06** — Live-Mirror der
    /// `DailyDropTracker`-Persistenz. Wird bei jedem Slot-Reveal
    /// (siehe `ElumiTabView` `onChange(of: slotPhase) → .revealed`)
    /// neu geschrieben; die HomeView reagiert damit sofort beim
    /// Pop-Back vom Slot-Screen, ohne explizites Re-Mount oder
    /// `.onAppear`-Reload.
    @AppStorage(appLastCompletedDailyDropDateKey) private var lastCompletedDailyDropTimestamp: Double = 0

    private let sectionStyle: AppSectionStyle = .home
    @State private var isHomeNavigationLocked = false

    @ObservedObject private var profileStore = ProfileStore.shared

    // MARK: - Layout helpers

    /// **2026-05-08 Padding-Cleanup** — Footer-Migration zu
    /// `.safeAreaInset(.bottom)` reserviert die Footer-Höhe systemweit;
    /// das frühere `footerHeight + insetBottom + sm` schob den letzten
    /// Home-Block sichtbar nach oben. Property gibt jetzt nur noch
    /// den Atemraum-Buffer zurück.
    private var homeFooterClearance: CGFloat {
        AppTheme.Spacing.sm
    }

    // MARK: - Navigation

    /// **Daily-Drop-Badge-State 2026-05-06** — computed aus dem
    /// `@AppStorage`-Mirror, sodass SwiftUI bei jedem Slot-Reveal
    /// automatisch re-rendert. Greift auf `Calendar.current.
    /// isDateInToday(...)` für die Tag-Wechsel-Logik zurück:
    /// Mitternacht (lokale Zeit) reset automatisch auf „NEU HEUTE",
    /// keine dedizierte Reset-Routine nötig.
    private var dailyDropBadgeState: DailyDropTracker.BadgeState {
        guard lastCompletedDailyDropTimestamp > 0 else { return .neuHeute }
        let date = Date(timeIntervalSinceReferenceDate: lastCompletedDailyDropTimestamp)
        return Calendar.current.isDateInToday(date) ? .erledigt : .neuHeute
    }

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
            WideCard(
                // **Naming-Sweep 2026-05-06** — „Mix-Training" →
                // „Daily Drop" + neuer Subtitle. Brand-Begriff für
                // die Slot-basierte Surprise-Übung; konsistent zum
                // Pop-up-Pre-Title („DAILY DROP") und CTA („Drop
                // starten").
                // **Card-Cleanup 2026-05-07** — `WideMethodCard` mit
                // `WideCard` zusammengelegt. Method-Style hier via
                // `subtitle: …` + `showsChevron: true` + Method-
                // Padding/Corner aktiviert.
                title: "Daily Drop",
                subtitle: "Heute schon gecheckt?",
                accent: AppTheme.Colors.elumiPinkDeep,
                height: 86,
                titleSize: 19,
                showsChevron: true,
                cornerRadius: 22,
                horizontalPadding: 16,
                verticalPadding: 12,
                iconFrameSize: 52,
                icon: {
                    // **Polish 2026-05-07** — Sparkles-SF-Symbol durch
                    // programmatische 3-Karten-Stack-Illustration
                    // ersetzt (siehe `DailyDropStackedCardsIcon`).
                    DailyDropStackedCardsIcon(size: 40)
                },
                onTap: { openHomeScreen(.elumi) }
            )
            // **Daily-Drop-Highlight + Habit-Tracking 2026-05-06** —
            // Badge-Text + Color jetzt dynamisch je nach
            // `DailyDropTracker`-State (geschrieben beim Slot-Reveal,
            // gelesen via @AppStorage-Mirror). „Neu heute" / Amber
            // wenn noch nicht erledigt; „✓ Heute gemacht" / Mint
            // sobald die Slot-Maschine heute mindestens einmal in
            // `.revealed` gelandet ist.
            .dailyDropCardHighlight(
                badgeText: dailyDropBadgeState.text,
                badgeColor: dailyDropBadgeState.color,
                badgeForeground: dailyDropBadgeState.foreground
            )

            WideCard(
                // **Card-Cleanup 2026-05-07** — Method-Style via
                // `subtitle:` + `showsChevron: true` + Method-Padding/
                // Corner; siehe Daily-Drop-Card oben für Pattern.
                title: "Training",
                subtitle: "Vokabeln & Spezial",
                accent: AppTheme.Colors.moduleVocabulary,
                height: 86,
                titleSize: 19,
                showsChevron: true,
                cornerRadius: 22,
                horizontalPadding: 16,
                verticalPadding: 12,
                iconFrameSize: 52,
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
                // **Naming-Sweep 2026-05-06 — Revert** — „Meine
                // Listen" → zurück zu „Listen" (User-Feedback). Mit
                // dem längeren Text griff `minimumScaleFactor` und
                // die Schrift wirkte kleiner; mit „Listen" steht
                // sie wieder auf den vollen 17 pt.
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
        // **Naming-Sweep 2026-05-06 Iteration 3** — vorher
        // GeometryReader + `frame(minHeight: geo.size.height)` der
        // den VStack auf volle Screen-Höhe streckte und Tools
        // dadurch ans Footer-Ende drückte. User-Feedback „Tools
        // nach oben, sitzen direkt am Footer". Jetzt rein
        // intrinsisch sized: Content fließt natürlich, Tools sitzen
        // mit fixem 8 pt Abstand nach den Wide-Cards (User-
        // Iterationen 2-6 haben den Wert schrittweise von 56 → 8
        // gedrückt, bis es sich „richtig" anfühlte).
        ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    // **Entry-Stagger** (Phase 7.6).
                    HomeHeader(
                        greeting: Personalization.homeGreeting(for: profileStore.profile?.displayName),
                        streakDays: currentStreak,
                        // **Bug-Fix 2026-05-06** — Streak-Pill-Tap
                        // navigiert zum Trophy/Fortschritt-Screen
                        // (User-Feedback „Pill tappable, führt zum
                        // Pokal"). Routing über die existierende
                        // `openHomeScreen`-Closure.
                        onStreakTap: { openHomeScreen(.trophy) }
                    )
                    .appEntryTransition()

                    // Section-Header über den Methoden-Cards. Größe
                    // 16 → 22 pt + textPrimary + .bold (User-Spec
                    // Spacing-Polish: prominenter, klarer Anker
                    // zwischen Header und Card-Block). Text-Update
                    // „lernen" → „üben" (User-Spec).
                    //
                    // **Naming-Sweep 2026-05-06 Iteration 2** —
                    // Top-Padding 28 → 48 pt. User-Feedback „Was
                    // möchtest du heute üben + die 4 Cards ein
                    // bisschen nach unten". Drückt den Section-
                    // Header und die nachfolgenden Cards um 20 pt
                    // tiefer; HomeHeader oben bekommt mehr Atemraum.
                    Text("Was möchtest du heute üben?")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .padding(.top, 48)
                        .padding(.bottom, 16)
                        .appEntryTransition(delay: 0.05)

                    // Methoden-Cards: Karteikarten + Quiz Hero-Reihe
                    // (2×1, 135 pt) und Mix-Training + Training als
                    // Vollbreite-WideMethodCards (~86 pt) drunter.
                    heroCardsRow
                        .appEntryTransition(delay: 0.1)

                    wideMethodCards
                        // **Polish 2026-05-07** — Top-Padding 12 →
                        // 20 pt. Daily-Drop-Card (erstes Element im
                        // wideMethodCards-VStack) hat ein Badge oben
                        // rechts, das -8pt über die Card-Kante ragt.
                        // Mit nur 12pt Abstand zur KK/Quiz-Hero-Reihe
                        // wirkte das Badge gequetscht; die zusätzlichen
                        // 8pt geben ihm subtilen Atemraum, ohne den
                        // Layout-Rhythmus zu brechen. Training-Card
                        // darunter rückt durch das interne VStack-
                        // Spacing (12pt) entsprechend mit.
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                        .appEntryTransition(delay: 0.15)

                    // **Naming-Sweep 2026-05-06 Iteration 6** — vom
                    // ehemaligen flexiblen `Spacer(minLength: 32)`
                    // (der Tools ans Footer drückte) zu einem fixen
                    // 8 pt Abstand. Iterativ über 56 → 24 → 16 → 8 pt
                    // gedrückt nach mehreren User-Feedback-Runden.
                    // Tools sitzen jetzt eng an den Wide-Cards; der
                    // Hairline-Divider darunter bleibt der primäre
                    // Zonen-Trenner.
                    Color.clear.frame(height: 8)

                    // **Top-Trennlinie** vor der Tools-Sektion —
                    // dezenter Hairline (0.5 pt, border-token).
                    // Edge-to-edge via negativem Horizontal-Padding,
                    // identisch zur Footer-Top-Border-Geometrie.
                    Rectangle()
                        .fill(AppTheme.Colors.border)
                        .frame(height: 0.5)
                        .padding(.horizontal, -AppLayout.screenPadding)
                        .appEntryTransition(delay: 0.2)

                    // Sub-Section-Label „DEINE TOOLS" — Größe 11 →
                    // 13 pt (User-Spec: prominenter ohne den CAPS-
                    // Charakter zu verlieren). Padding-top 16 nach
                    // Trennlinie.
                    SectionLabel(text: "Deine Tools", size: 13)
                        .padding(.top, 16)
                        .appEntryTransition(delay: 0.22)

                    // 2 Tools-Cards quer (Typ C, je 76 pt).
                    toolsRow
                        .padding(.bottom, 16)
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
