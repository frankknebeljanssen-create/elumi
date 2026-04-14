import SwiftUI
import Combine

/// Tracking-PreferenceKeys für das Drag-and-Drop-Matching im Verbformen-Modul.
/// Dieselbe Mechanik wie im Quiz-Matching: Chips/Targets melden ihre Frames
/// im gemeinsamen `coordinateSpace`, der Drag-State berechnet daraus den Hover-Treffer.
struct VerbformsPronounFramePreferenceKey: PreferenceKey {
    static var defaultValue: [VerbformsPerson: CGRect] = [:]
    static func reduce(value: inout [VerbformsPerson: CGRect], nextValue: () -> [VerbformsPerson: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct VerbformsFormFramePreferenceKey: PreferenceKey {
    static var defaultValue: [VerbformsPerson: CGRect] = [:]
    static func reduce(value: inout [VerbformsPerson: CGRect], nextValue: () -> [VerbformsPerson: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

extension TrainingView {
    var trainingRootContent: some View {
        ZStack(alignment: .top) {
            Group {
                if isVerbformsMode {
                    if verbformsSession.isActive || verbformsCountdown != nil {
                        verbformsSessionScreen
                    } else if verbformsSession.isFinished {
                        verbformsResultScreen
                    } else {
                        trainingSetupScreen
                    }
                } else if session.isShowingSetup {
                    trainingSetupScreen
                } else {
                    trainingSessionScreen
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, AppLayout.contentTopPadding)
            .padding(.bottom, usesGlobalChrome ? 0 : AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.lg)
        }
    }

    private var sessionHeaderTitle: String {
        switch session.trainingMode {
        case .vocabulary: return "Vokabeln"
        case .nouns: return "Nomen"
        case .articles: return "Artikel"
        case .verbs: return "Verben"
        case .verbforms: return "Verbformen"
        }
    }

    var trainingSessionScreen: some View {
        VStack(spacing: 8) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: sessionHeaderTitle,
                subtitle: "",
                systemImage: "waveform.circle.fill"
            )

            Button {
                dismissTraining()
            } label: {
                Label("Zurück", systemImage: "arrow.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppSecondaryButtonStyle(tint: trainingActionTint))
            .padding(.horizontal, trainingSessionCardInset)

            // Progress counter for Nomen, Artikel, Verben
            if !session.isSpeedRound, (isNounMode || isArticleMode || isVerbMode), session.hasStartedTraining, !session.isShowingRoundComplete {
                let solved = session.preparedTrainingItems.count - session.remainingTrainingItems.count
                let total = session.preparedTrainingItems.count
                HStack {
                    Text("\(solved) / \(total)")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(trainingActionTint)
                    Spacer()
                    Text("Runde \(session.completedRound)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(.horizontal, trainingSessionCardInset + 4)
            }

            if session.isShowingRoundComplete {
                roundCompleteView
            } else if let countdown = speedCountdown {
                // 3-2-1 Countdown overlay
                Text("\(countdown)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.warning)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.scale.combined(with: .opacity))
            } else {
                if session.isSpeedRound, session.hasStartedTraining {
                    speedRoundTimerBar
                        .padding(.horizontal, trainingSessionCardInset)
                }

                sessionCard
                    .padding(.horizontal, trainingSessionCardInset)
                if isArticleMode {
                    articleButtons
                        .padding(.horizontal, trainingSessionCardInset)
                } else if isVerbMode {
                    Spacer().frame(height: AppTheme.Spacing.xs)
                    verbMCCard
                        .padding(.horizontal, trainingSessionCardInset)

                    // Translation hint
                    if let item = session.currentTrainingItem {
                        let isFRtoDe = selectedAppDirection == .frenchToGerman || selectedAppDirection == .englishToGerman
                        let translationText = isFRtoDe ? item.german : item.french
                        Button {
                            showingVerbTranslation.toggle()
                        } label: {
                            if showingVerbTranslation {
                                Text(translationText)
                                    .font(.system(size: 20, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 52)
                                    .background(AppTheme.Colors.secondarySurface)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                            } else {
                                Label("Übersetzung", systemImage: "eye")
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 52)
                                    .background(AppTheme.Colors.secondarySurface)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, trainingSessionCardInset)
                    }
                } else {
                    actionButtons
                        .padding(.horizontal, trainingSessionCardInset)
                    responseCard
                        .padding(.horizontal, trainingSessionCardInset)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + AppTheme.Spacing.lg)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var trainingSetupScreen: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: sessionHeaderTitle,
                subtitle: isVerbformsMode ? "Konjugationen üben" : "",
                systemImage: isVerbformsMode
                    ? "text.line.first.and.arrowtriangle.forward"
                    : "waveform.circle.fill"
            )

            Button {
                dismiss()
            } label: {
                Label("Zurück", systemImage: "arrow.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppSecondaryButtonStyle(tint: trainingActionTint))

            if session.trainingMode == .vocabulary {
                // Vokabeln: 4 category cards
                Text("Was möchtest Du trainieren?")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .padding(.top, 4)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    trainingCategoryCard(
                        category: .topic,
                        title: "Nach Themen",
                        systemImage: "tag.fill",
                        subtitle: "\(topicListCount) Listen"
                    )
                    trainingCategoryCard(
                        category: .level,
                        title: "Nach Niveau",
                        systemImage: "chart.bar.fill",
                        subtitle: "\(levelListCount) Listen"
                    )
                    trainingCategoryCard(
                        category: .own,
                        title: "Eigene Listen",
                        systemImage: "person.fill",
                        subtitle: "\(ownListCount) Listen"
                    )
                    trainingCategoryCard(
                        category: .all,
                        title: "Ganzes Wörterbuch",
                        systemImage: "book.fill",
                        subtitle: "Alle Einträge"
                    )
                }

                // Ausgewählte Listen card below
                ListCategoryPickerView(
                    availableLists: availableTrainingLists,
                    selectedListIDs: session.selectedTrainingListIDs,
                    accent: trainingActionTint,
                    style: sectionStyle,
                    feedbackPlayer: feedbackPlayer,
                    summaryText: trainingListCount.isEmpty ? "" : (trainingListName + " \u{00B7} " + trainingListCount),
                    itemLabel: "Eintr\u{00E4}ge",
                    onSelectionChanged: { session.selectedTrainingListIDs = $0 }
                )
            } else if session.trainingMode == .verbforms {
                // Verbformen: Listen oben, dann Modus + Zeitform
                ListCategoryPickerView(
                    availableLists: availableTrainingLists,
                    selectedListIDs: session.selectedTrainingListIDs,
                    accent: trainingActionTint,
                    style: sectionStyle,
                    feedbackPlayer: feedbackPlayer,
                    summaryText: trainingListCount.isEmpty ? "" : (trainingListName + " \u{00B7} " + trainingListCount),
                    itemLabel: "Verben",
                    onSelectionChanged: { session.selectedTrainingListIDs = $0 }
                )
                verbformsSetupOptions
            } else {
                // Nomen, Artikel, Verben: Ausgewählte Listen card
                // (Verben trainiert NUR Infinitive → kein Wörter/Phrasen-Selector nötig)
                ListCategoryPickerView(
                    availableLists: availableTrainingLists,
                    selectedListIDs: session.selectedTrainingListIDs,
                    accent: trainingActionTint,
                    style: sectionStyle,
                    feedbackPlayer: feedbackPlayer,
                    summaryText: trainingListCount.isEmpty ? "" : (trainingListName + " \u{00B7} " + trainingListCount),
                    itemLabel: trainingItemLabel,
                    onSelectionChanged: { session.selectedTrainingListIDs = $0 }
                )
            }

            if isDictionaryTrainingSelected {
                dictionaryTrainingLevelCard
            }

            speedRoundToggle

            Spacer(minLength: 0)

            if !canStartTraining && !isVerbformsMode {
                Text(startHintText)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            // Verbformen: spezifischer Hint, wenn die Analyse der Listen keine
            // Verben ergeben hat — deckt sich mit der Datenquelle für
            // „Verben trainieren" (gleiche Verb-Basis).
            if isVerbformsMode && !verbformsCanStart {
                Text(verbformsStartHint)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            Text("Los geht's!")
                .font(AppTheme.Typography.button)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.Layout.buttonHeight)
                .background(
                    isVerbformsMode
                        ? (verbformsCanStart ? AppTheme.Colors.cta : AppTheme.Colors.textDisabled)
                        : (canStartTraining ? AppTheme.Colors.cta : AppTheme.Colors.textDisabled)
                )
                .cornerRadius(AppTheme.Radius.md)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isVerbformsMode {
                        guard verbformsCanStart else { return }
                        startVerbformsTraining()
                    } else {
                        guard canStartTraining else { return }
                        startTraining()
                    }
                }
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + 32)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $listPickerCategory) { category in
            TrainingCategoryListSheet(
                category: category,
                style: sectionStyle,
                lists: filteredLists(for: category),
                selectedListIDs: session.selectedTrainingListIDs,
                onSelectionChanged: { updatedSelection in
                    session.selectedTrainingListIDs = updatedSelection
                    listPickerCategory = nil
                }
            )
        }
    }

    @ViewBuilder
    private func trainingCategoryCard(
        category: ListPickerCategory,
        title: String,
        systemImage: String,
        subtitle: String
    ) -> some View {
        Button {
            feedbackPlayer.playTabSwitch()
            if category == .all {
                if let allList = filteredLists(for: .all).first {
                    session.selectedTrainingListIDs = [allList.id]
                }
            } else {
                listPickerCategory = category
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(trainingActionTint)
                    .frame(height: 28)

                Text(title)
                    .font(.system(size: 15, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .fill(AppTheme.Colors.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                            .fill(trainingActionTint.opacity(0.06))
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.largeCardCornerRadius, style: .continuous)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Round Complete View

    private var roundCompleteView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "star.circle.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(AppTheme.Colors.warning)

            Text("Runde \(session.completedRound) geschafft!")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("\(session.preparedTrainingItems.count) \(trainingItemLabel) durchgearbeitet")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Spacer()

            Button {
                feedbackPlayer.playStudySuccess()
                session.continueNextRound()
            } label: {
                Text("Weiter \u{2192} Runde \(session.completedRound + 1)")
                    .font(AppTheme.Typography.button)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(AppTheme.Colors.cta)
                    .cornerRadius(AppTheme.Radius.md)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, trainingSessionCardInset)

            Button {
                dismissTraining()
            } label: {
                Label("Zur\u{00FC}ck", systemImage: "arrow.left")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(AppSecondaryButtonStyle(tint: AppTheme.Colors.textSecondary))
            .padding(.horizontal, trainingSessionCardInset)

            Spacer().frame(height: 8)
        }
        .onAppear {
            feedbackPlayer.playStudyAchievement()
        }
    }

    // MARK: - Verb Content Type Selector (Verben / Phrasen)

    private var verbContentTypeSelector: some View {
        HStack(spacing: 10) {
            ForEach([CardType.words, CardType.phrases], id: \.self) { type in
                Button {
                    session.cardType = type
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: type == .words ? "textformat" : "text.quote")
                            .font(.system(size: 16, weight: .bold))
                        Text(type == .words ? "Verben" : "Phrasen")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .foregroundStyle(session.cardType == type ? .white : AppTheme.Colors.textPrimary)
                    .background(session.cardType == type ? trainingActionTint : AppTheme.Colors.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(session.cardType == type ? trainingActionTint : AppTheme.Colors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Verbformen Setup Options

    private var verbformsSetupOptions: some View {
        VStack(spacing: 12) {
            // Hinweis: Modus-Toggle (Auswählen/Tippen) wurde entfernt.
            // Verbformen läuft jetzt ausschließlich im Drag-&-Drop-Modus.

            // Tense selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Zeitform")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(VerbformsTense.allCases) { tense in
                        let isActive = tense.isAvailable   // aktuell nur Präsens
                        let isSelected = verbformsSession.selectedTenses.contains(tense)
                        Button {
                            guard isActive else { return }
                            if isSelected {
                                if verbformsSession.selectedTenses.count > 1 {
                                    verbformsSession.selectedTenses.remove(tense)
                                }
                            } else {
                                verbformsSession.selectedTenses.insert(tense)
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(tense.rawValue)
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                if !isActive {
                                    Text("demnächst")
                                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        .foregroundStyle(AppTheme.Colors.textSecondary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 56)
                            .foregroundStyle(
                                isSelected
                                    ? .white
                                    : (isActive ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                            )
                            .background(
                                isSelected
                                    ? trainingActionTint
                                    : (isActive ? AppTheme.Colors.surface : AppTheme.Colors.surface.opacity(0.4))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        isSelected
                                            ? trainingActionTint
                                            : AppTheme.Colors.border.opacity(isActive ? 1.0 : 0.4),
                                        lineWidth: 1
                                    )
                            )
                            .opacity(isActive ? 1.0 : 0.45)
                        }
                        .buttonStyle(.plain)
                        .disabled(!isActive)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .appCardBackground(sectionStyle, intensity: 0.09, cornerRadius: AppLayout.largeCardCornerRadius)
        }
    }

    // MARK: - Verbformen Session Screen

    var verbformsSessionScreen: some View {
        VStack(spacing: 12) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Verbformen",
                subtitle: "",
                systemImage: "text.line.first.and.arrowtriangle.forward"
            )

            Button {
                verbformsSession.reset()
                verbformsCountdown = nil
            } label: {
                Label("Zurück", systemImage: "arrow.left")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppSecondaryButtonStyle(tint: trainingActionTint))

            if let countdown = verbformsCountdown {
                // 3-2-1 Countdown
                Spacer()
                Text("\(countdown)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(trainingActionTint)
                    .transition(.scale.combined(with: .opacity))
                Spacer()
            } else if verbformsSession.isSpeedRound {
                // Speed Round Timer
                verbformsSpeedRoundBar
                verbformsActiveContent
            } else if verbformsSession.isShowingRoundComplete {
                // Runde abgeschlossen → Gratulation + Weitermachen / Fertig
                verbformsRoundCompleteView
            } else {
                // Normal Progress inkl. Runden-Zähler
                HStack {
                    Text(verbformsSession.progressText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(trainingActionTint)
                    Spacer()
                    Text("Runde \(verbformsSession.completedRound)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Text("·")
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                    Text("\(verbformsSession.score) richtig")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 4)
                verbformsActiveContent
            }

            Spacer(minLength: 0)

            // Persistenter Weiter-Button — sitzt zwischen Cards und Footer.
            // Nur sichtbar, wenn alle 6 Pronomen-Form-Paare einer Runde sitzen.
            if verbformsSession.isMatchingRoundComplete,
               !verbformsSession.isSpeedRound,
               !verbformsSession.isShowingRoundComplete,
               verbformsCountdown == nil {
                Button {
                    feedbackPlayer.playStudySuccess()
                    verbformsSession.next()
                } label: {
                    Text("Weiter")
                        .font(AppTheme.Typography.button)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 56)
                        .background(AppTheme.Colors.cta)
                        .cornerRadius(AppTheme.Radius.md)
                }
                .buttonStyle(.plain)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + 16)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Colors.background.ignoresSafeArea())
    }

    /// Zeigt je nach Modus das Matching-Grid (Drag&Drop) oder den Typing-Input.
    @ViewBuilder
    var verbformsActiveContent: some View {
        if verbformsSession.mode == .multipleChoice,
           let round = verbformsSession.currentMatching {
            verbformsMatchingContent(round: round)
        } else if let question = verbformsSession.currentQuestion {
            verbformsTypingQuestionContent(question: question)
        }
    }

    // MARK: - Drag & Drop Matching (Auswählen-Modus)

    /// Einheitliche Farbe für alle 6 Pronomen-Chips — das Verbformen-Purple
    /// des Moduls. Keine Variationen, damit keine Positions-/Farb-Hints
    /// auf die Lösung entstehen.
    static let verbformsPronounColor = Color(hue: 0.72, saturation: 0.55, brightness: 0.78)

    /// Einheitliche Farbe für alle 6 Form-Karten — ein sattes Blau.
    /// Absichtlich NICHT grün (= richtig) und NICHT orange (= falsch), damit
    /// die Feedback-Farben eindeutig bleiben. Klar vom Purple unterscheidbar.
    static let verbformsFormColor = Color(hue: 0.58, saturation: 0.55, brightness: 0.80)

    /// Aktuell vom DragGesture überfahrene Form-Karte (für Hover-Highlight).
    /// Wird live während des Drag-Updates berechnet — ohne das Quiz-Pattern
    /// nutzt SwiftUI's `.draggable` einen Long-Press, der hier nicht erwünscht ist.
    func verbformsHoveredFormPerson(for pronoun: VerbformsPerson) -> VerbformsPerson? {
        guard let pronounFrame = verbformsPronounFrames[pronoun] else { return nil }
        let dragged = CGPoint(
            x: pronounFrame.midX + verbformsDragOffset.width,
            y: pronounFrame.midY + verbformsDragOffset.height
        )
        return verbformsFormFrames.first(where: { person, frame in
            !verbformsSession.matchedPersons.contains(person) && frame.contains(dragged)
        })?.key
    }

    /// Beendet eine Drag-Geste: prüft welche Form-Karte unter dem Cursor liegt
    /// und ruft `dropPronoun` im Session-Controller auf. Setzt Drag-State zurück.
    func verbformsFinishDrag(for pronoun: VerbformsPerson) {
        let target = verbformsHoveredFormPerson(for: pronoun)
        if let target {
            let correct = verbformsSession.dropPronoun(pronoun, onForm: target)
            if correct {
                feedbackPlayer.playStudySuccess()
            } else {
                feedbackPlayer.playStudyError()
            }
        }
        // Snap zurück (egal ob richtig oder falsch — bei richtig wird der Chip
        // ohnehin ausgeblendet, bei falsch springt er optisch in seine Grid-Position)
        withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
            verbformsDragOffset = .zero
        }
        verbformsDraggingPronoun = nil
        verbformsHoveredForm = nil
    }

    @ViewBuilder
    private func verbformsMatchingContent(round: VerbformsMatchingRound) -> some View {
        // Fragekarte: Infinitiv + Tempus + gefragte Form („1. Person Plural" etc.)
        VStack(spacing: 8) {
            Text(round.infinitive)
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            if !round.translation.isEmpty {
                Text("(\(round.translation))")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            Text(round.tense.rawValue)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(AppTheme.Colors.secondarySurface)
                .clipShape(Capsule())

            // Gefragte Person als zentrale „Fragestellung" — Font 17pt
            // (2pt größer als die vorige Variante), kräftig in Akzentfarbe.
            if let nextPerson = verbformsSession.nextTargetPerson {
                Text(nextPerson.promptLabel)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(trainingActionTint)
                    .padding(.top, 2)
            } else {
                Text("Alle Paare gefunden!")
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.success)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)

        // Extra Raum zwischen Fragekarte und Grids
        Spacer().frame(height: 10)

        let pronounColumns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]

        // Drag/Drop-Container: gemeinsamer coordinateSpace + Frame-Tracking
        VStack(spacing: 6) {
            // Draggable pronouns (2×3) in gemischter Reihenfolge
            LazyVGrid(columns: pronounColumns, spacing: 10) {
                ForEach(verbformsSession.shuffledPronouns, id: \.self) { person in
                    verbformsPronounChip(person: person)
                }
            }

            // Drop-target forms (2×3) in separat gemischter Reihenfolge
            LazyVGrid(columns: pronounColumns, spacing: 10) {
                ForEach(verbformsSession.shuffledForms, id: \.self) { person in
                    verbformsFormTarget(person: person, round: round)
                }
            }
        }
        .coordinateSpace(name: "verbformsMatchingArea")
        .onPreferenceChange(VerbformsPronounFramePreferenceKey.self) { frames in
            verbformsPronounFrames = frames
        }
        .onPreferenceChange(VerbformsFormFramePreferenceKey.self) { frames in
            verbformsFormFrames = frames
        }

        // Weiter-Button bewusst NICHT hier — wird im verbformsSessionScreen
        // nach dem Spacer gerendert, damit er garantiert UNTEN sitzt
        // (zwischen Cards und Footer) und nicht von der Bottom-Bar überlagert wird.
    }

    // MARK: - Verbformen Round-Complete View

    private var verbformsRoundCompleteView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "star.circle.fill")
                .font(.system(size: 56, weight: .bold))
                .foregroundStyle(AppTheme.Colors.warning)

            Text("Runde \(verbformsSession.completedRound) geschafft!")
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("\(verbformsSession.score) von \(verbformsSession.totalAsked) Zuordnungen richtig")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)

            Spacer()

            Button {
                feedbackPlayer.playStudySuccess()
                verbformsSession.continueToNextRound()
            } label: {
                Text("Weiter \u{2192} Runde \(verbformsSession.completedRound + 1)")
                    .font(AppTheme.Typography.button)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 56)
                    .background(AppTheme.Colors.cta)
                    .cornerRadius(AppTheme.Radius.md)
            }
            .buttonStyle(.plain)

            Button {
                verbformsSession.finishTraining()
            } label: {
                Label("Fertig", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
            }
            .buttonStyle(AppSecondaryButtonStyle(tint: AppTheme.Colors.textSecondary))

            Spacer().frame(height: 8)
        }
    }

    /// Pronomen-Chip als Drag-Source — manuelle DragGesture (kein Long-Press),
    /// Quiz-Stil. Beim Drag-Update wird der Hover über Form-Karten live berechnet,
    /// beim Drag-Ende erfolgt Drop-Validation via `verbformsFinishDrag`.
    @ViewBuilder
    private func verbformsPronounChip(person: VerbformsPerson) -> some View {
        let isUsed = verbformsSession.usedPronouns.contains(person)
        let tint = Self.verbformsPronounColor
        let isDragging = verbformsDraggingPronoun == person

        Text(person.label)
            .font(.system(size: 16, weight: .bold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .foregroundStyle(.white)
            .background(tint)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .contentShape(Rectangle())
            .opacity(isUsed ? 0.0 : 1.0)
            .scaleEffect(isDragging ? 1.05 : 1.0)
            .shadow(color: isDragging ? tint.opacity(0.5) : .clear,
                    radius: isDragging ? 12 : 0, x: 0, y: isDragging ? 6 : 0)
            .offset(isDragging ? verbformsDragOffset : .zero)
            .zIndex(isDragging ? 100 : 0)
            .animation(.easeOut(duration: 0.25), value: isUsed)
            .allowsHitTesting(!isUsed)
            .background(
                GeometryReader { geo in
                    Color.clear.preference(
                        key: VerbformsPronounFramePreferenceKey.self,
                        value: [person: geo.frame(in: .named("verbformsMatchingArea"))]
                    )
                }
            )
            .gesture(
                DragGesture(coordinateSpace: .named("verbformsMatchingArea"))
                    .onChanged { value in
                        guard !isUsed else { return }
                        verbformsDraggingPronoun = person
                        verbformsDragOffset = value.translation
                        verbformsHoveredForm = verbformsHoveredFormPerson(for: person)
                    }
                    .onEnded { _ in
                        guard !isUsed else { return }
                        verbformsFinishDrag(for: person)
                    }
            )
    }

    /// Form-Karte als Drop-Target (manuelles Drop via Frame-Tracking, kein
    /// `.dropDestination`). Default-Farbe Blau, Match → grün, Wrong-Flash → orange.
    /// Wenn ein Pronomen-Drag die Karte überfährt, leichter Hover-Highlight.
    @ViewBuilder
    private func verbformsFormTarget(person: VerbformsPerson, round: VerbformsMatchingRound) -> some View {
        let form = round.forms[person] ?? "?"
        let isMatched = verbformsSession.matchedPersons.contains(person)
        let isFlashWrong = verbformsSession.wrongFlashTarget == person
        let isHovered = verbformsHoveredForm == person

        let bg: Color = {
            if isMatched { return AppTheme.Colors.success }
            if isFlashWrong { return Color(red: 0.95, green: 0.55, blue: 0.15) }
            return Self.verbformsFormColor
        }()

        VStack(spacing: 2) {
            if isMatched {
                Text(person.label)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text(form)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 56)
        .padding(.horizontal, 6)
        .foregroundStyle(.white)
        .background(bg)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                .stroke(isHovered ? Color.white : Color.white.opacity(0.25),
                        lineWidth: isHovered ? 2.5 : 1)
        )
        .scaleEffect(isHovered && !isMatched ? 1.05 : 1.0)
        .animation(.easeInOut(duration: 0.18), value: isMatched)
        .animation(.easeInOut(duration: 0.18), value: isFlashWrong)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .background(
            GeometryReader { geo in
                Color.clear.preference(
                    key: VerbformsFormFramePreferenceKey.self,
                    value: [person: geo.frame(in: .named("verbformsMatchingArea"))]
                )
            }
        )
    }

    // MARK: - Typing-Modus-Frage (alt: verbformsQuestionContent)

    @ViewBuilder
    private func verbformsTypingQuestionContent(question: VerbformsQuestion) -> some View {
        // Verb card — Infinitiv + Übersetzung + Person/Zeit
        VStack(spacing: 10) {
            Text(question.infinitive)
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            if !question.translation.isEmpty {
                Text("(\(question.translation))")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            HStack(spacing: 8) {
                Text(question.person.promptLabel)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(trainingActionTint)
                    .clipShape(Capsule())
                Text(question.tense.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppTheme.Colors.secondarySurface)
                    .clipShape(Capsule())
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)

        verbformsTypingInput(question: question)

        if verbformsSession.isLocked, !verbformsSession.isSpeedRound {
            Spacer(minLength: 8)
            Button {
                verbformsSession.next()
            } label: {
                Text("Weiter")
                    .font(AppTheme.Typography.button)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 48)
                    .background(trainingActionTint)
                    .cornerRadius(AppTheme.Radius.md)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private func verbformsTypingInput(question: VerbformsQuestion) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Text(question.person.label)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(trainingActionTint)
                    .frame(width: 70, alignment: .trailing)

                TextField("Verbform eingeben", text: $verbformsSession.typedAnswer)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .disabled(verbformsSession.isLocked)
            }

            if !verbformsSession.isLocked {
                Button {
                    verbformsSession.submitTyping()
                    if case .correct = verbformsSession.typingResult {
                        feedbackPlayer.playStudySuccess()
                    } else {
                        feedbackPlayer.playStudyError()
                    }
                } label: {
                    Text("Prüfen")
                        .font(AppTheme.Typography.button)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .background(verbformsSession.typedAnswer.isEmpty ? AppTheme.Colors.textDisabled : trainingActionTint)
                        .cornerRadius(AppTheme.Radius.md)
                }
                .buttonStyle(.plain)
                .disabled(verbformsSession.typedAnswer.isEmpty)
            }

            if let result = verbformsSession.typingResult {
                switch result {
                case .correct:
                    if let question = verbformsSession.currentQuestion {
                        // Volle Phrase als Bestätigung: „Richtig: je vais"
                        let full = VerbformsEngine.fullConjugation(
                            person: question.person,
                            form: question.correctAnswer
                        )
                        Text("Richtig: \(full)")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.success)
                    } else {
                        Text("Richtig!")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.success)
                    }
                case .incorrect(let correctAnswer):
                    // correctAnswer ist die kurze Form (z.B. „vais") — für
                    // das Feedback rekonstruieren wir die volle Phrase.
                    let fullCorrect: String = {
                        guard let question = verbformsSession.currentQuestion else {
                            return correctAnswer
                        }
                        return VerbformsEngine.fullConjugation(
                            person: question.person,
                            form: correctAnswer
                        )
                    }()
                    VStack(spacing: 4) {
                        Text("Fast.")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.9, green: 0.3, blue: 0.15))
                        Text("Die richtige Form ist: \(fullCorrect)")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }
            }
        }
        .padding(16)
        .appCardBackground(sectionStyle, intensity: 0.08, cornerRadius: AppLayout.largeCardCornerRadius)
    }

    // MARK: - Verbformen Result Screen

    var verbformsResultScreen: some View {
        VStack(spacing: 16) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Verbformen",
                subtitle: "",
                systemImage: "text.line.first.and.arrowtriangle.forward"
            )

            VStack(spacing: 12) {
                Text("Ergebnis")
                    .font(.system(size: 24, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                Text("\(verbformsSession.score) / \(verbformsSession.totalAsked)")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(trainingActionTint)

                let pct = verbformsSession.totalAsked > 0
                    ? Int(Double(verbformsSession.score) / Double(verbformsSession.totalAsked) * 100)
                    : 0
                Text("\(pct)% richtig")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
            .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)

            Button {
                verbformsSession.reset()
            } label: {
                Label("Zurück", systemImage: "arrow.left")
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: AppTheme.Layout.buttonHeight)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + 32)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Colors.background.ignoresSafeArea())
    }

    // MARK: - Verbformen Speed Round Bar

    private var verbformsSpeedRoundBar: some View {
        let isUrgent = verbformsSession.speedRoundTimeRemaining <= 10

        return VStack(spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(isUrgent ? AppTheme.Colors.error : AppTheme.Colors.warning)

                Text("\(verbformsSession.score)")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.success)
                Text("richtig")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Spacer()

                Text("\(verbformsSession.speedRoundTimeRemaining)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(isUrgent ? AppTheme.Colors.error : AppTheme.Colors.warning)
                    .monospacedDigit()
                    .scaleEffect(isUrgent ? 1.1 : 1.0)
                    .animation(.easeInOut(duration: 0.3), value: verbformsSession.speedRoundTimeRemaining)
                Text("s")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            GeometryReader { geo in
                let progress = CGFloat(verbformsSession.speedRoundTimeRemaining) / 45.0
                ZStack(alignment: .leading) {
                    Capsule().fill(AppTheme.Colors.textSecondary.opacity(0.2))
                    Capsule()
                        .fill(isUrgent ? AppTheme.Colors.error : AppTheme.Colors.warning)
                        .frame(width: max(0, geo.size.width * progress))
                        .animation(.linear(duration: 1.0), value: verbformsSession.speedRoundTimeRemaining)
                }
            }
            .frame(height: 10)
            .clipShape(Capsule())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .appCardBackground(sectionStyle, intensity: isUrgent ? 0.15 : 0.09)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(isUrgent ? AppTheme.Colors.error.opacity(verbformsSession.speedRoundTimeRemaining % 2 == 0 ? 0.8 : 0.3) : Color.clear, lineWidth: isUrgent ? 2 : 0)
        )
        .opacity(isUrgent ? (verbformsSession.speedRoundTimeRemaining % 2 == 0 ? 1.0 : 0.7) : 1.0)
        .animation(.easeInOut(duration: 0.4), value: verbformsSession.speedRoundTimeRemaining)
    }

    // MARK: - Verbformen Start

    /// Zentrale Lemma-Quelle für Verbformen — nutzt dieselbe Analyse-Pipeline wie
    /// „Verben trainieren" (FrenchListStatisticsAggregator.verbLemmas).
    /// Damit: gleiche Liste → gleiche Verb-Basis in beiden Modulen.
    /// Liefert Lemmas inkl. reflexiver Form („s'appeler", „se lever").
    func verbformsLemmasFromSelectedLists() -> [String] {
        let selectedIDs = session.selectedTrainingListIDs
        guard !selectedIDs.isEmpty else { return [] }
        let lists = availableTrainingLists.filter { selectedIDs.contains($0.id) }
        let items = lists.flatMap(\.items)
            .filter { $0.sourceLanguage == selectedAppDirection.sourceLanguage }
        let stats = FrenchListStatisticsAggregator.cachedStatistics(for: items)
        return stats.verbLemmas
    }

    /// Kann Verbformen mit der aktuellen Listen-Auswahl gestartet werden?
    var verbformsCanStart: Bool {
        let lemmas = verbformsLemmasFromSelectedLists()
        return !lemmas.isEmpty && !verbformsSession.availableTenses.isEmpty
    }

    /// Hilfetext, der erklärt, warum nicht gestartet werden kann.
    var verbformsStartHint: String {
        if session.selectedTrainingListIDs.isEmpty {
            return "Wähle zuerst eine Liste aus."
        }
        let lemmas = verbformsLemmasFromSelectedLists()
        if lemmas.isEmpty {
            return "In der gewählten Liste wurden keine Verben erkannt."
        }
        if verbformsSession.availableTenses.isEmpty {
            return "Für die erkannten Verben sind noch keine Konjugationsformen verfügbar."
        }
        return ""
    }

    func loadVerbformsAvailableTenses() {
        let lemmas = verbformsLemmasFromSelectedLists()
        let inflections = lemmas.isEmpty ? [] : VerbformsEngine.loadInflections(forLemmas: lemmas)
        verbformsSession.availableTenses = VerbformsEngine.availableTenses(in: inflections)
        // Auto-select only available tenses
        verbformsSession.selectedTenses = verbformsSession.selectedTenses.intersection(verbformsSession.availableTenses)
        if verbformsSession.selectedTenses.isEmpty, let first = verbformsSession.availableTenses.first {
            verbformsSession.selectedTenses = [first]
        }
    }

    func startVerbformsTraining() {
        // Verben aus den gewählten Listen holen (via Analyse-Pipeline, konsistent
        // mit „Verben trainieren"). Reflexive Lemmas werden im Engine-Lookup
        // auf ihre konjugierte Reflexiv-Form expandiert.
        let lemmas = verbformsLemmasFromSelectedLists()
        guard !lemmas.isEmpty else { return }

        let allInflections = VerbformsEngine.loadInflections(forLemmas: lemmas)
        guard !allInflections.isEmpty else { return }

        verbformsSession.availableTenses = VerbformsEngine.availableTenses(in: allInflections)
        let isSpeed = session.isSpeedRound
        let selectedTenses = verbformsSession.selectedTenses.intersection(verbformsSession.availableTenses)
        guard !selectedTenses.isEmpty else { return }

        // Modus-Weiche: MC-Modus = Drag&Drop-Matching-Runden (6 Paare pro Verb);
        // Typing-Modus = klassische Einzelfragen (1 Person pro Karte).
        let isMatching = (verbformsSession.mode == .multipleChoice)

        let matchingCount = isSpeed ? 10 : 8
        let questionCount = isSpeed ? 30 : 20

        let matchingRounds: [VerbformsMatchingRound]
        let questions: [VerbformsQuestion]
        if isMatching {
            matchingRounds = VerbformsEngine.generateMatchingRounds(
                from: allInflections, tenses: selectedTenses, count: matchingCount
            )
            questions = []
            guard !matchingRounds.isEmpty else { return }
        } else {
            matchingRounds = []
            questions = VerbformsEngine.generateQuestions(
                from: allInflections, tenses: selectedTenses, count: questionCount
            )
            guard !questions.isEmpty else { return }
        }

        feedbackPlayer.playTabSwitch()

        let startSession: () -> Void = {
            if isMatching {
                verbformsSession.startMatching(with: matchingRounds, inflections: allInflections, speedRound: isSpeed)
            } else {
                verbformsSession.start(with: questions, inflections: allInflections, speedRound: isSpeed)
            }
        }

        if isSpeed {
            startSession()
            verbformsCountdown = 3
            feedbackPlayer.playToggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                guard verbformsSession.isActive else { return }
                verbformsCountdown = 2
                feedbackPlayer.playToggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                    guard verbformsSession.isActive else { return }
                    verbformsCountdown = 1
                    feedbackPlayer.playToggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                        guard verbformsSession.isActive else { return }
                        verbformsCountdown = nil
                        feedbackPlayer.playLaunch()
                        verbformsSession.startSpeedRoundTimer(feedbackPlayer: feedbackPlayer)
                    }
                }
            }
        } else {
            startSession()
        }
    }

    var body: some View {
        trainingRootContent
            .appScreenBackground(sectionStyle)
            .dismissKeyboardOnTap()
            .toolbar(.hidden, for: .navigationBar)
            .appLocalChrome(enabled: !usesGlobalChrome) {
                AppTopBar(onBack: { dismiss() }, onInfo: openInfo)
                    .padding(.horizontal, AppLayout.screenPadding)
                    .padding(.top, AppLayout.topBarInsetTop)
            } bottomBar: {
                AppBottomBar(
                    feedbackPlayer: feedbackPlayer,
                    onHome: { dismissToHome() },
                    onFavorite: nil,
                    onScan: nil,
                    onSettings: { openSettings() }
                )
            }
            .onAppear {
                handleTrainingAppear()
                if isVerbformsMode { loadVerbformsAvailableTenses() }
            }
            .onDisappear {
                stopSpeedRoundTimer()
            }
            .onChange(of: session.direction) { _, _ in
                handleTrainingDirectionChange()
            }
            .onChange(of: session.cardType) { _, _ in
                handleTrainingCardTypeChange()
            }
            .onChange(of: session.selectedTrainingListID) { _, _ in
                handleTrainingListChange()
            }
            .onChange(of: session.selectedTrainingListIDs) { _, _ in
                // Verfügbare Zeiten für Verbformen hängen direkt an der gewählten Liste
                if isVerbformsMode { loadVerbformsAvailableTenses() }
            }
            .onChange(of: session.currentTrainingItem) { _, newItem in
                // Pragmatischer Fix gegen „Lösungswort fehlt in Runde 2":
                // Sobald sich die aktuelle Trainingskarte ändert, im Verben-MC
                // die Optionen (Lösung + frische Distraktoren) KOMPLETT neu
                // aufbauen und die Selection/Lock-State zurücksetzen.
                guard isVerbMode, newItem != nil else { return }
                verbMCSelected = nil
                verbMCLocked = false
                prepareVerbMCOptions()
            }
            .onChange(of: session.selectedDictionaryLearningLevel) { _, _ in
                handleDictionaryLearningLevelChange()
            }
            .onChange(of: selectedAppDirectionRaw) { _, _ in
                handleTrainingAppDirectionChange()
            }
            .onChange(of: listStore.customLists) { _, _ in
                handleTrainingCustomListsChange()
            }
            .onChange(of: session.showingTrainingListPicker) { _, _ in
                handleTrainingListPickerChange()
            }
            .onReceive(runtimeSpeechController?.$isRecording.removeDuplicates().eraseToAnyPublisher() ?? Just(false).eraseToAnyPublisher()) { isRecording in
                let was = wasRecording
                wasRecording = isRecording
                handleTrainingRecordingTransition(from: was, to: isRecording)
                handleTrainingRecordingPulseChange(isRecording)
            }
            .onReceive(runtimeSpeaker?.$isSpeaking.removeDuplicates().eraseToAnyPublisher() ?? Just(false).eraseToAnyPublisher()) { isSpeaking in
                let was = wasSpeakerSpeaking
                wasSpeakerSpeaking = isSpeaking
                handleTrainingSpeakerTransition(from: was, to: isSpeaking)
            }
            .onChange(of: feedbackPlayer.areSoundsEnabled) { _, isEnabled in
                handleAudioModeChange(isEnabled: isEnabled)
            }
            .onChange(of: typedAnswerFieldFocused) { _, isFocused in
                handleTypedAnswerFocusChange(isFocused)
            }
            .onDisappear {
                handleTrainingDisappear()
            }
    }
}
