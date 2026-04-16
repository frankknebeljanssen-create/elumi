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

    var speedRoundToggle: some View {
        Button {
            session.isSpeedRound.toggle()
        } label: {
            HStack(spacing: 14) {
                // Icon immer in Modul-Akzentfarbe — konsistent mit dem
                // Listen-Icon in der „Ausgewählte Listen"-Card darüber.
                Image(systemName: session.isSpeedRound ? "bolt.circle.fill" : "bolt.circle")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(trainingActionTint)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Speed Round")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("45 Sekunden")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }

                Spacer()

                Image(systemName: session.isSpeedRound ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(session.isSpeedRound ? trainingActionTint : AppTheme.Colors.textDisabled)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity, minHeight: 100)
            .appCardBackground(sectionStyle, intensity: session.isSpeedRound ? AppTheme.CardIntensity.bold : AppTheme.CardIntensity.subtle, cornerRadius: AppLayout.largeCardCornerRadius)
        }
        .buttonStyle(.plain)
    }

    var speedRoundTimerBar: some View {
        let isUrgent = session.speedRoundTimeRemaining <= 10

        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isUrgent ? AppTheme.Colors.error : AppTheme.Colors.warning)

                Text("\(session.speedRoundScore)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.success)
                Text("richtig")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Spacer()

                Text("\(session.speedRoundTimeRemaining)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(isUrgent ? AppTheme.Colors.error : AppTheme.Colors.warning)
                    .monospacedDigit()
                    .scaleEffect(isUrgent ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: session.speedRoundTimeRemaining)
                Text("s")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            GeometryReader { geo in
                let progress = CGFloat(session.speedRoundTimeRemaining) / 45.0
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.Colors.textSecondary.opacity(0.2))
                    Capsule()
                        .fill(isUrgent ? AppTheme.Colors.error : AppTheme.Colors.warning)
                        .frame(width: max(0, geo.size.width * progress))
                        .animation(.linear(duration: 1.0), value: session.speedRoundTimeRemaining)
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .appCardBackground(sectionStyle, intensity: isUrgent ? AppTheme.CardIntensity.strong : AppTheme.CardIntensity.soft)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(isUrgent ? AppTheme.Colors.error.opacity(session.speedRoundTimeRemaining % 2 == 0 ? 0.8 : 0.3) : Color.clear, lineWidth: isUrgent ? 2 : 0)
        )
        .opacity(isUrgent ? (session.speedRoundTimeRemaining % 2 == 0 ? 1.0 : 0.7) : 1.0)
        .animation(.easeInOut(duration: 0.4), value: session.speedRoundTimeRemaining)
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
                                .font(.system(size: 21, weight: .bold, design: .rounded))
                                .foregroundStyle(AppTheme.Colors.textPrimary)
                            Text("45 Sek. Contest")
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
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
