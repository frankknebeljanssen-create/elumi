import SwiftUI

/// **Pokal-Tab** (Footer). Sammelt die ausführlichen Status-/Fortschritts-
/// Cards, die früher dominant auf dem Home-Screen lagen — beim Home-Rebuild
/// (Phase „Final-Home") wurden sie dort entfernt, leben aber als bewährte
/// Komponenten weiter und kommen hier zur vollen Geltung.
///
/// Bewusst **keine Custom-Layouts** — die View komponiert exakt die
/// vorhandenen Karten:
///   • `HomeStatusCard`           — Anzahl Aktionen heute
///   • `HomeProgressBoardCard`    — Streak · Level/Progress · XP · Goal
///   • `HomeLernstatusCard`       — Cross-modulare Vokabel-Status-Übersicht
///
/// Tap-Aktionen führen weiterhin auf die jeweiligen Detail-Screens
/// (Hearts, Lernstatus, Quiz). Der Hub selbst ist eine ruhige Liste, kein
/// neues Dashboard.
struct TrophyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome

    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let navigate: (AppScreen) -> Void

    @AppStorage(appElumiCurrentStreakKey) private var currentStreak = 0
    @AppStorage(appElumiXPKey) private var collectedXP = 0
    @AppStorage(appArcadeCreditsKey) private var arcadeCredits = 0

    @ObservedObject private var dailyStatsStore = DailyStatsStore.shared
    @ObservedObject private var itemLearningStatusStore = ItemLearningStatusStore.shared

    private let sectionStyle: AppSectionStyle = .home

    // MARK: - Daten-Mappings (gespiegelt aus HomeView, damit der
    //         Pokal-Tab konsistent dieselben Cards zeigt).

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
        if let progressionHint = LevelProgression.xpGoalHint(currentXP: collectedXP) {
            return progressionHint
        }
        guard let next = nextElumiLevelTier(for: collectedXP) else { return nil }
        let remaining = max(0, next.threshold - collectedXP)
        guard remaining > 0 else { return nil }
        return "Noch \(remaining) XP bis \(next.title)"
    }

    private var lernstatusData: HomeLernstatusData {
        let strong = itemLearningStatusStore.strongItems.count
        let needsWork = itemLearningStatusStore.needsWorkItems.count
        let learning = itemLearningStatusStore.learningItems.count
        let sparse = itemLearningStatusStore.sparseItems.count
        return HomeLernstatusData(
            strongCount: strong,
            needsWorkCount: needsWork,
            sparseCount: learning + sparse,
            totalTracked: itemLearningStatusStore.totalTracked
        )
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                trophyHeader
                    .padding(.bottom, 6)

                // Drei Status-Cards im Pokal-Tab. User-Wunsch (letzte
                // Iteration): **schmaler** (horizontales Inset),
                // **näher zueinander** (dichtere VStack-Folge) und
                // trotzdem **atmungsaktives Padding** zwischen ihnen.
                // Der Wrapper setzt horizontales Inset + gleichmäßiges
                // vertikales Padding — VStack-Spacing ist 0, damit der
                // Abstand zwischen zwei Cards = wrapper-bottom +
                // wrapper-top des nächsten ist (= 2 × vertical).
                trophyCardWrapper {
                    HomeStatusCard(
                        actionsToday: dailyStatsStore.actionsToday,
                        actionsSinceLastSession: dailyStatsStore.lastSessionDelta
                    ) {
                        navigate(.quiz(nil))
                    }
                }

                trophyCardWrapper {
                    HomeProgressBoardCard(data: progressBoardData) {
                        navigate(.hearts)
                    }
                }

                trophyCardWrapper {
                    HomeLernstatusCard(data: lernstatusData) {
                        navigate(.lernstatus)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.contentTopPadding)
            .padding(.bottom, AppTheme.Spacing.xxl)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .tint(sectionStyle.accent)
        .appScreenBackground(sectionStyle)
        .dismissKeyboardOnTap()
        .toolbar(.hidden, for: .navigationBar)
        .appLocalChrome(enabled: !usesGlobalChrome) {
            AppTopBar(onBack: { dismiss() }, onInfo: openInfo)
                .padding(.horizontal, AppLayout.screenPadding)
                .padding(.top, AppLayout.topBarInsetTop)
        } bottomBar: {
            AppBottomBar(
                feedbackPlayer: feedbackPlayer,
                onHome: { goHome() },
                onFavorite: nil,
                onScan: nil,
                onSettings: openSettings,
                isTrophyActive: true
            )
        }
    }

    private var trophyHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            Text("Dein Fortschritt")
                .font(AppTheme.Typography.largeTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Streak, Level und Lernstatus.")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    /// Wrapper für jede Card im Pokal-Tab.
    ///
    /// - `padding(.horizontal, 10)` → Cards wirken **schmaler**, weil
    ///   sie einen ruhigen Seitenrand bekommen (die Rahmen-Spalte
    ///   bleibt homogen, der Content selbst ist nicht mehr
    ///   bildschirmbündig).
    /// - `padding(.vertical, 7)` + `VStack-spacing: 0` → Cards liegen
    ///   **näher zueinander** (2 × 7 = 14 pt Luft zwischen Karten,
    ///   statt vorher 8 + 16 + 8 = 32 pt), aber **mit** ordentlichem
    ///   Padding — also nicht flush.
    /// - `minHeight: 140` bleibt: die Cards dürfen weiterhin die
    ///   prominente Pokal-Höhe haben.
    @ViewBuilder
    private func trophyCardWrapper<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .frame(minHeight: 140)
    }
}
