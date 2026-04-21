import SwiftUI

extension TrainingView {
    func listCategoryButton(title: String, count: Int, category: ListPickerCategory) -> some View {
        let hasSelected = !session.selectedTrainingListIDs.isEmpty && {
            let filtered = filteredLists(for: category)
            return filtered.contains { session.selectedTrainingListIDs.contains($0.id) }
        }()

        return Button {
            feedbackPlayer.playTabSwitch()
            listPickerCategory = category
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Text("\(count)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(hasSelected ? trainingActionTint.opacity(AppTheme.CardIntensity.medium) : trainingActionTint.opacity(AppTheme.CardIntensity.whisper))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(hasSelected ? trainingActionTint.opacity(0.4) : AppTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    var trainingDirectionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Abfragerichtung")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: 10) {
                Button {
                    selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
                } label: {
                    HStack(spacing: 10) {
                        StraightFlagBadge(countryCode: "FR", width: 34, height: 23, labelFontSize: 11)
                        Text("→")
                            .font(.system(size: 18, weight: .black))
                        StraightFlagBadge(countryCode: "DE", width: 34, height: 23, labelFontSize: 11)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .foregroundStyle(selectedAppDirection == .frenchToGerman ? .white : AppTheme.Colors.textPrimary)
                    .background(selectedAppDirection == .frenchToGerman ? trainingActionTint : AppTheme.Colors.secondarySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    selectedAppDirectionRaw = Direction.germanToFrench.rawValue
                } label: {
                    HStack(spacing: 10) {
                        StraightFlagBadge(countryCode: "DE", width: 34, height: 23, labelFontSize: 11)
                        Text("→")
                            .font(.system(size: 18, weight: .black))
                        StraightFlagBadge(countryCode: "FR", width: 34, height: 23, labelFontSize: 11)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 50)
                    .foregroundStyle(selectedAppDirection == .germanToFrench ? .white : AppTheme.Colors.textPrimary)
                    .background(selectedAppDirection == .germanToFrench ? trainingActionTint : AppTheme.Colors.secondarySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    // Ehemaliger `speedRoundToggle` (standalone Card mit bolt-Icon und
    // Checkmark) wurde durch den systemweiten `drillModeSection`
    // ersetzt — siehe `TrainingView+Layout.swift`. Speed Round ist jetzt
    // kein separater Toggle mehr, sondern eine Modus-Option im
    // [Training] [Speed Round]-Paar der Drill-Module.

    /// Speed-Round-Timer-Card. Delegiert an die zentrale
    /// `SpeedRoundTimerCard` — Legacy-Methode bleibt als thin-wrapper
    /// erhalten, damit bestehende Call-Sites im Training-Layout nicht
    /// angetastet werden müssen.
    var speedRoundTimerBar: some View {
        SpeedRoundTimerCard(
            remainingSeconds: session.speedRoundTimeRemaining,
            totalSeconds: session.speedRoundTotalSeconds,
            correctCount: session.speedRoundScore,
            sectionStyle: sectionStyle
        )
    }

    var dictionaryTrainingLevelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lernniveau")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: 10) {
                ForEach(DictionaryLearningLevel.allCases) { option in
                    Button {
                        session.selectedDictionaryLearningLevel = option
                    } label: {
                        Text(option.title)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 38)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .foregroundStyle(session.selectedDictionaryLearningLevel == option ? .white : AppTheme.Colors.textPrimary)
                            .background(session.selectedDictionaryLearningLevel == option ? trainingActionTint : AppTheme.Colors.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    func largeTrainingSelectionCard(title: String, value: String, detail: String = "") -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text(value)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(trainingActionTint)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.down.circle.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(trainingActionTint)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 100)
        .padding(.horizontal, AppTheme.Spacing.md)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    var trainingModeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Was willst du trainieren?")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
            HStack(spacing: 8) {
                ForEach(TrainingMode.allCases) { mode in
                    Button {
                        session.trainingMode = mode
                    } label: {
                        VStack(spacing: 6) {
                            Text(mode.iconLabel)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Text(mode.rawValue)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 68)
                        .foregroundStyle(session.trainingMode == mode ? .white : AppTheme.Colors.textPrimary)
                        .background(session.trainingMode == mode ? trainingActionTint : AppTheme.Colors.secondarySurface)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    var trainingBottomOptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if session.trainingMode == .vocabulary {
                HStack(spacing: 10) {
                    ForEach(CardType.allCases) { item in
                        Button {
                            session.cardType = item
                        } label: {
                            Text(item.rawValue)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .foregroundStyle(session.cardType == item ? .white : AppTheme.Colors.textPrimary)
                                .background(session.cardType == item ? trainingActionTint : AppTheme.Colors.secondarySurface)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else {
                Button {
                    session.isSpeedRound.toggle()
                } label: {
                    HStack(spacing: 14) {
                        // Icon immer in Modul-Akzentfarbe — konsistent mit dem
                        // Listen-Icon in der „Ausgewählte Listen"-Card darüber.
                        Image(systemName: "flag.checkered")
                            .font(.system(size: 30, weight: .bold))
                            .foregroundStyle(trainingActionTint)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Speed Round")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Text("45 Sek. Contest")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textSecondary)
                        }

                        Spacer()

                        Image(systemName: session.isSpeedRound ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(session.isSpeedRound ? trainingActionTint : AppTheme.Colors.textDisabled)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 76)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium, cornerRadius: AppLayout.largeCardCornerRadius)
    }
}
