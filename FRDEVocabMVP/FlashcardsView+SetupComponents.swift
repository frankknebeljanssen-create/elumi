import SwiftUI

extension FlashcardsView {
    /// Karteikarten-spezifische Convenience — delegiert an den globalen
    /// `setupCardLabel(_:)` (siehe AppViewModifiers.swift).
    func flashcardSetupCardLabel(_ text: String) -> some View {
        setupCardLabel(text)
    }

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
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
        let progress = maxCards > minSlider ? CGFloat(displayCount - minSlider) / CGFloat(maxCards - minSlider) : 1.0

        return VStack(alignment: .leading, spacing: 8) {
            flashcardSetupCardLabel("Anzahl der Karten")

            // Kompakte Inline-Zeile: links die große rote Zahl, daneben der
            // kleine Mini-Stapel (in derselben roten Farbe), dann der Slider.
            HStack(alignment: .center, spacing: 6) {
                Text("\(displayCount)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.error)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: displayCount)
                    .frame(minWidth: 60, alignment: .leading)

                ZStack {
                    let visibleCards = max(1, Int(progress * 5) + 1)
                    ForEach(0..<visibleCards, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(AppTheme.Colors.error.opacity(0.18 + Double(i) * 0.12))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(AppTheme.Colors.error.opacity(0.4), lineWidth: 1)
                            )
                            .frame(width: 22, height: 28)
                            .offset(x: CGFloat(i) * 2.5, y: -CGFloat(i) * 1.5)
                    }
                }
                .frame(width: 36, height: 36)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: displayCount)

                if maxCards > minSlider {
                    elumiCardCountSlider(
                        value: sliderValue,
                        range: Double(minSlider)...Double(maxCards),
                        step: 1
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .appSetupCardBackground(cornerRadius: AppLayout.largeCardCornerRadius)
    }


    /// Card zur Auswahl, wie viele richtige Antworten hintereinander nötig
    /// sind, bis eine Karte aus dem Stapel fällt (1x / 2x / 3x).
    /// Platzierung: direkt unter `flashcardCountLimitCard` im Setup.
    var flashcardMasteryThresholdCard: some View {
        let labels: [(count: Int, label: String)] = [
            (1, "Schnell"),
            (2, "Normal"),
            (3, "Gründlich")
        ]
        return VStack(alignment: .leading, spacing: 10) {
            flashcardSetupCardLabel("Karte fällt raus nach")

            HStack(spacing: 6) {
                ForEach(labels, id: \.count) { entry in
                    let isSelected = setup.masteryThreshold == entry.count
                    Button {
                        setup.masteryThreshold = entry.count
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(entry.count)x")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(entry.label)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(hex: "#888888"))
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? Color(hex: "#1A3A55") : Color(hex: "#1A2A40"))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(
                                    isSelected ? AppTheme.Colors.elumiBlue : Color(hex: "#243B55"),
                                    lineWidth: isSelected ? 1.5 : 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .appSetupCardBackground(cornerRadius: AppLayout.largeCardCornerRadius)
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

    /// Effektive Karten-Anzahl für die kommende Übung — berücksichtigt
    /// den Slider-Wert (oder „alle" wenn 0). Wird sowohl in der Hunger-Card
    /// als auch in der Geschätzte-Zeit-Tile verwendet.
    var flashcardEffectiveCardCount: Int {
        let max = max(selectedStackCardCount, 0)
        guard max > 0 else { return 0 }
        return setup.selectedCardCount == 0
            ? max
            : Swift.min(setup.selectedCardCount, max)
    }

    /// „Ich hab Hunger"-Motivations-Card. Zeigt den Elumi-Avatar links und
    /// einen kleinen Hinweis-Text mit aktueller Karten-Anzahl als Highlight.
    var flashcardHungerCard: some View {
        let totalCards = flashcardEffectiveCardCount
        return HStack(alignment: .center, spacing: 12) {
            ArcadeElumiAvatar(size: 56, withShadow: false)

            (
                Text("Ich hab Hunger! ")
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                +
                Text("\(totalCards) Würmchen")
                    .foregroundStyle(AppTheme.Colors.elumiAmber)
                    .fontWeight(.bold)
                +
                Text(" warten auf mich. Fütter mich!")
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            )
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .appSetupCardBackground(cornerRadius: AppLayout.largeCardCornerRadius)
    }

    /// Stat-Trio: Geschätzte Zeit, Streak-Bonus, Tage-Streak. 3-Spalten-Grid.
    /// Geschätzte Zeit reagiert live auf:
    ///   • Anzahl der Karten (Slider in der Anzahl-Card)
    ///   • Mastery-Threshold (1× / 2× / 3× richtig) — höhere Schwelle
    ///     bedeutet mehr Wiederholungen pro Karte → längere Sitzung.
    /// Pacing: ~8 Sekunden pro Karte-Begegnung. Wir multiplizieren mit dem
    /// Threshold, weil jede Karte erst nach N richtigen Antworten rausfällt
    /// (in der Praxis braucht sie also mind. N Begegnungen, oft mehr).
    var flashcardStatsTrioCard: some View {
        let totalCards = max(flashcardEffectiveCardCount, 1)
        let threshold = max(1, setup.masteryThreshold)
        let totalEncounters = totalCards * threshold
        let estMinutes = max(1, Int((Double(totalEncounters) * 8.0 / 60.0).rounded()))

        return HStack(spacing: 8) {
            flashcardSetupTrioTile(value: "~\(estMinutes) min", label: "Geschätzte Zeit")
            flashcardSetupTrioTile(value: "x1.2", label: "Streak-Bonus")
            flashcardSetupTrioTile(value: "3", label: "Tage-Streak")
        }
        .frame(maxWidth: .infinity)
    }

    /// Spec: BG #1A2A40, Border #243B55 1px, Radius 10pt, Padding 10pt.
    /// Wert: 16pt/700 weiß, Label: 10pt #888888.
    private func flashcardSetupTrioTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color(hex: "#888888"))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: "#1A2A40"))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(hex: "#243B55"), lineWidth: 1)
        )
    }

    /// Custom Slider mit klassischem runden Handle in der Modul-Akzentfarbe.
    /// Dünner Track + Tap+Drag auf der gesamten Track-Fläche.
    @ViewBuilder
    func elumiCardCountSlider(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1
    ) -> some View {
        let handleSize: CGFloat = 22
        let trackHeight: CGFloat = 6

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

                // Track-Fortschritt — füllt den linken Teil bis zum Handle
                Capsule()
                    .fill(sectionStyle.accent)
                    .frame(width: max(handleSize / 2, trackWidth * progress), height: trackHeight)
                    .frame(maxHeight: .infinity)

                // Klassischer runder Handle in Modul-Akzent (blau bei Karteikarten)
                Circle()
                    .fill(sectionStyle.accent)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.85), lineWidth: 2)
                    )
                    .frame(width: handleSize, height: handleSize)
                    .shadow(color: .black.opacity(0.25), radius: 3, x: 0, y: 2)
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
