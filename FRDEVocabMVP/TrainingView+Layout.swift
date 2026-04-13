import SwiftUI
import Combine

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
            .padding(.bottom, AppTheme.Spacing.xs)

            if let countdown = speedCountdown {
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
                subtitle: "",
                systemImage: "waveform.circle.fill"
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
                    summaryText: trainingListCount.isEmpty ? "" : (trainingListName + " · " + trainingListCount),
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
                    summaryText: trainingListCount.isEmpty ? "" : (trainingListName + " · " + trainingListCount),
                    onSelectionChanged: { session.selectedTrainingListIDs = $0 }
                )
                verbformsSetupOptions
            } else {
                // Nomen, Artikel, Verben: Ausgewählte Listen card
                ListCategoryPickerView(
                    availableLists: availableTrainingLists,
                    selectedListIDs: session.selectedTrainingListIDs,
                    accent: trainingActionTint,
                    style: sectionStyle,
                    feedbackPlayer: feedbackPlayer,
                    summaryText: trainingListCount.isEmpty ? "" : (trainingListName + " · " + trainingListCount),
                    onSelectionChanged: { session.selectedTrainingListIDs = $0 }
                )

                // Verben: Auswahl Verben / Phrasen
                if isVerbMode {
                    verbContentTypeSelector
                }
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

            Text("Los geht's!")
                .font(AppTheme.Typography.button)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.Layout.buttonHeight)
                .background(isVerbformsMode ? AppTheme.Colors.cta : (canStartTraining ? AppTheme.Colors.cta : AppTheme.Colors.textDisabled))
                .cornerRadius(AppTheme.Radius.md)
                .contentShape(Rectangle())
                .onTapGesture {
                    if isVerbformsMode {
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
            // Mode selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Modus")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                HStack(spacing: 10) {
                    ForEach(VerbformsMode.allCases) { mode in
                        Button {
                            verbformsSession.mode = mode
                        } label: {
                            Text(mode.rawValue)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: 44)
                                .foregroundStyle(verbformsSession.mode == mode ? .white : AppTheme.Colors.textPrimary)
                                .background(verbformsSession.mode == mode ? trainingActionTint : AppTheme.Colors.secondarySurface)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .appCardBackground(sectionStyle, intensity: 0.09, cornerRadius: AppLayout.largeCardCornerRadius)

            // Tense selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Zeitform")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)], spacing: 8) {
                    ForEach(VerbformsTense.allCases) { tense in
                        Button {
                            let hasTenseData = verbformsSession.availableTenses.contains(tense)
                            guard hasTenseData else { return }
                            if verbformsSession.selectedTenses.contains(tense) {
                                if verbformsSession.selectedTenses.count > 1 {
                                    verbformsSession.selectedTenses.remove(tense)
                                }
                            } else {
                                verbformsSession.selectedTenses.insert(tense)
                            }
                        } label: {
                            let hasTenseData = verbformsSession.availableTenses.contains(tense)
                            VStack(spacing: 2) {
                                Text(hasTenseData ? tense.rawValue : "demnächst")
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                            }
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .foregroundStyle(
                                verbformsSession.selectedTenses.contains(tense)
                                    ? .white
                                    : (tense.isAvailable ? AppTheme.Colors.textPrimary : AppTheme.Colors.textSecondary)
                            )
                            .background(
                                verbformsSession.selectedTenses.contains(tense)
                                    ? trainingActionTint
                                    : (tense.isAvailable ? AppTheme.Colors.surface : AppTheme.Colors.surface.opacity(0.6))
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(
                                        verbformsSession.selectedTenses.contains(tense)
                                            ? trainingActionTint
                                            : AppTheme.Colors.border,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(!tense.isAvailable)
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

                if let question = verbformsSession.currentQuestion {
                    verbformsQuestionContent(question: question)
                }
            } else {
                // Normal Progress
                HStack {
                    Text(verbformsSession.progressText)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(trainingActionTint)
                    Spacer()
                    Text("\(verbformsSession.score) richtig")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .padding(.horizontal, 4)

                if let question = verbformsSession.currentQuestion {
                    verbformsQuestionContent(question: question)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + 32)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Colors.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func verbformsQuestionContent(question: VerbformsQuestion) -> some View {
        // Verb card
        VStack(spacing: 6) {
            Text(question.infinitive)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
            if !question.translation.isEmpty {
                Text(question.translation)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }
            HStack(spacing: 8) {
                Text(question.tense.rawValue)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(AppTheme.Colors.secondarySurface)
                    .clipShape(Capsule())
                Text("·")
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                Text(question.person.promptLabel)
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(trainingActionTint)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)

        // Answer area
        if verbformsSession.mode == .multipleChoice {
            verbformsMCGrid(question: question)
        } else {
            verbformsTypingInput(question: question)
        }

        // Next button (after correct answer, not in speed round) — centered in remaining space
        if verbformsSession.isLocked, !verbformsSession.isSpeedRound {
            Spacer(minLength: 8)
            Button {
                verbformsSession.next()
            } label: {
                Text("Weiter")
                    .font(AppTheme.Typography.button)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 96)
                    .background(trainingActionTint)
                    .cornerRadius(AppTheme.Radius.md)
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
        }
    }

    @ViewBuilder
    private func verbformsMCGrid(question: VerbformsQuestion) -> some View {
        let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(verbformsSession.currentOptions.enumerated()), id: \.offset) { _, option in
                let isTappable = !verbformsSession.isLocked && !verbformsSession.wrongOptions.contains(option.lowercased())
                Button {
                    guard isTappable else { return }
                    feedbackPlayer.playTabSwitch()
                    verbformsSession.submitMC(option)
                    if option.lowercased() == question.correctAnswer.lowercased() {
                        feedbackPlayer.playStudySuccess()
                    } else {
                        feedbackPlayer.playStudyError()
                    }
                } label: {
                    Text(option)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 48)
                        .foregroundStyle(verbformsMCForeground(option, question: question))
                        .background(verbformsMCBackground(option, question: question))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func verbformsMCForeground(_ option: String, question: VerbformsQuestion) -> Color {
        .white
    }

    private func verbformsMCBackground(_ option: String, question: VerbformsQuestion) -> Color {
        let lower = option.lowercased()
        if verbformsSession.wrongOptions.contains(lower) { return Color(red: 0.95, green: 0.55, blue: 0.15) }
        if verbformsSession.isLocked, lower == question.correctAnswer.lowercased() { return AppTheme.Colors.success }
        return trainingActionTint
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
                    Text("Richtig!")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.success)
                case .incorrect(let correctAnswer):
                    VStack(spacing: 4) {
                        Text("Falsch")
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(red: 0.9, green: 0.3, blue: 0.15))
                        Text("Richtig: \(correctAnswer)")
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

    func loadVerbformsAvailableTenses() {
        let inflections = VerbformsEngine.loadAllInflections(limit: 100)
        verbformsSession.availableTenses = VerbformsEngine.availableTenses(in: inflections)
        // Auto-select only available tenses
        verbformsSession.selectedTenses = verbformsSession.selectedTenses.intersection(verbformsSession.availableTenses)
        if verbformsSession.selectedTenses.isEmpty, let first = verbformsSession.availableTenses.first {
            verbformsSession.selectedTenses = [first]
        }
    }

    func startVerbformsTraining() {
        let allInflections = VerbformsEngine.loadAllInflections(limit: 200)
        guard !allInflections.isEmpty else { return }

        verbformsSession.availableTenses = VerbformsEngine.availableTenses(in: allInflections)
        let isSpeed = session.isSpeedRound
        let questionCount = isSpeed ? 5 : 20
        let selectedTenses = verbformsSession.selectedTenses.intersection(verbformsSession.availableTenses)
        guard !selectedTenses.isEmpty else { return }
        let questions = VerbformsEngine.generateQuestions(from: allInflections, tenses: selectedTenses, count: questionCount)
        guard !questions.isEmpty else { return }

        feedbackPlayer.playTabSwitch()

        if isSpeed {
            // Show session screen with 3-2-1 countdown overlay, then start timer
            verbformsSession.start(with: questions, inflections: allInflections, speedRound: true)
            verbformsCountdown = 3
            feedbackPlayer.playToggle()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                verbformsCountdown = 2
                feedbackPlayer.playToggle()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                    verbformsCountdown = 1
                    feedbackPlayer.playToggle()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [self] in
                        verbformsCountdown = nil
                        feedbackPlayer.playLaunch()
                        verbformsSession.startSpeedRoundTimer(feedbackPlayer: feedbackPlayer)
                    }
                }
            }
        } else {
            verbformsSession.start(with: questions, inflections: allInflections, speedRound: false)
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
