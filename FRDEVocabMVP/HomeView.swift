import Foundation
import SwiftUI

/// Neu strukturierter Home-Screen (Home-Redesign).
///
/// Der Screen besteht aus vier klaren Sektionen — in dieser Reihenfolge:
///   1. Header (Begrüßung + Hauptfrage + Maskottchen)
///   2. Status-Card „Heute" (Feedback: Anzahl Aktionen, **kein** Ziel) —
///      wird bei aktiver „Weiterlernen"-Session durch die Continue-Card
///      ersetzt (Merge, nie beide parallel)
///   3. Progress Board (Streak · Level/Progress · XP · Ziel-Hinweis)
///   4. Modul-Pager (8 Lernmodule, 2 Seiten) — die Organisations-Kacheln
///      (Listen, Lexikon) liegen auf Seite 2 neben den Lernmodulen
///
/// Die drei oberen Komponenten (Progress / Fokus / Weiterlernen) sind
/// eigenständige Views mit dedizierten Datenmodellen — die HomeView baut
/// diese Modelle aus den bereits vorhandenen Stores (ProgressStore,
/// @AppStorage, DailyChallengeStore). Im nächsten Schritt („Content-Logik")
/// wird die Befüllung in Services / ViewModels verschoben, ohne dass die
/// Views angefasst werden müssen.
struct HomeView: View {
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let openScreen: (AppScreen) -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let openAccount: () -> Void
    let replaySplash: () -> Void

    // Die Lernrichtung wird jetzt ausschließlich über den globalen
    // `LanguageDirectionSwitch` gelesen/geschrieben — HomeView selbst
    // beobachtet sie nicht mehr direkt. Die Komponente nutzt denselben
    // `@AppStorage(appDirectionKey)`, alle anderen Module ebenfalls.
    @AppStorage(appElumiCurrentStreakKey) private var currentStreak = 0
    @AppStorage(appElumiXPKey) private var collectedXP = 0
    @AppStorage(appArcadeCreditsKey) private var arcadeCredits = 0

    private let sectionStyle: AppSectionStyle = .home
    @State private var pressedHomeScreen: AppScreen?
    @State private var isHomeNavigationLocked = false
    /// Aktive Seite im Modul-Swipe-Pager (0 = erste Vier, 1 = zweite Vier).
    /// Bleibt während der Session erhalten, damit ein zurückkehrender User
    /// dort weitermacht, wo er war.
    @State private var modulePage: Int = 0

    @ObservedObject private var progressStore = ProgressStore.shared
    @ObservedObject private var profileStore = ProfileStore.shared
    @ObservedObject private var dailyChallengeStore = DailyChallengeStore.shared
    /// Feedback-Quelle für die Status-Card „Heute" — zählt Aktionen des
    /// aktuellen Tages, ohne ein Tagesziel vorzugeben.
    @ObservedObject private var dailyStatsStore = DailyStatsStore.shared

    // MARK: - Layout helpers

    private var homeFooterClearance: CGFloat {
        usesGlobalChrome
            ? AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.sm
            : AppTheme.Spacing.lg
    }

