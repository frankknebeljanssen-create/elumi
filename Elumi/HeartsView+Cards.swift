import SwiftUI

extension HeartsView {

    // MARK: - Header (Titel + Personalisierungs-Intro)
    //
    // Bewusst leise personalisiert: der Name erscheint *nur* in diesem
    // einzigen Untertitel des Progress Hub — der Rest des Screens bleibt
    // namens-neutral. Siehe `Personalization.progressHubIntro(for:)`.
    var progressHubHeader: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.xxs) {
            Text("Fortschritt")
                .font(AppTheme.Typography.largeTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text(Personalization.progressHubIntro(for: profileStore.profile?.displayName))
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
    }

    // MARK: - Hero
    //
    // Call-Site für die standalone `ProgressHeroCard`. Alle Werte kommen
    // aus den Hearts-Metrics (currentLevel, xpToNextLevel, collectedXP).
    // Diese dünne Wrapper-Schicht macht den Austausch gegen eine kompakte
    // Home-Variante später trivial — der Container bleibt gleich, nur die
    // Card-Instanz wird getauscht.
    var progressHeroCard: some View {
        ProgressHeroCard(
            levelTitle: currentLevel.title,
            levelNumber: currentLevel.level,
            xp: collectedXP,
            progress: Double(levelProgress),
            milestoneTagline: nextLevel.map { "Noch \(xpToNextLevel) XP bis \($0.title)" },
            snackKind: currentLevel.snackKind,
            sectionStyle: sectionStyle
        )
    }

    // MARK: - Beute-Strip
    //
    // Drei Währungen in einer kompakten Gruppe. Liegt in genau *einer*
    // Surface-Card, die Zellen sind durch 1pt-Divider getrennt. Kein
    // XP-Eintrag — XP ist die Hero-Identität, nicht Teil der Beute.
    var resourceStrip: some View {
        HStack(spacing: 0) {
            resourceStripCell(
                snackKind: .wuermchen,
                value: collectedWorms,
                label: "Credits"
            )
            resourceStripDivider
            resourceStripCell(
                snackKind: .wasserfloh,
                value: collectedWaterfloh,
                label: "Seltene Beute"
            )
            resourceStripDivider
            resourceStripCell(
                snackKind: .algenkugel,
                value: collectedAlgenkugel,
                label: "Legendäre Beute"
            )
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
    }

    @ViewBuilder
    func resourceStripCell(snackKind: ElumiSnackKind, value: Int, label: String) -> some View {
        VStack(spacing: 5) {
            ElumiSnackIcon(snackKind, size: 34)
            Text("\(value)")
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
    }

    private var resourceStripDivider: some View {
        Rectangle()
            .fill(AppTheme.Colors.border.opacity(0.55))
            .frame(width: 1, height: 72)
    }

    // MARK: - Lernstand-Strip
    //
    // Streak + Multiplier gebündelt; darunter (optional) die nächste
    // Streak-Meilenstein-Zeile. So wird der Streak-Kontext als *eine*
    // Gruppe lesbar — nicht als zwei separate Mini-Karten + eine dritte
    // Milestone-Karte wie früher.
    var learningStandStrip: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                learningStandCell(
                    systemImage: "flame.fill",
                    iconColor: Color(hex: "#FF9F40"),
                    value: "\(currentStreak)",
                    label: currentStreak == 1 ? "Tag Streak" : "Tage Streak"
                )
                resourceStripDivider
                learningStandCell(
                    systemImage: "bolt.fill",
                    iconColor: sectionStyle.accent,
                    value: String(format: "×%.1f", activeMultiplier),
                    label: "Multiplikator"
                )
            }

            // Tagesaufgabe als Primary-Footer: Status (Progress, Titel, Done).
            // Nimmt Vorrang vor dem Streak-Meilenstein-Hinweis, weil sie
            // der aktive Tages-Trigger für den Streak ist.
            if let dailyTagline = dailyChallengeFooterText {
                HStack(spacing: 6) {
                    Image(systemName: dailyChallengeFooterIcon)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(dailyChallengeFooterTint)
                    Text(dailyTagline)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }

            // Streak-Meilenstein als kleine Footer-Zeile — nur wenn es
            // *einen* nächsten Meilenstein gibt. Kein eigener Block, keine
            // eigene Karte — bewusste Integration in den Lernstand-Context.
            if let streakTagline = streakMilestoneTagline {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Text(streakTagline)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, AppTheme.Spacing.md)
        .frame(maxWidth: .infinity)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.soft)
    }

    @ViewBuilder
    func learningStandCell(systemImage: String, iconColor: Color, value: String, label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(iconColor)
                .frame(height: 34)
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.82)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Dein Weg (Level-Liste)
    //
    // Alle Level in *einer* Container-Karte, Rows durch dezente Divider
    // getrennt. Das aktive Level erhält einen subtilen Highlight-Hintergrund
    // — alle anderen Rows bleiben transparent. So verschwindet der bisherige
    // „Card-auf-Card-auf-Card"-Effekt und der Pfad wird als zusammenhängende
    // Progression lesbar.
    var levelPathList: some View {
        VStack(spacing: 0) {
            ForEach(Array(elumiLevelTiers.enumerated()), id: \.element.id) { idx, tier in
                levelPathRow(for: tier)
                if idx < elumiLevelTiers.count - 1 {
                    Rectangle()
                        .fill(AppTheme.Colors.border.opacity(0.4))
                        .frame(height: 1)
                        .padding(.leading, 60)
                }
            }
        }
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.subtle)
    }

    @ViewBuilder
    func levelPathRow(for tier: ElumiLevelTier) -> some View {
        let isUnlocked = collectedXP >= tier.threshold
        let isCurrent = tier.level == currentLevel.level

        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill((isUnlocked ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                        .opacity(isCurrent ? 0.22 : 0.14))
                ElumiSnackIcon(tier.snackKind, size: 22)
                    .opacity(isUnlocked ? 1 : 0.4)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text("Level \(tier.level)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .tracking(0.6)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    if isCurrent {
                        Text("Aktiv")
                            .font(.system(size: 10, weight: .black, design: .rounded))
                            .tracking(0.6)
                            .foregroundStyle(sectionStyle.accent)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(sectionStyle.accent.opacity(0.14)))
                    }
                }
                Text(tier.title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(isUnlocked ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 1) {
                Text("\(tier.threshold) XP")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .monospacedDigit()
                let rewards = levelRewardText(for: tier)
                if !rewards.isEmpty {
                    Text(rewards)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary.opacity(0.85))
                }
            }

            if isUnlocked && !isCurrent {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(sectionStyle.accent.opacity(0.75))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            isCurrent
                ? sectionStyle.accent.opacity(0.10)
                : Color.clear
        )
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
}
