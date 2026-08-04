import SwiftUI

extension TrainingView {
    func handleTrainingAppear() {
        triggerTrainingAudioPreparationIfNeeded()
        applyLaunchContextIfNeeded()
        // **Bug-Fix 2026-05-04 (Punkt 2 follow-up)** — siehe Doc in
        // `QuizView+Lifecycle.handleQuizAppear`. Restore unconditional,
        // damit Listen-Tab-Änderungen über Modul-Re-Opens propagieren.
        session.restoreSelectedListIDs()
        refreshDictionaryTrainingListIfNeeded()
        ensureTrainingSelectionValidity()
        ensureDirectionValidity()
        // Reset if not in active session
        if !session.hasStartedTraining {
            resetTrainingSession()
        }
        // Auto-start only from Import Completion (shouldAutoStart)
        // From Home: show setup screen with list selection
        //
        // **Stufe 4b-5 (2026-05-02)** — Verbformen läuft als
        // `TrainingMode.verbforms` durch dieselbe TrainingView, hat
        // aber einen eigenen Start-Pfad (`startVerbformsTraining`)
        // und braucht `verbformsSession.availableTenses` populiert.
        // Im Chain-Modus deshalb hier branchen: Verbformen-Versuch
        // sofort, falls nicht möglich (Tenses noch async im
        // Loading) → Retry läuft via
        // `handleVerbformsAvailableTensesChange()` aus dem
        // `.onChange(of: availableTenses.count)`-Handler in
        // `TrainingView+Layout.body`.
        if launchContext?.shouldAutoStart == true {
            if isVerbformsMode {
                tryAutoStartVerbformsIfReady()
            } else if !session.hasStartedTraining {
                startTraining()
            }
        }
    }

    /// **Stufe 4b-5 (2026-05-02)** — Wird vom
    /// `.onChange(of: verbformsSession.availableTenses.count)`-Handler
    /// in `TrainingView+Layout.body` getriggert. Retry-Pfad für
    /// Verbformen-Auto-Start nach asynchronem
    /// `loadVerbformsAvailableTenses`-Laden — analog zum Quiz-
    /// `handleQuizCandidatesChange`-Pattern.
    func handleVerbformsAvailableTensesChange() {
        guard launchContext?.shouldAutoStart == true,
              isVerbformsMode else {
            return
        }
        tryAutoStartVerbformsIfReady()
    }

    /// **Stufe 4b-5 (2026-05-02)** — gemeinsamer Auto-Start-Check für
    /// Verbformen. Idempotent über `verbformsSession.isActive` /
    /// `verbformsSession.isFinished`-Guards.
    ///
    /// **Race-Fix (2026-05-02 Commit 1)**: ursprünglich war der Guard
    /// `verbformsCanStart` (= `setupCanStartCached &&
    /// !availableTenses.isEmpty`). Beide Flags werden async populiert
    /// (`refreshSetupCardLemmas` über `Task.detached`-Pipeline, plus
    /// `loadVerbformsAvailableTenses`-Sync-Call mit eigener
    /// `cachedStatistics`-Latenz). Da nur ein onChange-Retry-Pfad
    /// existiert (`availableTenses.count`), konnte ein später
    /// kommendes `setupCanStartCached = true` keinen weiteren
    /// Auto-Start-Versuch triggern — Setup-Screen rendert dauerhaft
    /// statt direkt in die Verbformen-Aufgabe zu starten.
    ///
    /// Im Chain-Mode ist `setupCanStartCached` aber konzeptionell
    /// irrelevant — es ist der Setup-Card-CTA-Gate für den manuellen
    /// „Los geht's"-Flow. Im Chain wird die Setup-Card ohnehin
    /// übersprungen. Wir branchen daher: Chain-Pfad gated nur auf
    /// `!availableTenses.isEmpty`, Out-of-Chain-Pfad behält das
    /// bestehende `verbformsCanStart`-Gate (Schutz vor Start mit
    /// leerer Listen-Auswahl).
    private func tryAutoStartVerbformsIfReady() {
        guard !verbformsSession.isActive,
              !verbformsSession.isFinished else {
            return
        }
        if launchContext?.chainContext != nil {
            // Chain-Mode: nur availableTenses-Gate. setupCanStartCached
            // wird hier ignoriert.
            guard !verbformsSession.availableTenses.isEmpty else { return }
        } else {
            // Out-of-Chain: existing canStart-Gate (Listen + Tenses).
            guard verbformsCanStart else { return }
        }
        startVerbformsTraining()
    }

