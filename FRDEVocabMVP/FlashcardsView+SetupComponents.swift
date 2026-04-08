import SwiftUI

extension FlashcardsView {
    var flashcardDictionaryLevelCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lernniveau")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: 10) {
                ForEach(DictionaryLearningLevel.allCases) { option in
                    Button {
                        setup.selectedStackDictionaryLearningLevel = option
                    } label: {
                        Text(option.title)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 50)
                            .font(AppTheme.Typography.button)
                            .foregroundStyle(setup.selectedStackDictionaryLearningLevel == option ? .white : AppTheme.Colors.textPrimary)
                            .background(setup.selectedStackDictionaryLearningLevel == option ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    func largeSetupSelectionCard(title: String, value: String) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(value)
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.down.circle.fill")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(sectionStyle.accent)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: AppLayout.largeSelectionHeight)
        .padding(.horizontal, 18)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    var largeFlashcardContentCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                ForEach(FlashcardContentSelection.allCases) { option in
                    Button {
                        setup.selectedSetupContent = option
                    } label: {
                        Text(option.rawValue)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.82)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 10)
                            .frame(maxWidth: .infinity, minHeight: 68)
                            .foregroundStyle(setup.selectedSetupContent == option ? .white : AppTheme.Colors.textPrimary)
                            .background(setup.selectedSetupContent == option ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 108)
        .padding(.horizontal, 18)
        .padding(.vertical, 4)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    var flashcardDirectionCard: some View {
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
                    .background(selectedAppDirection == .frenchToGerman ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
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
                    .background(selectedAppDirection == .germanToFrench ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    var flashcardCountLimitCard: some View {
        let maxCards = max(selectedStackCardCount, 1)
        let minSlider = min(5, maxCards)
        let sliderValue = Binding<Double>(
            get: {
                setup.selectedCardCount == 0 ? Double(maxCards) : Double(setup.selectedCardCount)
            },
            set: { newValue in
                let rounded = Int(newValue.rounded())
                setup.selectedCardCount = rounded >= maxCards ? 0 : max(minSlider, rounded)
            }
        )
        let displayCount = setup.selectedCardCount == 0 ? maxCards : min(setup.selectedCardCount, maxCards)
        let isAll = setup.selectedCardCount == 0 || setup.selectedCardCount >= maxCards

        return VStack(alignment: .leading, spacing: 12) {
            Text("Anzahl der Karten")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(isAll ? "Alle \(maxCards) Karten" : "\(displayCount) Karten")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(sectionStyle.accent)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            if maxCards > minSlider {
                Slider(value: sliderValue, in: Double(minSlider)...Double(maxCards), step: 1)
                    .tint(sectionStyle.accent)

                HStack {
                    Text("\(minSlider)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Spacer()
                    Text("Alle")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }


    func largeFlashcardToggleCard(title: String, value: String) -> some View {
        let valueParts = value.components(separatedBy: "·").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let primaryValue = valueParts.first ?? value
        let secondaryValue = valueParts.count > 1 ? valueParts.dropFirst().joined(separator: " · ") : ""

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if !title.isEmpty {
                    Text(title)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                Text(primaryValue)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if !secondaryValue.isEmpty {
                    Text(secondaryValue)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(sectionStyle.accent)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 96)
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }
}