    /// 2 Spalten — alle Modul-Kacheln sind jetzt gleich groß (Hero-Size).
    /// Beide Pager-Seiten nutzen dasselbe Grid, damit Seite 2 identisch
    /// wirkt und nur die Icons/Titel wechseln.
    private var heroGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 16), count: 2)
    }

    /// Feste Höhe für den Modul-Pager. Ergibt sich aus
    /// 2 × Tile-MinHeight (148) + Row-Spacing (16) + Platz für die
    /// PageTabView-Dots (~18). Konstante Höhe ist wichtig, damit die
    /// TabView in einer vertikalen ScrollView stabil bleibt.
    private let moduleSwipePagerHeight: CGFloat = 334

    // MARK: - Module color tokens (from AppTheme)

    private var moduleFlashcards: Color { AppTheme.Colors.moduleFlashcards }
    private var moduleNomen: Color { AppTheme.Colors.moduleNomen }
    private var moduleArticles: Color { AppTheme.Colors.moduleArticles }
    private var moduleVerbs: Color { AppTheme.Colors.moduleVerbs }
    private var moduleVerbforms: Color { AppTheme.Colors.moduleVerbforms }
    private var moduleVocabulary: Color { AppTheme.Colors.moduleVocabulary }
    private var moduleQuiz: Color { AppTheme.Colors.moduleQuiz }
    private var moduleLists: Color { AppTheme.Colors.moduleLists }

    // MARK: - Navigation helper

    private func openHomeScreen(_ screen: AppScreen) {
        guard !isHomeNavigationLocked else { return }
        isHomeNavigationLocked = true
        pressedHomeScreen = screen
        feedbackPlayer.playTabSwitch()
        openScreen(screen)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            pressedHomeScreen = nil
            isHomeNavigationLocked = false
        }
    }

    // MARK: - Progress Board mapping
    //
    // Struktur **final**. Die Datenbeschaffung (Streak / XP / Level /
    // Credits / Goal-Hint) greift aktuell direkt auf die vorhandenen
    // Stores zu. Der nächste Schritt verlagert das in ein Home-ViewModel.

    private var progressBoardData: HomeProgressBoardData {
        let level = GamificationConfig.level(forXP: collectedXP)
        let progress = GamificationConfig.progressTowardNextLevel(totalXP: collectedXP)
        return HomeProgressBoardData(
            streakDays: currentStreak,
            level: level,
            levelProgress: progress,
            totalXP: collectedXP,
            credits: arcadeCredits,
            goalHint: goalHint
        )
    }

    private var goalHint: String? {
        guard let next = nextElumiLevelTier(for: collectedXP) else { return nil }
        let remaining = max(0, next.threshold - collectedXP)
        guard remaining > 0 else { return nil }
        return "Noch \(remaining) XP bis \(next.title)"
    }

    // MARK: - Status-Card „Heute" mapping
    //
    // Die frühere „Dein Fokus heute"-Card (Tagesaufgabe/Ziel-System) ist
    // bewusst ersetzt worden — die Home-Priorität ist „User wählt selbst",
    // nicht „System gibt Aufgabe vor". Statt eines Ziels zeigt die
    // Status-Card, **was heute passiert ist**: Anzahl der absolvierten
    // Aktionen + optional „+X seit letzter Session".
    //
    // Quelle: `DailyStatsStore` (zählt zentral in `ProgressService.record`).
    // Der `DailyChallengeStore` bleibt bestehen — Rewards und Streak-
    // Advance hängen weiterhin an der Challenge-Logik, werden aber nicht
    // mehr als Home-Card dargestellt.

    /// Tap-Ziel der Status-Card: der Quiz-Flow ist der sinnvollste Default-
    /// Entry, weil jedes Modul-Setup ohnehin 1 Tap vom Home entfernt liegt
    /// und Quiz die breiteste Action-Klasse erzeugt. Bewusst **keine**
    /// harte Steuerung — der User kann Home jederzeit ignorieren und ein
    /// anderes Modul aus dem Pager wählen.
    private var statusCardTargetScreen: AppScreen { .quiz(nil) }

    // MARK: - Continue-Session mapping
    //
    // Der `LastSessionStore` folgt im nächsten Schritt. Bis dahin bleibt
    // das Modell hier `nil` — die Merge-Logik zeigt dann automatisch die
    // Daily-Fokus-Karte.
    //
    // Sobald der Store existiert, wird `continueSessionData` aus ihm
    // gefüllt — die View bleibt unverändert, nur die Merge-Priorität
    // greift.
    private var continueSessionData: HomeContinueSessionData? { nil }

    private func continueSession() {
        // Placeholder — Runde „Content-Logik" ergänzt den echten Re-Entry.
    }

    // MARK: - Fokus + Continue Merge
    //
    // Spec: beide Cards werden nicht parallel gezeigt, sondern gemergt.
    // Priorität:
    //   • Continue, wenn eine fortsetzbare Session existiert (stärkerer
    //     Impuls, klarer Re-Entry)
    //   • sonst Daily-Fokus (Tagesimpuls)
    // Ergebnis: immer **eine** Card — das Layout spart eine ganze
    // Card-Höhe, der Screen bleibt fokussiert.

    @ViewBuilder
    private var focusOrContinueCard: some View {
        if let continueData = continueSessionData {
            HomeContinueSessionCard(data: continueData) {
                continueSession()
            }
        } else {
            // Status-Card „Heute" (Feedback) statt der alten Fokus-Card
            // (Ziel). Aktionen werden aus dem `DailyStatsStore` gezogen —
            // Rollover passiert automatisch um 6 Uhr (konsistent zu
            // Streak + DailyChallenge).
            HomeStatusCard(
                actionsToday: dailyStatsStore.actionsToday,
                actionsSinceLastSession: dailyStatsStore.lastSessionDelta
            ) {
                openHomeScreen(statusCardTargetScreen)
            }
        }
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 10) {
                HomeHeader(
                    greeting: Personalization.homeGreeting(for: profileStore.profile?.displayName),
                    mainQuestion: "Wähle dein Training"
                )

                // Reihenfolge bewusst auf Flow optimiert: direkt nach
                // dem Greeting kommt die **Primary Action** (Fokus /
                // Continue). Die Status-Card mit Streak/Level/XP steht
                // darunter als Kontext — sie ist wichtig, aber kein
                // Handlungsimpuls.
                //
                // Fokus + Continue sind gemergt: es wird immer nur eine
                // Karte gezeigt. Priorität: fortsetzbare Session → Continue,
                // sonst → Daily-Fokus. So spart das Layout eine ganze
                // Card-Höhe, ohne eine der beiden Funktionen aufzugeben.
                focusOrContinueCard
                    .padding(.top, 10)

                // Progress-Board — sitzt **unter** der Fokus-Card, damit
                // der Tagesimpuls oben dominiert und die Werteleiste als
                // ruhiger Kontext folgt.
                HomeProgressBoardCard(data: progressBoardData) {
                    openHomeScreen(.hearts)
                }

                // 25 pt Luft über dem Pager — die 8 Modul-Kacheln rücken
                // gegenüber der Zwischenstufe (40 pt) nochmal 15 pt höher.
                // Gegenüber dem ursprünglichen 20-pt-Wert bleiben sie nur
                // 5 pt tiefer, der zweite Status-Block oben bekommt aber
                // weiterhin mehr visuelle Luft als zu Beginn. Unten
                // bleiben 30 pt Abstand zur fixierten Flag-Leiste.
                moduleSwipePager
                    .padding(.top, 25)
                    .padding(.bottom, 30)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.contentTopPadding)
            .padding(.bottom, AppTheme.Spacing.sm)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        // Die fixe Flag-Leiste am Home-Footer ist entfernt — der globale
        // Richtungs-Schalter bleibt in jedem Session-Setup erreichbar und
        // belegt nicht mehr permanent den Home-Fußbereich. Home wirkt
        // dadurch ruhiger und die 8 Modul-Tiles bekommen den Abschluss.
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
                isSettingsActive: false
            )
        }
    }

    // MARK: - Module Swipe Pager

    /// Horizontaler Pager mit zwei Seiten à 4 Kacheln — alle gleich groß
    /// (Hero-Size). Swipe nach links zeigt die zweite Seite. Page-Dots
    /// unten signalisieren, dass es eine weitere Seite gibt.
    private var moduleSwipePager: some View {
        TabView(selection: $modulePage) {
            modulePagePrimary
                .tag(0)
            modulePageSecondary
                .tag(1)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .never))
        .frame(height: moduleSwipePagerHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Modul-Auswahl, Seite \(modulePage + 1) von 2")
    }

    /// Seite 1 — Karteikarten · Nomen · Artikel · Verben.
    /// Reihenfolge folgt der didaktischen Progression (Lernformat →
    /// Wortarten-Grundlagen).
    private var modulePagePrimary: some View {
        LazyVGrid(columns: heroGridColumns, spacing: 16) {
            moduleTile(
                icon: .karteikarten,
                title: "Karteikarten",
                accent: moduleFlashcards,
                screen: .flashcards(nil)
            )
            moduleTile(
                icon: .nomen,
                title: "Nomen",
                accent: moduleNomen,
                screen: .train(TrainingLaunchContext(preferredMode: .nouns))
            )
            moduleTile(
                icon: .artikel,
                title: "Artikel",
                accent: moduleArticles,
                screen: .train(TrainingLaunchContext(preferredMode: .articles))
            )
            moduleTile(
                icon: .verben,
                title: "Verben",
                accent: moduleVerbs,
                screen: .train(TrainingLaunchContext(preferredMode: .verbs))
            )
        }
        .padding(.bottom, 22) // Platz für die Page-Dots unter dem Grid
    }

    /// Seite 2 — Verbformen · Vokabeln · Quiz · Listen.
    /// Listen läuft hier visuell mit, zielt aber auf den Organisations-
    /// Screen (`.lists`), nicht auf eine Training-Session.
    private var modulePageSecondary: some View {
        LazyVGrid(columns: heroGridColumns, spacing: 16) {
            moduleTile(
                icon: .verbformen,
                title: "Verbformen",
                accent: moduleVerbforms,
                screen: .train(TrainingLaunchContext(preferredMode: .verbforms))
            )
            moduleTile(
                icon: .vokabeln,
                title: "Vokabeln",
                accent: moduleVocabulary,
                screen: .train(TrainingLaunchContext(preferredMode: .vocabulary))
            )
            moduleTile(
                icon: .quiz,
                title: "Quiz",
                accent: moduleQuiz,
                screen: .quiz(nil)
            )
            moduleTile(
                icon: .listen,
                title: "Listen",
                accent: moduleLists,
                screen: .lists(nil),
                deemphasized: true // kein Lernmodul — visuell schwächer
            )
        }
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private func moduleTile(
        icon: HomeModuleIcon,
        title: String,
        accent: Color,
        screen: AppScreen,
        deemphasized: Bool = false,
        iconOffset: CGSize = .zero
    ) -> some View {
        HomeModuleTile(
            icon: icon,
            title: title,
            accent: accent,
            isPressed: pressedHomeScreen == screen,
            onTap: { openHomeScreen(screen) },
            deemphasized: deemphasized,
            iconOffset: iconOffset
        )
    }

    // Der lokale Flaggen-Toggle wurde durch den wiederverwendbaren
    // `LanguageDirectionSwitch` (globaler System-Schalter) ersetzt — die
    // Komponente liest/schreibt direkt auf `@AppStorage(appDirectionKey)`,
    // dadurch bleibt der Home-Zustand automatisch mit Session-Setup und
    // allen konsumierenden Modulen synchron.
    //
    // Version/Credit-Footer sind unter Account/Info verfügbar. Der
    // `replaySplash`-Prop bleibt im Struct erhalten, damit die
    // Aufruferseite nicht angefasst werden muss.
}