    func handleTrainingDirectionChange() {
        // Only reset if still in setup (not during active training)
        if session.isShowingSetup {
            resetTrainingSession()
        }
    }

    func handleTrainingCardTypeChange() {
        guard session.isShowingSetup else { return }
        resetTrainingSession()
    }

    func handleTrainingListChange() {
        guard session.isShowingSetup else { return }
        refreshDictionaryTrainingListIfNeeded()
        ensureDirectionValidity()
        resetTrainingSession()
    }

    func handleDictionaryLearningLevelChange() {
        guard session.isShowingSetup else { return }
        refreshDictionaryTrainingListIfNeeded()
        ensureTrainingSelectionValidity()
        ensureDirectionValidity()
        resetTrainingSession()
    }

    func handleTrainingAppDirectionChange() {
        guard session.isShowingSetup else { return }
        refreshDictionaryTrainingListIfNeeded()
        ensureDirectionValidity()
        resetTrainingSession()
    }

    func handleTrainingCustomListsChange() {
        guard session.isShowingSetup else { return }
        ensureTrainingSelectionValidity()
        ensureDirectionValidity()
        resetTrainingSession()
    }

    func handleTrainingListPickerChange() {
        refreshDictionaryTrainingListIfNeeded()
    }

    func handleTrainingRecordingTransition(from wasRecording: Bool, to isRecording: Bool) {
        guard wasRecording, !isRecording, shouldEvaluateAfterStop else { return }
        shouldEvaluateAfterStop = false
        evaluateTranscript()
    }

    func handleTrainingRecordingPulseChange(_ isRecording: Bool) {
    }

    func handleTrainingSpeakerTransition(from wasSpeaking: Bool, to isSpeaking: Bool) {
        appDebugLog("🔊 [SpeakerTransition] \(wasSpeaking) → \(isSpeaking)")
        guard wasSpeaking, !isSpeaking else { return }
        appDebugLog("🔊 [SpeakerTransition] speaker finished → calling beginAutomaticListeningIfNeeded")
        beginAutomaticListeningIfNeeded()
    }

    func handleTypedAnswerFocusChange(_ isFocused: Bool) {
        if isFocused {
            stopListeningForTyping()
        }
        // **Daily Drop Modul 2.8 (2026-05-23)** — globalen Footer aus-/
        // einblenden (bewiesener Chat-Mechanismus), damit die Tastatur die
        // View nicht hochschiebt. Reset auch in handleTrainingDisappear.
        setKeyboardChromeHidden?(isFocused)
    }

    func handleTrainingDisappear() {
        // **Daily Drop Modul 2.8 (2026-05-23)** — Footer-Reset-Guard: sonst
        // bliebe der globale Footer auf Folge-Screens ausgeblendet, wenn der
        // User mit offener Tastatur weg-navigiert (Chat macht das ebenso).
        setKeyboardChromeHidden?(false)
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        speechController?.stopRecording()
        speechController?.deactivateAudioSession()
    }

    func triggerTrainingAudioPreparationIfNeeded() {
        guard !hasTriggeredAudioPreparation else { return }
        hasTriggeredAudioPreparation = true
        Task {
            await prepareTrainingAudioDependenciesIfNeeded()
        }
    }

    func prepareTrainingAudioDependenciesIfNeeded() async {
        guard speechController == nil || speaker == nil else { return }
        guard !isPreparingAudioDependencies else { return }
        isPreparingAudioDependencies = true
        await ensureAudioDependenciesReady()
        isPreparingAudioDependencies = false
    }
}
