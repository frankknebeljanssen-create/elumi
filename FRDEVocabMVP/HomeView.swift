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

    @AppStorage(appDirectionKey) private var selectedDirectionRaw = Direction.frenchToGerman.rawValue
    @AppStorage(appElumiCurrentStreakKey) private var currentStreak = 0
    @AppStorage(appElumiXPKey) private var collectedXP = 0
    @AppStorage(appArcadeCreditsKey) private var arcadeCredits = 0

    private let sectionStyle: AppSectionStyle = .home
    @State private var pressedHomeScreen: AppScreen?
    @State private var isHomeNavigationLocked = false

    @ObservedObject private var progressStore = ProgressStore.shared
    @ObservedObject private var profileStore = ProfileStore.shared
    @ObservedObject private var dailyChallengeStore = DailyChallengeStore.shared

    // MARK: - Layout helpers

    private var homeFooterClearance: CGFloat {
        usesGlobalChrome
            ? AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.sm
            : AppTheme.Spacing.lg
    }

    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
    }

    private var selectedDirection: Direction {
        Direction(rawValue: selectedDirectionRaw) ?? .frenchToGerman
    }

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
            VStack(alignment: .leading, spacing: 18) {
                HomeHeader(
                    greeting: Personalization.homeGreeting(for: profileStore.profile?.displayName),
                    mainQuestion: "Was möchtest du heute lernen?"
                )
                .padding(.top, 4)

                HomeProgressBoardCard(data: progressBoardData) {
                    openHomeScreen(.hearts)
                }

                HomeDailyFocusCard(data: dailyFocusData) {
                    openHomeScreen(dailyFocusTargetScreen)
                }

                HomeContinueSessionCard(data: continueSessionData) {
                    continueSession()
                }

                moduleGrid
                    .padding(.top, 2)

                organizationRow
                    .padding(.top, 2)

                directionToggleRow
                    .padding(.top, 4)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.contentTopPadding + AppTheme.Spacing.sm)
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

    // MARK: - Module Grid

    private var moduleGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 10) {
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
        }
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

    // MARK: - Organization row (Listen)

    private var organizationRow: some View {
        HomeOrganizationTile(
            icon: .listen,
            title: "Listen",
            subtitle: "Eigene Vokabellisten verwalten",
            isPressed: pressedHomeScreen == .lists(nil),
            onTap: { openHomeScreen(.lists(nil)) }
        )
    }

    // MARK: - Direction toggle

    private var directionToggleRow: some View {
        let isFrToDE = selectedDirection == .frenchToGerman
        return Button {
            feedbackPlayer.playToggle()
            selectedDirectionRaw = isFrToDE
                ? Direction.germanToFrench.rawValue
                : Direction.frenchToGerman.rawValue
        } label: {
            HStack(spacing: 10) {
                StraightFlagBadge(countryCode: isFrToDE ? "FR" : "DE", width: 36, height: 24, labelFontSize: 10)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                StraightFlagBadge(countryCode: isFrToDE ? "DE" : "FR", width: 36, height: 24, labelFontSize: 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.surface.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(AppTheme.Colors.border.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isFrToDE ? "Richtung: Französisch nach Deutsch" : "Richtung: Deutsch nach Französisch")
    }

    // Version/Credit-Footer wurde entfernt — die Info ist unter
    // Account/Info zu finden. Der `replaySplash`-Prop bleibt im Struct
    // erhalten, damit die Aufruferseite nicht angefasst werden muss.
}
