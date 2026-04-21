import SwiftUI

/// **Pokal / „Dein Fortschritt"** — zentraler Motivations- und
/// Fortschritts-Bereich (Rebuild).
///
/// Fünf Sections in einer ruhigen vertikalen Liste, jede in einer
/// standardisierten Setup-Card (`appSetupCardBackground`):
///
///   1. Hero Progress — Level + Fortschrittsbalken + XP bis nächstes Level
///   2. Streak        — 🔥 X Tage
///   3. Lernstatus    — gelernt · trainiert · gesamt
///   4. Achievements  — Milestone-Badges (aus bestehenden Daten abgeleitet)
///   5. Spiele        — Word-Runner-Freischaltung / „Jetzt spielen"
///
/// (Eine frühere 6. Credits-Card ist entfallen — der Credit-Count
/// lebt prominent im Game-Hub, eine doppelte Anzeige hier war
/// redundant.)
///
/// Header: zentrales `AppTopBar` mit Back-Button + Screen-Titel
/// („Dein Fortschritt"). Kein Custom-Chrome. Horizontales Inset über
/// `AppLayout.screenPadding` — Cards sind **nicht** randlos.
///
/// **Keine neue Logik**: die Sections lesen ausschließlich bestehende
/// Stores (`ItemLearningStatusStore`, `@AppStorage`-Werte) und
/// bestehende Helper (`GamificationConfig`, `LevelProgression`).
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

    @ObservedObject private var itemLearningStatusStore = ItemLearningStatusStore.shared

    private let sectionStyle: AppSectionStyle = .home

    /// XP-Schwelle, ab der Word Runner freigeschaltet ist. Display-seitige
    /// Motivation — das eigentliche Game im Game-Tab läuft unabhängig.
    private static let wordRunnerUnlockXP: Int = 100

    // MARK: - Body

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                heroProgressCard
                streakCard
                lernstatusCard
                achievementsCard
                wordRunnerCard
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

    // MARK: - Section 1: Hero Progress (Level + Progressbar + XP-Ziel)

    private var heroProgressCard: some View {
        let level = GamificationConfig.level(forXP: collectedXP)
        let progress = GamificationConfig.progressTowardNextLevel(totalXP: collectedXP)
        let levelEnd = GamificationConfig.levelEndXP(for: level)
        let remaining = max(0, levelEnd - collectedXP)

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                levelBadge(level: level)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Dein Fortschritt")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .textCase(.uppercase)
                        .tracking(1.2)
                    Text("Level \(level)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                }
                Spacer(minLength: 0)
            }

            progressBar(progress: progress)

            Text(remaining > 0
                 ? "Noch \(remaining) XP bis Level \(level + 1)"
                 : "Maximum erreicht — weiter so!")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
    }

    private func levelBadge(level: Int) -> some View {
        ZStack {
            Circle()
                .fill(sectionStyle.accent.opacity(0.22))
                .frame(width: 54, height: 54)
            Circle()
                .stroke(sectionStyle.accent.opacity(0.45), lineWidth: 1.5)
                .frame(width: 54, height: 54)
            Text("\(level)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(sectionStyle.accent)
                .monospacedDigit()
        }
    }

    private func progressBar(progress: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppTheme.Colors.textSecondary.opacity(0.18))
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                sectionStyle.accent,
                                sectionStyle.accent.opacity(0.8)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(6, geo.size.width * min(1.0, max(0.0, progress))))
            }
        }
        .frame(height: 10)
    }

    // MARK: - Section 2: Streak

    private var streakCard: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#FF9F40").opacity(0.18))
                    .frame(width: 46, height: 46)
                Text("🔥")
                    .font(.system(size: 24))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(currentStreak == 1 ? "1 Tag Streak" : "\(currentStreak) Tage Streak")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(streakSubline(for: currentStreak))
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
    }

    private func streakSubline(for days: Int) -> String {
        switch days {
        case 0:       return "Starte heute deine Serie."
        case 1:       return "Ein guter Anfang — morgen weiter."
        case 2...6:   return "Bleib dran, das wird was."
        case 7...13:  return "Eine Woche — stark!"
        case 14...29: return "Zwei Wochen — beeindruckend."
        default:      return "Elite-Zone. Chapeau."
        }
    }

    // MARK: - Section 3: Lernstatus (gelernt · trainiert · gesamt)

    private var lernstatusCard: some View {
        let strong = itemLearningStatusStore.strongItems.count
        let needsWork = itemLearningStatusStore.needsWorkItems.count
        let learning = itemLearningStatusStore.learningItems.count
        let sparse = itemLearningStatusStore.sparseItems.count
        let total = itemLearningStatusStore.totalTracked
        let trained = needsWork + learning + sparse

        return Button {
            navigate(.lernstatus)
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Lernstatus")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                HStack(spacing: 0) {
                    lernstatusColumn(
                        icon: "checkmark.seal.fill",
                        tint: Color(hex: "#4ADE80"),
                        label: "Gelernt",
                        value: strong
                    )
                    lernstatusDivider
                    lernstatusColumn(
                        icon: "bolt.fill",
                        tint: Color(hex: "#F59E0B"),
                        label: "Im Training",
                        value: trained
                    )
                    lernstatusDivider
                    lernstatusColumn(
                        icon: "sparkles",
                        tint: AppTheme.Colors.elumiPink,
                        label: "Gesamt",
                        value: total
                    )
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSetupCardBackground()
        }
        .buttonStyle(.plain)
    }

    private func lernstatusColumn(icon: String, tint: Color, label: String, value: Int) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
            Text("\(value)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
            Text(label)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(maxWidth: .infinity)
    }

    private var lernstatusDivider: some View {
        Rectangle()
            .fill(AppTheme.Colors.border.opacity(0.5))
            .frame(width: 1, height: 40)
    }

    // MARK: - Section 4: Achievements

    private struct Achievement: Identifiable {
        let id: String
        let emoji: String
        let title: String
        let unlocked: Bool
    }

    private var achievements: [Achievement] {
        let strong = itemLearningStatusStore.strongItems.count
        let level = GamificationConfig.level(forXP: collectedXP)
        return [
            Achievement(id: "first-xp",  emoji: "🌱", title: "Erster Funke",   unlocked: collectedXP > 0),
            Achievement(id: "streak-3",  emoji: "⚡", title: "3-Tage-Streak",  unlocked: currentStreak >= 3),
            Achievement(id: "streak-7",  emoji: "🔥", title: "Wochenflamme",   unlocked: currentStreak >= 7),
            Achievement(id: "level-3",   emoji: "⭐", title: "Level 3",        unlocked: level >= 3),
            Achievement(id: "strong-20", emoji: "💎", title: "20 sichere Wörter", unlocked: strong >= 20)
        ]
    }

    private var achievementsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Erfolge")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Spacer()
                let count = achievements.filter(\.unlocked).count
                Text("\(count) / \(achievements.count)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .monospacedDigit()
            }

            HStack(alignment: .top, spacing: 8) {
                ForEach(achievements) { achievement in
                    achievementBadge(achievement)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appSetupCardBackground()
    }

    private func achievementBadge(_ achievement: Achievement) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(achievement.unlocked
                          ? sectionStyle.accent.opacity(0.22)
                          : AppTheme.Colors.textSecondary.opacity(0.12))
                    .frame(width: 44, height: 44)
                Circle()
                    .stroke(
                        achievement.unlocked
                        ? sectionStyle.accent.opacity(0.45)
                        : AppTheme.Colors.border.opacity(0.4),
                        lineWidth: 1
                    )
                    .frame(width: 44, height: 44)
                Text(achievement.emoji)
                    .font(.system(size: 20))
                    .opacity(achievement.unlocked ? 1.0 : 0.35)
            }
            Text(achievement.title)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(achievement.unlocked
                                 ? AppTheme.Colors.textPrimary
                                 : AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .frame(height: 28, alignment: .top)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section 5: Spiele / Word Runner

    private var wordRunnerCard: some View {
        let unlocked = collectedXP >= Self.wordRunnerUnlockXP
        let remaining = max(0, Self.wordRunnerUnlockXP - collectedXP)

        // Im Unlocked-Zustand tappable → `.gameHub`. Im Locked-Zustand
        // bleibt die Card statisch (kein sinnvolles Ziel, solange die
        // XP-Schwelle nicht erreicht ist).
        return Button {
            guard unlocked else { return }
            navigate(.gameHub)
        } label: {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(unlocked
                              ? sectionStyle.accent.opacity(0.22)
                              : AppTheme.Colors.textSecondary.opacity(0.12))
                        .frame(width: 46, height: 46)
                    Image(systemName: unlocked ? "gamecontroller.fill" : "lock.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(unlocked
                                         ? sectionStyle.accent
                                         : AppTheme.Colors.textSecondary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Word Runner")
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(unlocked
                         ? "Jetzt spielen"
                         : "Freischalten bei \(Self.wordRunnerUnlockXP) XP · noch \(remaining)")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Spacer(minLength: 0)

                if unlocked {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSetupCardBackground()
        }
        .buttonStyle(.plain)
        .disabled(!unlocked)
    }

}
