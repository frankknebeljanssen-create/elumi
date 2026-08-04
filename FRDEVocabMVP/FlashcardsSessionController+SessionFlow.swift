import Foundation
import SwiftUI

extension FlashcardsSessionController {
    func syncDisplayedCard(with sessionStore: FlashcardSessionStore) {
        displayedFlashCard = sessionStore.currentCard?.card(for: sessionStore.selectedDirection)
        // **Peek-Protection**: Wechselt die Karte, verliert der Peek-
        // Flag seine Gültigkeit — der nächste Durchgang startet frisch.
        if let currentCardID = sessionStore.session?.currentCardID,
           peekedCurrentCardID != currentCardID {
            peekedCurrentCardID = nil
        } else if sessionStore.session?.currentCardID == nil {
            peekedCurrentCardID = nil
        }
    }

    func resetTransientState(
        speechController: SpeechController,
        speaker: Speaker,
        dismissTypedAnswerFocus: () -> Void,
        clearDisplayedCard: Bool = false
    ) {
        dismissTypedAnswerFocus()
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        flashcardHistory = []
        lastResult = nil
        showingSolution = false
        isFlashcardFlipped = false
        resetCardFlyOut()
        speaker.stop()
        speechController.stopRecording()
        speechController.transcript = ""
        speechController.recordError = nil
        typedAnswer = ""
        hideTypedAnswerField()
        if clearDisplayedCard {
            displayedFlashCard = nil
        }
    }

    func handleDisappear(
        speechController: SpeechController,
        speaker: Speaker,
        dismissTypedAnswerFocus: () -> Void
    ) {
        resetTransientState(
            speechController: speechController,
            speaker: speaker,
            dismissTypedAnswerFocus: dismissTypedAnswerFocus,
            clearDisplayedCard: true
        )
        speechController.deactivateAudioSession()
    }

    func handleAudioModeChange(
        isEnabled: Bool,
        speechController: SpeechController,
        speaker: Speaker
    ) {
        if !isEnabled {
            stopListeningForTyping(speechController: speechController, speaker: speaker)
        }
    }

    func scheduleNextPrompt(
        after delay: TimeInterval,
        sessionStore: FlashcardSessionStore,
        speechController: SpeechController,
        speaker: Speaker? = nil,
        areSoundsEnabled: Bool = false
    ) {
        cancelPendingFeedback()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.lastResult = nil
            self.showingSolution = false
            self.isFlashcardFlipped = false
            speechController.transcript = ""
            self.typedAnswer = ""
            self.hideTypedAnswerField()

            if sessionStore.session?.isCompleted == true {
                return
            }

            // **Stufe 4b-1 (2026-05-01)** — Soft-Cutoff-Force-Done für
            // den Chain-Timer. Wenn der User auf einer Chain-Step-
            // Session sitzt UND der Chain-Timer im
            // `TrainingChainStore` schon abgelaufen ist, schließen wir
            // die Karteikarten-Session HIER ab — nach kompletter Eval
            // der gerade getippten Karte (R7-Schutz: aktueller Submit
            // läuft komplett durch, dieser Pfad ist im
            // „natural-transition-zur-nächsten-Karte"-Punkt). Folge:
            // `flashcardCompletionCard` rendert, der Chain-aware
            // Done-CTA aus Stufe 3 zeigt „Weiter zu …" oder
            // „Training abschließen".
            //
            // **Singleton-Zugriff**: bewusst direkt
            // `TrainingChainStore.shared.timerExpired` gelesen, statt
            // den Store als Init-Param durchzureichen — der Controller
            // bleibt damit Chain-agnostic für Non-Chain-Sessions
            // (Default false, kein Effekt). Pattern matcht
            // `ProgressService.shared` etc. an anderen Stellen.
            // **Modal-Race-Fix 2026-05-02** — Modal hat Vorrang vor
            // Force-Done-Pre-Emption. Siehe
            // `TrainingView+SessionFlow.loadNextTrainingCard` für die
            // ausführliche Begründung.
            if TrainingChainStore.shared.timerExpired,
               !TrainingChainStore.shared.cutoffModalVisible,
               sessionStore.session != nil {
                sessionStore.markCurrentSessionDoneFromChainTimer()
                return
            }

            if let speaker, areSoundsEnabled {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    self.speakCurrentPrompt(
                        speechController: speechController,
                        speaker: speaker,
                        areSoundsEnabled: areSoundsEnabled
                    )
                }
            }
        }
        pendingFeedbackTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelPendingFeedback() {
        pendingFeedbackTask?.cancel()
        pendingFeedbackTask = nil
    }

    func resetCardFlyOut() {
        cardFlyOutOffset = 0
        cardFlyOutRotation = 0
        cardFlyOutOpacity = 1
    }

    func hideTypedAnswerField() {
        showingTypedAnswerInput = false
    }

    func stopListeningForTyping(
        speechController: SpeechController,
        speaker: Speaker
    ) {
        shouldEvaluateAfterStop = false
        if speechController.isRecording {
            speechController.stopRecording()
        }
        if speaker.isSpeaking {
            speaker.stop()
        }
    }

    func pushCurrentFlashcardToHistory(
        revealingSolution: Bool,
        sessionStore: FlashcardSessionStore
    ) {
        guard let sessionSnapshot = sessionStore.session,
              let currentFlashCard else { return }

        let historyResult: ScoreResult?
        if revealingSolution {
            historyResult = ScoreResult(label: "Lösung", detail: currentFlashCard.answer)
        } else {
            historyResult = nil
        }

        flashcardHistory.append(
            HistoryEntry(
                sessionState: sessionSnapshot,
                lastResult: historyResult,
                showingSolution: revealingSolution,
                isFlashcardFlipped: revealingSolution
            )
        )
    }

    func restorePreviousFlashcard(
        sessionStore: FlashcardSessionStore,
        speechController: SpeechController,
        speaker: Speaker,
        dismissTypedAnswerFocus: () -> Void
    ) {
        guard let historyEntry = flashcardHistory.popLast() else { return }

        dismissTypedAnswerFocus()
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        speaker.stop()
        speechController.stopRecording()
        speechController.transcript = ""
        speechController.recordError = nil
        typedAnswer = ""
        hideTypedAnswerField()

        sessionStore.restoreSession(historyEntry.sessionState)
        syncDisplayedCard(with: sessionStore)
        // Beim Zurück-Wischen IMMER mit der Frage-Seite anfangen — der
        // History-Zustand (showingSolution / isFlashcardFlipped) wird
        // bewusst verworfen, damit der User die vorherige Karte noch einmal
        // selbst beantworten kann statt direkt die Lösung zu sehen.
        lastResult = nil
        showingSolution = false
        isFlashcardFlipped = false
        resetCardFlyOut()
    }
}

struct HistoryEntry {
    let sessionState: FlashcardSessionState
    let lastResult: ScoreResult?
    let showingSolution: Bool
    let isFlashcardFlipped: Bool
}
