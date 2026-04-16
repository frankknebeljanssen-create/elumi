import Foundation
import SwiftUI

/// Neu strukturierter Home-Screen (Home-Redesign).
///
/// Der Screen besteht aus fünf klaren Sektionen — in dieser Reihenfolge:
///   1. Header (Begrüßung + Hauptfrage + Maskottchen)
///   2. Progress Board (Streak · Level/Progress · XP · Credits · Ziel-Hinweis)
///   3. Dein Fokus heute (genau **eine** Tagesaufgabe)
///   4. Weiterlernen / Letzte Session fortsetzen
///   5. Modul-Grid (7 Lernmodule) + schwache Organisations-Zeile (Listen)
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

    // MARK: - Daily Focus mapping
    //
    // Bis die Content-Logik das Fokus-System eigenständig bestimmt, leiten
    // wir die Card direkt aus dem `DailyChallengeStore` ab — exakt eine
    // Aufgabe, drei klare Zustände.

    private var dailyFocusData: HomeDailyFocusData {
        guard let challenge = dailyChallengeStore.challenge else {
            return HomeDailyFocusData(
                title: "Tagesaufgabe wird vorbereitet …",
                subtitle: "Gleich steht dein Fokus für heute.",
                progressText: nil,
                iconSystemName: "sparkles",
                accent: AppTheme.Colors.cta,
                state: .open
            )
        }
        switch challenge.status {
        case .open:
            return HomeDailyFocusData(
                title: challenge.type.title,
                subtitle: "Halte deinen Streak am Leben.",
                progressText: nil,
                iconSystemName: challenge.type.systemImage,
                accent: AppTheme.Colors.cta,
                state: .open
            )
        case .inProgress:
            return HomeDailyFocusData(
                title: challenge.type.title,
                subtitle: "Halte deinen Streak am Leben.",
                progressText: "\(challenge.currentProgress)/\(challenge.target)",
                iconSystemName: challenge.type.systemImage,
                accent: AppTheme.Colors.cta,
                state: .inProgress
            )
        case .done:
            return HomeDailyFocusData(
                title: "Tagesziel erreicht",
                subtitle: "Streak gesichert — gönn dir eine Bonusrunde.",
                progressText: nil,
                iconSystemName: "checkmark.seal.fill",
                accent: AppTheme.Colors.success,
                state: .done
            )
        }
    }

    /// Ziel für den Fokus-Tap. Offene/laufende Challenges führen zum
    /// Haupt-Learning-Flow (Quiz = Default, weil jede Challenge-Variante
    /// dort Progress macht), erfülltes Ziel öffnet den Progress-Hub.
    private var dailyFocusTargetScreen: AppScreen {
        guard let challenge = dailyChallengeStore.challenge else { return .quiz(nil) }
        switch challenge.status {
        case .open, .inProgress: return .quiz(nil)
        case .done:              return .hearts
        }
    }

    // MARK: - Continue-Session mapping
    //
    // Der `LastSessionStore` folgt im nächsten Schritt. Bis dahin bleibt
    // das Modell hier `nil` — die Card zeigt einen ruhigen Empty-State,
    // ohne den Home-Flow zu reißen.
    //
    // Sobald der Store existiert, wird `continueSessionData` aus ihm
    // gefüllt — die View bleibt unverändert.
    private var continueSessionData: HomeContinueSessionData? { nil }

    private func continueSession() {
        // Placeholder — Runde „Content-Logik" ergänzt den echten Re-Entry.
    }

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                HomeHeader(
                    greeting: Personalization.homeGreeting(for: profileStore.profile?.displayName),
                    mainQuestion: "Was möchtest du heute lernen?"
                )

                HomeProgressBoardCard(data: progressBoardData) {
                    openHomeScreen(.hearts)
                }

                HomeDailyFocusCard(data: dailyFocusData) {
                    openHomeScreen(dailyFocusTargetScreen)
                }

                HomeContinueSessionCard(data: continueSessionData) {
                    continueSession()
                }

                // Alle acht Modul-Kacheln als horizontaler Pager.
                // Initial sichtbar: die ersten vier — per Swipe links/rechts
                // kommen die weiteren vier (inkl. Listen).
                moduleSwipePager
                    .padding(.top, 4)

                // Globaler Lernrichtungs-Schalter — Spec-Spacing:
                // Grid → Switch 16–20 pt (hier: 8 lokal + 12 VStack = 20),
                // Switch → Footer 16 pt (8 lokal + 8 im homeFooterClearance).
                LanguageDirectionSwitch(size: .regular) {
                    feedbackPlayer.playToggle()
                }
                .padding(.top, 8)
                .padding(.bottom, 8)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.contentTopPadding)
            .padding(.bottom, homeFooterClearance)
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
                screen: .lists(nil)
            )
        }
        .padding(.bottom, 22)
    }

    @ViewBuilder
    private func moduleTile(
        icon: HomeModuleIcon,
        title: String,
        accent: Color,
        screen: AppScreen
    ) -> some View {
        HomeModuleTile(
            icon: icon,
            title: title,
            accent: accent,
            isPressed: pressedHomeScreen == screen,
            onTap: { openHomeScreen(screen) }
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
