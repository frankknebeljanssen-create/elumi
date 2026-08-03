import Foundation
import SwiftUI

/// Home-Screen (Home-Rebuild, 2026-06-09).
///
/// Blöcke von oben nach unten:
///   1. Greeting + Streak-Inline + Maskottchen (`HomeHeader`) — unverändert
///   2. Headline „Was möchtest du heute üben?"
///   3. **4 Methoden-Cards Vollbreite** (Typ Wide, je 86 pt):
///      • Training („Karteikarten, Vokabeln & Spezial") — führt zu
///        `TrainingHubView`; Karteikarten ist hier als Auswahl-Option
///        eingehängt (nicht mehr als eigene Home-Card)
///      • Quiz („Teste dich!")
///      • Live Chat (`LeaChatHomeCard`) — führt zu `AppScreen.leaChat`
///      • Daily Drop („Heute schon gecheckt?") — öffnet Slot-Pop-up
///        via `AppScreen.elumi`
///   4. **2 Tools-Cards quer** (Typ C, je 76 pt): Scannen, Listen
///   5. Footer-Clearance
///
/// Vorher (Hybrid-γ-v3): Karteikarten + Quiz als 2×1-Hero-Reihe oben,
/// darunter Training/Live-Chat/Daily-Drop als Vollbreite-Cards. Mit dem
/// Rebuild ist die Karteikarten-Card ganz von Home entfernt und in den
/// Training-Hub gewandert; alle vier Method-Cards sind jetzt Vollbreite.
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

    // MARK: - Wide-Methoden-Cards (Typ Wide ~86pt, untereinander)

    /// **2026-06-09 Home-Rebuild** — Vier Vollbreite-Method-Cards
    /// untereinander: Training, Quiz, Live Chat, Daily Drop. Vorher
    /// lagen Karteikarten + Quiz als 2×1-Hero-Reihe oben; jetzt ist
    /// die Karteikarten-Card ganz von Home entfernt und als Auswahl-
    /// Option in den Training-Hub gewandert, Quiz ist zur Vollbreite-
    /// Card geworden. Alle vier Cards teilen das gleiche Method-Style-
    /// Profil (Icon-links + Title + Subtitle + Chevron, 86 pt).
    @ViewBuilder
    private var wideMethodCards: some View {
        VStack(spacing: 12) {
            WideCard(
                title: "Training",
                subtitle: "Karteikarten, Vokabeln & Spezial",
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

            // Quiz — vorher Hero-Card neben Karteikarten, jetzt als
            // Vollbreite-Method-Card. Route unverändert (`.quiz(nil)`).
            WideCard(
                title: "Quiz",
                subtitle: "Teste dich!",
                accent: AppTheme.Colors.moduleQuiz,
                height: 86,
                titleSize: 19,
                showsChevron: true,
                cornerRadius: 22,
                horizontalPadding: 16,
                verticalPadding: 12,
                iconFrameSize: 52,
                icon: { HomeModuleIconView(icon: .quiz, size: 44, glyphTint: .white) },
                onTap: { openHomeScreen(.quiz(nil)) }
            )

            // **Live Chat — Léa-Chat MVP Schritt 1 (2026-05-10)** —
            // Section-Header entfernt (Polish 2026-05-10) — andere
            // Cards auf Home haben auch keinen Section-Header, Drift weg.
            LeaChatHomeCard {
                openHomeScreen(.leaChat)
            }

            WideCard(
                // **Naming-Sweep 2026-05-06** — „Mix-Training" →
                // „Daily Drop" + neuer Subtitle. Brand-Begriff für
                // die Slot-basierte Surprise-Übung; konsistent zum
                // Pop-up-Pre-Title („DAILY DROP") und CTA („Drop
                // starten").
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

                    // **2026-06-09** — Section-Header „Was möchtest du
                    // heute üben?" entfernt (User-Spec). Das Top-Padding
                    // (vorher am Header) wandert auf den Card-Block,
                    // damit der Atemraum nach dem HomeHeader gleich
                    // bleibt.
                    //
                    // Methoden-Cards: vier Vollbreite-Cards
                    // untereinander (Training, Quiz, Live Chat, Daily
                    // Drop). Karteikarten ist als Auswahl-Option in den
                    // Training-Hub gewandert (nicht mehr als eigene
                    // Home-Card).
                    wideMethodCards
                        .padding(.top, 24)
                        .appEntryTransition(delay: 0.1)
                        // **Erstnutzer-Hint (2026-06-09)** — TestFlight-
                        // Vorbereitung: additiver Dismissible-Hint für
                        // Erstnutzer ohne begleiteten Onboarding-Flow.
                        // Verschwindet nach Dismiss dauerhaft (HintStore).
                        .hintBubble(
                            id: "home_intro",
                            text: "Hi, ich bin Elumi! 👋 Tipp auf Scannen und fotografier eine Seite aus deinem Vokabelbuch — ich mach dir daraus Karteikarten zum Üben."
                        )
                        // Bottom-Padding 8 pt bis zum Hairline-Divider
                        // (zusammen mit dem 2-pt-Spacer drunter ~10 pt).
                        .padding(.bottom, 8)

                    // **Naming-Sweep 2026-05-06 Iteration 6** — vom
                    // ehemaligen flexiblen `Spacer(minLength: 32)`
                    // (der Tools ans Footer drückte) zu einem fixen
                    // 8 pt Abstand. Iterativ über 56 → 24 → 16 → 8 pt
                    // gedrückt nach mehreren User-Feedback-Runden.
                    //
                    // **Polish 2026-05-10 Iter-3 → Iter-4** — 8 → 6
                    // → 2 pt. Reine Atemluft zwischen Training-Card
                    // und Hairline-Divider; nicht mehr.
                    Color.clear.frame(height: 2)

                    // **Top-Trennlinie** vor der Tools-Sektion —
                    // dezenter Hairline (0.5 pt, border-token).
                    // Edge-to-edge via negativem Horizontal-Padding,
                    // identisch zur Footer-Top-Border-Geometrie.
                    Rectangle()
                        .fill(AppTheme.Colors.border)
                        .frame(height: 0.5)
                        .padding(.horizontal, -AppLayout.screenPadding)
                        .appEntryTransition(delay: 0.2)

                    // **Polish 2026-05-10** — „Deine Tools"-Section-
                    // Label entfernt. Drift gegenüber dem Rest der
                    // Home-Sections (Daily Drop, Live Chat, Training
                    // haben keinen Section-Header). Trennlinie davor
                    // bleibt als visueller Anker zwischen Hauptmodul-
                    // Block und Tools-Block. `.padding(.top, 16)`
                    // wandert vom (gelöschten) SectionLabel hoch
                    // auf die toolsRow, damit der Abstand zur
                    // Trennlinie unverändert bleibt; entry-delay 0.22
                    // (vorher 0.25, jetzt einer Stufe schneller, weil
                    // ein Stagger-Step ausfällt).
                    toolsRow
                        .padding(.top, 16)
                        .padding(.bottom, 16)
                        .appEntryTransition(delay: 0.22)

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
