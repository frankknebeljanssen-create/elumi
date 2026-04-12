import SwiftUI
import UIKit

extension FlashcardsView {
    func dismissToHome() {
        resetTransientState()
        sessionStore.clearTransientCustomDeckState()
        goHome()
    }

    func returnToFlashcardSetup() {
        resetTransientState()
        setup.prepareReturnToSetup(
            selectedAppDirection: selectedAppDirection,
            sessionStore: sessionStore
        )
    }

    func handleBackNavigation() {
        resetTransientState()
        sessionStore.clearTransientCustomDeckState()
        dismiss()
    }

    func applyLaunchContextIfNeeded() {
        setup.applyLaunchContextIfNeeded(
            launchContext,
            listStore: listStore,
            updateAppDirectionRaw: { selectedAppDirectionRaw = $0 },
            sessionStore: sessionStore
        )
    }

    func ensureStackSelectionValidity() {
        setup.ensureStackSelectionValidity(
            listStore: listStore,
            selectedAppDirection: selectedAppDirection,
            updateAppDirectionRaw: { selectedAppDirectionRaw = $0 }
        )
    }

    func syncSetupSelection() {
        setup.syncSetupSelection(
            selectedAppDirection: selectedAppDirection,
            sessionStore: sessionStore
        )
    }

    func refreshDictionaryStackListIfNeeded() {
        setup.refreshDictionaryStackListIfNeeded(
            launchContext: launchContext,
            selectedAppDirection: selectedAppDirection,
            listStore: listStore,
            updateAppDirectionRaw: { selectedAppDirectionRaw = $0 }
        )
    }

    func startFlashcardsFromSetup(autoplayPrompt: Bool = false) {
        resetTransientState()
        isCardCountFieldFocused = false
        guard setup.startFlashcardsFromSetup(
            listStore: listStore,
            selectedAppDirection: selectedAppDirection,
            sessionStore: sessionStore
        ) else { return }
        interaction.syncDisplayedCard(with: sessionStore)
        if autoplayPrompt {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 150_000_000)
                speakCurrentPrompt()
            }
        }
    }

    func toggleRecording() {
        interaction.toggleRecording(
            sessionStore: sessionStore,
            speechController: speechController,
            speaker: speaker,
            dismissTypedAnswerFocus: dismissTypedAnswerFocus
        )
    }

    func speakCurrentPrompt() {
        interaction.speakCurrentPrompt(
            speechController: speechController,
            speaker: speaker,
            areSoundsEnabled: isAudioModeEnabled
        )
    }

    func submitTypedAnswer() {
        interaction.submitTypedAnswer(
            sessionStore: sessionStore,
            speechController: speechController,
            speaker: speaker,
            feedbackPlayer: feedbackPlayer,
            dismissTypedAnswerFocus: dismissTypedAnswerFocus
        )
    }

    func skipCard() {
        interaction.skipCard(
            sessionStore: sessionStore,
            speechController: speechController,
            speaker: speaker,
            areSoundsEnabled: isAudioModeEnabled,
            dismissTypedAnswerFocus: dismissTypedAnswerFocus
        )
    }

    func restorePreviousFlashcard() {
        interaction.restorePreviousFlashcard(
            sessionStore: sessionStore,
            speechController: speechController,
            speaker: speaker,
            dismissTypedAnswerFocus: dismissTypedAnswerFocus
        )
    }

    func resetTransientState() {
        interaction.resetTransientState(
            speechController: speechController,
            speaker: speaker,
            dismissTypedAnswerFocus: dismissTypedAnswerFocus
        )
    }

    func handleFlashcardsAppear() {
        markFlashcardsOpenTiming("flashcards_view_on_appear")
        applyLaunchContextIfNeeded()
        ensureStackSelectionValidity()
        refreshDictionaryStackListIfNeeded()
        interaction.syncDisplayedCard(with: sessionStore)
        if setup.shouldAutoStartFromLaunch {
            setup.shouldAutoStartFromLaunch = false
            isWaitingToStart = true
            startFlashcardsFromSetup(autoplayPrompt: false)
        } else {
            syncSetupSelection()
        }
        if sessionStore.hasActiveSession == false {
            speechController.stopRecording()
            speechController.deactivateAudioSession()
        }
        endFlashcardsOpenTiming("flashcards_ready")
    }

    func dismissTypedAnswerFocus() {
        isTypedAnswerFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    func showFlashcardTypedAnswerField() {
        interaction.handleAudioModeChange(
            isEnabled: false,
            speechController: speechController,
            speaker: speaker
        )
        guard interaction.showTypedAnswerField(isSessionReady: isSessionReady) else { return }
        DispatchQueue.main.async {
            isTypedAnswerFocused = true
        }
    }

}
