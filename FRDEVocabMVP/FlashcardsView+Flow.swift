import SwiftUI
import UIKit

extension FlashcardsView {
    func dismissToHome() {
        resetTransientState()
        sessionStore.clearTransientCustomDeckState()
        goHome()
    }

    func returnToFlashcardSetup() {
        let cameFromPersonalDeck = sessionStore.activePersonalDeckID != nil
        print("🔙 returnToFlashcardSetup: cameFromPersonalDeck=\(cameFromPersonalDeck) activeID=\(String(describing: sessionStore.activePersonalDeckID))")
        syncPersonalDeckProgressIfNeeded()
        resetTransientState()

        // **Chain-Mode Back-Chevron (2026-05-02)** — im Chain-Mode
        // führt der Back-Chevron NICHT zur Listen-/Stack-Auswahl-
        // Card zurück (das verstößt gegen Setup-Skip-Spec), sondern
        // poppt die Modul-Route → User landet auf dem
        // `TrainingChainOverviewView`-Pre-Screen. Personal-Deck-Sync
        // + Transient-State-Cleanup laufen oben unverändert; die
        // explizite `clearTransientCustomDeckState()` parallel zu
        // `handleBackNavigation` (KK-Setup-Header-Pfad) räumt den
        // Custom-Deck-Setup-State, falls aktiv. Speech-Recording /
        // TTS / Resume-Snapshot werden via `handleFlashcardsDisappear`
        // beim Route-Pop automatisch gestoppt — kein expliziter
        // Cleanup hier nötig.
        if launchContext?.chainContext != nil {
            sessionStore.clearTransientCustomDeckState()
            dismiss()
            return
        }

        setup.prepareReturnToSetup(
            selectedAppDirection: selectedAppDirection,
            sessionStore: sessionStore
        )
        if cameFromPersonalDeck {
            // **User-Revision 2026-04-22**: Async-Push, damit der
            // Setup-Body-Switch zuerst durchläuft. Mit `+ 0.05 s`
            // Mini-Delay, damit SwiftUI die Setup-Render-Phase wirklich
            // abgeschlossen hat — sonst verschluckt die NavigationStack
            // die Push-Animation oder feuert sie auf einen falschen
            // Frame.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                print("🔙 push isShowingPersonalDecksScreen = true")
                isShowingPersonalDecksScreen = true
            }
        }
    }

    func handleBackNavigation() {
        // Ebenso beim Verlassen des Moduls komplett — letzter
        // Fortschritt des Personal-Decks muss persistent landen.
        syncPersonalDeckProgressIfNeeded()
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
        // **User-Revision 2026-04-22 (Bug-Fix Navigation)**: SwiftUI
        // feuert `.onAppear` auch beim Pop einer
        // NavigationDestination (Meine-Stapel-Subscreen). Wenn der
        // User aus Meine Stapel zurück kommt, sieht der Auto-Switch
        // unten eine aktive Session und wirft ihn rein — obwohl er
        // ins Setup zurück will. Wir markieren den ersten Appear und
        // führen Init-Logik (LaunchContext, AutoStart, Session-Resume)
        // NUR dann aus.
        let isFirstAppear = !hasHandledInitialFlashcardsAppear
        hasHandledInitialFlashcardsAppear = true

        if setup.selectedStackListIDs.isEmpty {
            setup.restoreSelectedStackListIDs()
        }
        if isFirstAppear {
            applyLaunchContextIfNeeded()
        }
        ensureStackSelectionValidity()
        refreshDictionaryStackListIfNeeded()
        interaction.syncDisplayedCard(with: sessionStore)

        if isFirstAppear {
            if setup.shouldAutoStartFromLaunch {
                setup.shouldAutoStartFromLaunch = false
                isWaitingToStart = true
                startFlashcardsFromSetup(autoplayPrompt: false)
            } else {
                syncSetupSelection()
                // Auto-Resume nur beim ersten Appear, NICHT bei jedem
                // Inner-Navigation-Pop.
                if setup.isShowingSetup, sessionStore.hasActiveSession, launchContext == nil {
                    setup.isShowingSetup = false
                }
            }
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
