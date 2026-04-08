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

    var trainingSessionScreen: some View {
        VStack(spacing: 8) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Trainieren",
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

            sessionCard
                .padding(.horizontal, trainingSessionCardInset)
            actionButtons
                .padding(.horizontal, trainingSessionCardInset)
            responseCard
                .padding(.horizontal, trainingSessionCardInset)

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
                title: "Trainieren",
                subtitle: "",
                systemImage: "waveform.circle.fill"
            )

            Button {
                session.showingTrainingListPicker = true
            } label: {
                largeTrainingSelectionCard(
                    title: "Ausgewählte Liste(n)",
                    value: selectedTrainingList?.name ?? "Liste wählen"
                )
            }
            .buttonStyle(.plain)

            if isDictionaryTrainingSelected {
                dictionaryTrainingLevelCard
            }

            largeTrainingTypeCard

            Button {
                startTraining()
            } label: {
                Text("Los geht's!")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: canStartTraining ? AppTheme.Colors.cta : AppTheme.Colors.textDisabled))
            .disabled(!canStartTraining)

            if !canStartTraining {
                Text(startHintText)
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.bottom, AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $session.showingTrainingListPicker) {
            ListPickerSheet(
                style: sectionStyle,
                lists: availableTrainingLists,
                selectedListID: session.selectedTrainingListID ?? availableTrainingLists.first?.id ?? VocabularyListStore.dictionaryListID
            ) { pickedID in
                session.selectedTrainingListID = pickedID
                session.showingTrainingListPicker = false
            } onDelete: { deletedList in
                listStore.deleteCustomList(id: deletedList.id)
                if session.selectedTrainingListID == deletedList.id {
                    session.selectedTrainingListID = listStore.customLists.first?.id
                }
            }
        }
    }

    var body: some View {
        trainingRootContent
            .tint(trainingActionTint)
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
