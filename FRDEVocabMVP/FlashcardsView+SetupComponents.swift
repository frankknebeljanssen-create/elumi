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
                            .frame(minHeight: 44)
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

    var flashcardCountLimitCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Anzahl der Karten")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            HStack(spacing: 10) {
                Button {
                    setup.isUsingAllCardCount = true
                    isCardCountFieldFocused = false
                } label: {
                    flashcardCountModeCard(
                        title: "ALLE",
                        subtitle: countLabel(selectedStackCardCount, singular: "Karte", plural: "Karten"),
                        isSelected: setup.isUsingAllCardCount
                    )
                }
                .buttonStyle(.plain)

                Button {
                    setup.isUsingAllCardCount = false
                    isCardCountFieldFocused = true
                } label: {
                    flashcardCountModeCard(
                        title: "ANZAHL",
                        subtitle: !setup.isUsingAllCardCount && effectiveSelectedCardCount > 0
                            ? countLabel(effectiveSelectedCardCount, singular: "Karte", plural: "Karten")
                            : "Eigene Zahl",
                        isSelected: !setup.isUsingAllCardCount
                    )
                }
                .buttonStyle(.plain)
            }

            if !setup.isUsingAllCardCount {
                HStack(spacing: 10) {
                    TextField("Anzahl eingeben", text: $setup.customCardCountText)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .keyboardType(.numberPad)
                        .submitLabel(.done)
                        .focused($isCardCountFieldFocused)

                    Button("OK") {
                        confirmCardCountEntry()
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 64)
                .background(AppTheme.Colors.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .id(flashcardCountInputScrollID)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 156)
        .padding(.horizontal, 18)
        .padding(.vertical, 6)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    func flashcardCountModeCard(title: String, subtitle: String, isSelected: Bool) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.system(size: 15, weight: .bold, design: .rounded))
            Text(subtitle)
                .font(AppTheme.Typography.caption)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.82)
                .foregroundStyle(isSelected ? Color.white.opacity(0.84) : AppTheme.Colors.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 82)
        .foregroundStyle(isSelected ? .white : AppTheme.Colors.textPrimary)
        .background(isSelected ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .lineLimit(title.isEmpty ? 2 : 1)
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
