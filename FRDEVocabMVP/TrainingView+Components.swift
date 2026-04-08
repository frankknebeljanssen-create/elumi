import SwiftUI

extension TrainingView {
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
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    func largeTrainingSelectionCard(title: String, value: String) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: title.isEmpty ? 0 : 8) {
                if !title.isEmpty {
                    Text(title)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Text(value)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.down.circle.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(trainingActionTint)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: title.isEmpty ? 72 : AppLayout.largeSelectionHeight)
        .padding(.horizontal, AppTheme.Spacing.md)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
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
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    var largeTrainingTypeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
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
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 76)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }
}
