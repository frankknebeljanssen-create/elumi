import SwiftUI

extension FlashcardsView {
    /// Karteikarten-spezifische Convenience — delegiert an den globalen
    /// `setupCardLabel(_:)` (siehe AppViewModifiers.swift).
    func flashcardSetupCardLabel(_ text: String) -> some View {
        setupCardLabel(text)
    }

    /// Etwas größere Label-Variante speziell für die Mechanik-Cards
    /// „Anzahl der Karten" + „Karte fällt raus nach" (+2 pt gegenüber
    /// dem Standard-Setup-Label). Wird nur dort genutzt — der globale
    /// `setupCardLabel` bleibt unverändert.
    func flashcardSetupCardLabelLarge(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12, weight: .semibold, design: .rounded))
            .tracking(1.5)
            .foregroundStyle(AppTheme.Colors.cardLabel)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium, cornerRadius: AppLayout.largeCardCornerRadius)
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
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium, cornerRadius: AppLayout.largeCardCornerRadius)
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
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium, cornerRadius: AppLayout.largeCardCornerRadius)
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
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    var flashcardCountLimitCard: some View {
        // **User-Revision 2026-04-22**: Hard-Cap bei 200 Karten in der
        // Auswahl-Card. Größere Listen werden intern weiterhin geladen,
        // aber der Setup-Slider erlaubt maximal 200 — wer mehr will,
        // splittet seine Session sauber in mehrere Durchläufe.
        let maxCards = min(max(selectedStackCardCount, 1), 200)
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
            flashcardSetupCardLabelLarge("Anzahl der Karten")

            // Kompakte Inline-Zeile: links die große rote Zahl, daneben der
            // kleine Mini-Stapel (in derselben roten Farbe), dann der Slider.
            HStack(alignment: .center, spacing: 6) {
                Text("\(displayCount)")
                    // **User-Revision**: Font nicht mehr bold (.black →
                    // .regular). 31 pt reicht visuell auch ohne Bold-
                    // Gewicht, die rote Farbe trägt die Auffälligkeit.
                    .font(.system(size: 31, weight: .regular, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.error)
                    .contentTransition(.numericText())
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: displayCount)
                    .frame(minWidth: 60, alignment: .leading)
                    // **User-Revision 2026-04-22**: Zahl 4 pt nach
                    // rechts verschieben, damit sie nicht direkt auf
                    // der linken Card-Kante klebt.
                    .padding(.leading, 4)

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
                // Mini-Stapel sitzt visuell zwischen der großen roten Zahl
                // und dem Slider. **User-Revision**: `x: -15` → `x: -9`,
                // damit der Stapel ein Stück weiter nach rechts rückt und
                // die Zahl etwas Luft hat. `y: 5` bleibt unverändert, der
                // Stapel sitzt weiterhin mittig zwischen Zahl-Baseline
                // und Slider-Track.
                .offset(x: -9, y: 5)
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
        // **User-Revision 2026-04-22**: Card noch einen Tick kompakter
        // (12 → 9 pt vertikal). Slider + Zahl füllen den Platz bei der
        // reduzierten Höhe weiterhin souverän.
        // **User-Revision 2026-04-22 (Revert)**: Card wieder auf die
        // ursprüngliche Größe zurückgesetzt (17 pt vertikal).
        .padding(.vertical, 17)
        .appSetupCardBackground(cornerRadius: AppLayout.largeCardCornerRadius)
    }


    /// Card zur Auswahl, wie viele richtige Antworten hintereinander nötig
    /// sind, bis eine Karte aus dem Stapel fällt (1x / 2x / 3x / 4x).
    /// **User-Revision 2026-04-22**: „4x Intensiv" ergänzt — alle vier
    /// Optionen liegen nebeneinander in einer Reihe. Button-Breite wird
    /// automatisch auf 1/4 der Card verteilt, `spacing: 6` bleibt.
    /// Platzierung: direkt unter `flashcardCountLimitCard` im Setup.
    var flashcardMasteryThresholdCard: some View {
        let labels: [(count: Int, label: String)] = [
            (1, "Schnell"),
            (2, "Normal"),
            (3, "Gründlich"),
            (4, "Intensiv")
        ]
        return VStack(alignment: .leading, spacing: 10) {
            flashcardSetupCardLabelLarge("Karte fällt raus nach")

            HStack(spacing: 6) {
                ForEach(labels, id: \.count) { entry in
                    let isSelected = setup.masteryThreshold == entry.count
                    Button {
                        setup.masteryThreshold = entry.count
                    } label: {
                        VStack(spacing: 2) {
                            // User-Request: 1x/2x/3x/4x und Schnell/Normal/
                            // Gründlich/Intensiv um 1 pt größer — zieht die
                            // Mechanik-Card optisch in eine Reihe mit
                            // dem größeren Label darüber.
                            Text("\(entry.count)x")
                                .font(.system(size: 19, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(entry.label)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(hex: "#888888"))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                        }
                        .frame(maxWidth: .infinity)
                        // **User-Revision 2026-04-22 (Revert)**: innere
                        // Button-Höhe zurück auf 56 pt (ursprüngliche Größe).
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
        // **User-Revision 2026-04-22 (Feinschliff)**: Card vertical
        // padding 12 → 8 pt, zusammen mit den reduzierten Button-Höhen
        // wirkt die Mechanik-Card jetzt kompakter.
        .padding(.vertical, 8)
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
        .appCardBackground(sectionStyle, intensity: AppTheme.CardIntensity.medium, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    /// Effektive Karten-Anzahl für die kommende Übung — berücksichtigt
    /// den Slider-Wert (oder „alle" wenn 0). Wird sowohl in der Hunger-Card
    /// als auch in der Geschätzte-Zeit-Tile verwendet.
    ///
    /// **User-Revision 2026-04-22**: On 200-Karten-Cap pro Session —
    /// derselbe Hard-Limit wie in `effectiveSelectedCardCount(for:)`.
    var flashcardEffectiveCardCount: Int {
        let rawMax = Swift.max(selectedStackCardCount, 0)
        guard rawMax > 0 else { return 0 }
        let cappedMax = Swift.min(rawMax, FlashcardsSetupController.maxCardsPerSession)
        return setup.selectedCardCount == 0
            ? cappedMax
            : Swift.min(setup.selectedCardCount, cappedMax)
    }

    // `flashcardHungerCard`, `flashcardStatsTrioCard` und
    // `flashcardSetupTrioTile` wurden mit dem Master-Session-Setup-Umbau
    // komplett entfernt:
    //   • das isolierte „Ich hab Hunger"-Würmchen-Messaging fällt weg
    //   • die Mini-Stats (Zeit-Schätzung, Streak-Multi, Streak-Tage) werden
    //     jetzt über die globale `SessionGamificationBar` über dem CTA
    //     abgedeckt — eine konsistente Preview für alle Setup-Screens
    //     statt modulspezifischer Trio-Kacheln.

    /// Custom Slider mit klassischem runden Handle in der Modul-Akzentfarbe.
    /// Dünner Track + Tap+Drag auf der gesamten Track-Fläche.
    @ViewBuilder
    func elumiCardCountSlider(
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1
    ) -> some View {
        // **User-Revision 2026-04-22**: Handle war mit 22 pt zu dominant
        // gegenüber dem restlichen Inhalt der Card — 22 → 16 pt. Track-
        // Höhe unverändert (6 pt), bleibt gut tappbar durch die
        // `contentShape(Rectangle())`-Gesture über die volle Track-
        // Fläche weiter unten.
        let handleSize: CGFloat = 16
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
