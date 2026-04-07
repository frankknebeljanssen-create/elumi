import SwiftUI

struct HeartsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appUsesGlobalChrome) private var usesGlobalChrome
    @AppStorage(appQuizHeartsKey) var collectedWorms = 0
    @AppStorage(appElumiWaterflohKey) var collectedWaterfloh = 0
    @AppStorage(appElumiAlgenkugelKey) var collectedAlgenkugel = 0
    @AppStorage(appElumiXPKey) var collectedXP = 0
    @AppStorage(appElumiCurrentStreakKey) var currentStreak = 0
    @AppStorage(appElumiBestStreakKey) var bestStreak = 0
    @AppStorage(appFirstNameKey) var firstName = "Frank"
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    @ObservedObject var listStore: VocabularyListStore
    let goHome: () -> Void
    let openSettings: () -> Void
    let sectionStyle: AppSectionStyle = .hearts

    private let statColumns = [
        GridItem(.flexible(), spacing: AppTheme.Spacing.xs),
        GridItem(.flexible(), spacing: AppTheme.Spacing.xs)
    ]

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
                    Text("Sammlung")
                        .font(AppTheme.Typography.largeTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    Text(introSubtitle)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                heroCard

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("Beute")
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    LazyVGrid(columns: statColumns, spacing: AppTheme.Spacing.sm) {
                        statCard(
                            title: "Würmchen",
                            value: "\(collectedWorms)",
                            subtitle: "Hauptwährung",
                            snackKind: .wuermchen
                        )

                        statCard(
                            title: "Wasserflöhe",
                            value: "\(collectedWaterfloh)",
                            subtitle: "Seltene Beute",
                            snackKind: .wasserfloh
                        )

                        statCard(
                            title: "Algenkugeln",
                            value: "\(collectedAlgenkugel)",
                            subtitle: "Legendäre Beute",
                            snackKind: .algenkugel
                        )

                        statCard(
                            title: "XP",
                            value: "\(collectedXP)",
                            subtitle: "Level-Fortschritt",
                            systemImage: "sparkles"
                        )
                    }
                }

                milestoneCard

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("Lernstand")
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    LazyVGrid(columns: statColumns, spacing: AppTheme.Spacing.sm) {
                        statCard(
                            title: "Streak",
                            value: "\(currentStreak)",
                            subtitle: countLabel(currentStreak, singular: "Tag", plural: "Tage"),
                            systemImage: "flame.fill"
                        )

                        statCard(
                            title: "Multiplikator",
                            value: String(format: "×%.1f", activeMultiplier),
                            subtitle: "für Würmchen",
                            systemImage: "bolt.fill"
                        )

                        statCard(
                            title: "Eigene Listen",
                            value: "\(listStore.customLists.count)",
                            subtitle: countLabel(listStore.customLists.count, singular: "Liste", plural: "Listen"),
                            systemImage: "list.bullet.rectangle.fill"
                        )

                        statCard(
                            title: "Wortschatz",
                            value: "\(totalWordsCount + totalPhrasesCount)",
                            subtitle: "\(totalWordsCount) Wörter · \(totalPhrasesCount) Phrasen",
                            systemImage: "sparkle.magnifyingglass"
                        )
                    }
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    Text("Level")
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    VStack(spacing: AppTheme.Spacing.sm) {
                        ForEach(elumiLevelTiers) { tier in
                            levelRow(for: tier)
                        }
                    }
                }
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, AppLayout.contentTopPadding)
            .padding(.bottom, AppTheme.Spacing.xxl)
            .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .tint(sectionStyle.accent)
        .appAmbientWormBackground(sectionStyle)
        .dismissKeyboardOnTap()
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
                onSettings: { openSettings() },
                isHeartsActive: true
            )
        }
    }

}
