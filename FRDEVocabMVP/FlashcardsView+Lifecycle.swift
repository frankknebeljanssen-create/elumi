import SwiftUI

extension FlashcardsView {
    var flashcardsLifecycleStage1: AnyView {
        AnyView(
            flashcardsChromeContent
                .onAppear {
                    handleFlashcardsAppear()
                }
                .onChange(of: sessionStore.selectedDeckID) { _, _ in
                    interaction.syncDisplayedCard(with: sessionStore)
                    resetTransientState()
                }
                .onChange(of: sessionStore.selectedDirection) { _, _ in
                    interaction.syncDisplayedCard(with: sessionStore)
                    resetTransientState()
                }
        )
    }

    var flashcardsLifecycleStage2: AnyView {
        AnyView(
            flashcardsLifecycleStage1
                .onChange(of: sessionStore.session) { _, _ in
                    interaction.syncDisplayedCard(with: sessionStore)
                }
                .onChange(of: selectedAppDirectionRaw) { _, _ in
                    setup.syncSetupSelection(
                        selectedAppDirection: selectedAppDirection,
                        sessionStore: sessionStore
                    )
                    refreshDictionaryStackListIfNeeded()
                }
                .onChange(of: setup.selectedStackDictionaryLearningLevel) { _, _ in
                    refreshDictionaryStackListIfNeeded()
                }
                .onChange(of: setup.isShowingSetup) { _, _ in
                    refreshDictionaryStackListIfNeeded()
                }
                .onChange(of: setup.showingStackComposer) { _, _ in
                    refreshDictionaryStackListIfNeeded()
                }
        )
    }

    var flashcardsLifecycleStage3: AnyView {
        AnyView(
            flashcardsLifecycleStage2
                .onChange(of: setup.selectedStackListIDs) { _, _ in
                    refreshDictionaryStackListIfNeeded()
                }
                .onChange(of: listStore.customLists) { _, _ in
                    ensureStackSelectionValidity()
                }
                .onChange(of: setup.customCardCountText) { _, _ in
                    setup.sanitizeCustomCardCountTextIfNeeded()
                }
                .onChange(of: speechController.isRecording) { wasRecording, isRecording in
                    interaction.handleRecordingStateChange(
                        wasRecording: wasRecording,
                        isRecording: isRecording,
                        sessionStore: sessionStore,
                        speechController: speechController,
                        speaker: speaker,
                        feedbackPlayer: feedbackPlayer,
                        dismissTypedAnswerFocus: { dismissTypedAnswerFocus() }
                    )
                }
        )
    }

    var flashcardsLifecycleContent: AnyView {
        AnyView(
            flashcardsLifecycleStage3
                .onChange(of: feedbackPlayer.areSoundsEnabled) { _, isEnabled in
                    interaction.handleAudioModeChange(
                        isEnabled: isEnabled,
                        speechController: speechController,
                        speaker: speaker
                    )
                }
                .onChange(of: isTypedAnswerFocused) { _, isFocused in
                    if isFocused {
                        interaction.handleAudioModeChange(
                            isEnabled: false,
                            speechController: speechController,
                            speaker: speaker
                        )
                    }
                }
                .onDisappear {
                    interaction.handleDisappear(
                        speechController: speechController,
                        speaker: speaker,
                        dismissTypedAnswerFocus: { dismissTypedAnswerFocus() }
                    )
                }
        )
    }
}
