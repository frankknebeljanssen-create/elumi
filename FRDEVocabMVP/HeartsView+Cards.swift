import SwiftUI

extension HeartsView {
    var heroCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Aktuelles Level")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    Text(currentLevel.title)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)

                    Text("Level \(currentLevel.level)")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(sectionStyle.accent)
                }

                Spacer(minLength: 0)

                ZStack {
                    Circle()
                        .fill(sectionStyle.accent.opacity(0.18))
                    ElumiSnackIcon(currentLevel.snackKind, size: 42)
                }
                .frame(width: 64, height: 64)
            }

            HStack(alignment: .lastTextBaseline, spacing: AppTheme.Spacing.xs) {
                Text("\(collectedXP)")
                    .font(.system(size: 50, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("XP")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            ViewThatFits {
                HStack(spacing: AppTheme.Spacing.sm) {
                    milestoneChip(title: "\(currentStreak)-Tage-Streak", isHighlighted: currentStreak > 0)
                    milestoneChip(title: String(format: "×%.1f Würmchen", activeMultiplier), isHighlighted: activeMultiplier > 1)
                }

                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    milestoneChip(title: "\(currentStreak)-Tage-Streak", isHighlighted: currentStreak > 0)
                    milestoneChip(title: String(format: "×%.1f Würmchen", activeMultiplier), isHighlighted: activeMultiplier > 1)
                }
            }

            VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                rewardProgressBar

                Text(heroSubtitle)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardBackground(sectionStyle, intensity: 0.14, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    var milestoneCard: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            Text("Nächster Meilenstein")
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            if let nextLevel {
                Text("Bei \(nextLevel.threshold) XP erreichst du \(nextLevel.title).")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                ViewThatFits {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        milestoneChip(title: currentLevel.title, isHighlighted: false)
                        milestoneChip(title: nextLevel.title, isHighlighted: true)
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                        milestoneChip(title: currentLevel.title, isHighlighted: false)
                        milestoneChip(title: nextLevel.title, isHighlighted: true)
                    }
                }

                Text(streakSubtitle)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Du hast das höchste Level erreicht. Jetzt geht es ums Ausbauen deiner Sammlung und deines Streaks.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(AppTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardBackground(sectionStyle, intensity: 0.10)
    }

    var rewardProgressBar: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.Colors.secondarySurface)

                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [
                                sectionStyle.accent.opacity(0.88),
                                AppTheme.Colors.warning.opacity(0.95)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: max(16, geometry.size.width * levelProgress))
            }
        }
        .frame(height: 12)
    }

    @ViewBuilder
    func statCard(
        title: String,
        value: String,
        subtitle: String,
        systemImage: String? = nil,
        snackKind: ElumiSnackKind? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
            HStack {
                Text(title)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(2)

                Spacer(minLength: 0)

                if let snackKind {
                    ElumiSnackIcon(snackKind, size: 28)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(sectionStyle.accent)
                }
            }

            Text(value)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Text(subtitle)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(AppTheme.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 106, alignment: .topLeading)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }

    @ViewBuilder
    func levelRow(for tier: ElumiLevelTier) -> some View {
        let isUnlocked = collectedXP >= tier.threshold
        let isCurrent = tier.level == currentLevel.level

        HStack(spacing: AppTheme.Spacing.sm) {
            ZStack {
                Circle()
                    .fill((isUnlocked ? sectionStyle.accent : AppTheme.Colors.secondarySurface).opacity(isCurrent ? 0.22 : 0.14))

                ElumiSnackIcon(tier.snackKind, size: 31)
                    .opacity(isUnlocked ? 1 : 0.45)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 3) {
                Text(tier.title)
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text("ab \(tier.threshold) XP · \(levelRewardText(for: tier))")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }

            Spacer(minLength: 0)

            if isCurrent {
                Text("Aktiv")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(sectionStyle.accent)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(sectionStyle.accent.opacity(0.14))
                    )
            } else if isUnlocked {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(sectionStyle.accent)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCardBackground(sectionStyle, intensity: isCurrent ? 0.12 : 0.06)
    }

    func levelRewardText(for tier: ElumiLevelTier) -> String {
        var parts: [String] = []
        if tier.rewardWorms > 0 {
            parts.append("+\(tier.rewardWorms) W")
        }
        if tier.rewardWaterfloh > 0 {
            parts.append("+\(tier.rewardWaterfloh) Wf")
        }
        if tier.rewardAlgenkugel > 0 {
            parts.append("+\(tier.rewardAlgenkugel) Ak")
        }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    func milestoneChip(title: String, isHighlighted: Bool) -> some View {
        Text(title)
            .font(AppTheme.Typography.caption)
            .foregroundStyle(isHighlighted ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill((isHighlighted ? sectionStyle.accent : AppTheme.Colors.secondarySurface).opacity(isHighlighted ? 0.22 : 1))
            )
            .overlay(
                Capsule()
                    .stroke(isHighlighted ? sectionStyle.accent.opacity(0.45) : AppTheme.Colors.border, lineWidth: 1)
            )
    }
}
