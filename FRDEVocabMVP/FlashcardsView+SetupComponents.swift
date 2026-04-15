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
        let progress = maxCards > minSlider ? CGFloat(displayCount - minSlider) / CGFloat(maxCards - minSlider) : 1.0

        return VStack(alignment: .leading, spacing: 8) {
            Text("Anzahl der Karten")
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)

            // Visual card stack
            HStack(spacing: 0) {
                Spacer()
                ZStack {
                    // Stack of cards — grows with slider
                    let visibleCards = max(1, Int(progress * 6) + 1)
                    ForEach(0..<visibleCards, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(sectionStyle.accent.opacity(0.12 + Double(i) * 0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(sectionStyle.accent.opacity(0.25 + Double(i) * 0.06), lineWidth: 1)
                            )
                            .frame(width: 44, height: 54)
                            .offset(x: CGFloat(i) * 3.5, y: -CGFloat(i) * 2.5)
                    }

                    // Count label on top card
                    Text("\(displayCount)")
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundStyle(sectionStyle.accent)
                        .offset(x: CGFloat(visibleCards - 1) * 3.5, y: -CGFloat(visibleCards - 1) * 2.5)
                }
                .frame(height: 72)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: displayCount)
                Spacer()
            }

            Text(isAll ? "Alle \(maxCards) Karten" : "\(displayCount) von \(maxCards) Karten")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(sectionStyle.accent)
                .frame(maxWidth: .infinity, alignment: .center)

            if maxCards > minSlider {
                // Custom Slider mit Elumi-Handle. Etwas eingerückt, damit man
                // nicht ganz bis an den Card-Rand ziehen muss, um Min/Max zu erreichen.
                elumiCardCountSlider(
                    value: sliderValue,
                    range: Double(minSlider)...Double(maxCards),
                    step: 1
                )
                .padding(.horizontal, 22)

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
                .foregroundStyle(sectionStyle.accent)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: title.isEmpty ? 72 : AppLayout.largeSelectionHeight)
        .padding(.horizontal, AppTheme.Spacing.md)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    /// Custom Slider mit Elumi-Avatar als Handle. Dünner Track + großer
    /// Drag-Handle, Tap+Drag auf der gesamten Track-Fläche.
    @ViewBuilder
    func elumiCardCountSlider(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1
    ) -> some View {
        let handleSize: CGFloat = 32
        let trackHeight: CGFloat = 8

        GeometryReader { geo in
            let trackWidth = geo.size.width
            let progress: CGFloat = {
                let span = range.upperBound - range.lowerBound
                guard span > 0 else { return 0 }
                return CGFloat((value.wrappedValue - range.lowerBound) / span)
            }()
            let handleX = max(handleSize / 2, min(trackWidth - handleSize / 2, trackWidth * progress))

            ZStack(alignment: .leading) {
                // Track-Hintergrund
                Capsule()
                    .fill(AppTheme.Colors.border.opacity(0.35))
                    .frame(height: trackHeight)
                    .frame(maxHeight: .infinity)

                // Track-Fortschritt
                Capsule()
                    .fill(sectionStyle.accent)
                    .frame(width: max(handleSize / 2, trackWidth * progress), height: trackHeight)
                    .frame(maxHeight: .infinity)

                // Elumi-Handle (echtes Asset wie im Footer + Spiel)
                ArcadeElumiAvatar(size: handleSize, withShadow: true)
                    .offset(x: handleX - handleSize / 2)
                    .animation(.spring(response: 0.18, dampingFraction: 0.85), value: handleX)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        let clampedX = min(max(0, drag.location.x), trackWidth)
                        let span = range.upperBound - range.lowerBound
                        guard span > 0 else { return }
                        let newValue = range.lowerBound + Double(clampedX / trackWidth) * span
                        let stepped = (newValue / step).rounded() * step
                        value.wrappedValue = min(max(range.lowerBound, stepped), range.upperBound)
                    }
            )
        }
        .frame(height: handleSize)
    }
}
