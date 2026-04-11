import SwiftUI
import Combine

extension TrainingView {
    var trainingRootContent: some View {
        ZStack(alignment: .top) {
            Group {
                if session.isShowingSetup {
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
        case .articles: return "Artikel"
        case .verbs: return "Verben"
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
                returnToTrainingSetup()
            } label: {
                Label("Zurück zur Auswahl", systemImage: "arrow.left")
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

                    Spacer(minLength: AppTheme.Spacing.sm)

                    // Translation hint — pinned above footer like in article mode
                    if let item = session.currentTrainingItem {
                        let isFRtoDe = selectedAppDirection == .frenchToGerman || selectedAppDirection == .englishToGerman
                        let translationText = isFRtoDe ? item.french : item.german
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

            // List category buttons
            VStack(spacing: 8) {
                Text("Listen auswählen")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    listCategoryButton(
                        title: "📝 Meine Listen",
                        count: ownListCount,
                        category: .own
                    )
                    listCategoryButton(
                        title: "📚 Nach Niveau",
                        count: levelListCount,
                        category: .level
                    )
                }

                HStack(spacing: 8) {
                    listCategoryButton(
                        title: "🏷️ Nach Thema",
                        count: topicListCount,
                        category: .topic
                    )
                    listCategoryButton(
                        title: "📖 Komplett",
                        count: allInOneCount,
                        category: .all
                    )
                }

                if !trainingListCount.isEmpty {
                    Text(trainingListName + " · " + trainingListCount)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(trainingActionTint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 2)
                }
            }
            .padding(.bottom, AppTheme.Spacing.sm)

            // Direction is set on Home screen

            if launchContext?.preferredMode == nil {
                trainingModeCard
            }

            if isDictionaryTrainingSelected {
                dictionaryTrainingLevelCard
            }

            trainingBottomOptionCard

            Spacer(minLength: 0)

            if !canStartTraining {
                Text(startHintText)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Text("Los geht's!")
                .font(AppTheme.Typography.button)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppTheme.Layout.buttonHeight)
                .background(AppTheme.Colors.cta)
                .cornerRadius(AppTheme.Radius.md)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard canStartTraining else { return }
                    startTraining()
                }
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + 32)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(item: $listPickerCategory) { category in
            FlashcardStackComposerSheet(
                style: sectionStyle,
                lists: filteredLists(for: category),
                selectedListIDs: session.selectedTrainingListIDs,
                language: selectedAppDirection.sourceLanguage,
                cardTypeFilter: nil
            ) { updatedSelection in
                session.selectedTrainingListIDs = updatedSelection
                listPickerCategory = nil
            }
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
