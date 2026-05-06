import SwiftUI
import AVFoundation

extension TrainingView {
    func dismissToHome() {
        resetTrainingSession()
        goHome()
    }

    /// TopBar-/Session-Back-Verhalten: Im aktiven Abfragemodus (nach „Los geht's")
    /// führt der Back-Button eine Ebene zurück zur Setup-/Listenauswahl-Card,
    /// NICHT komplett nach Home. Bei Verbformen wird weiterhin dismissed — dort
    /// gibt es eigene Reset/Setup-Flows und der User hat explizit gesagt, dass
    /// das aktuelle Verhalten passt.
    ///
    /// XP/Credits werden gleich wie bei `dismissTraining()` vergeben, damit der
    /// User nicht bestraft wird, wenn er zurück zum Setup springt statt zu Home.
    func handleTopBarBack() {
        let isInTrainingSession = !isVerbformsMode
            && (session.hasStartedTraining || !session.isShowingSetup)
        if isInTrainingSession {
            awardTrainingXPIfNeeded()

            // **Chain-Mode Back-Chevron (2026-05-02)** — im Chain-Mode
            // poppen wir die Modul-Route statt zur Listen-/Mode-Card
            // zurückzufallen (Setup-Skip-Verstoß). XP wurde oben
            // idempotent vergeben (`sessionRewardConsumed`-Schutz).
            // Audio-Cleanup explizit hier, damit TTS / Mikro nicht
            // weiterläuft während der Pre-Screen rendert; `onDisappear`
            // räumt zusätzlich auf, aber die UI-State-Resets in
            // `resetTrainingSession()` (verbMC, articleAnswer, …)
            // werden bewusst übersprungen — die View wird ohnehin
            // gepopt + bei nächster Chain-Step-Push neu instanziiert.
            if launchContext?.chainContext != nil {
                cancelPendingFeedback()
                speechController?.stopRecording()
                speechController?.transcript = ""
                speaker?.stop()
                stopSpeedRoundTimer()
                dismiss()
                return
            }

            resetTrainingSession()
        } else {
            // Auch im Verbformen-Flow: erst Reward (falls Fortschritt
            // vorhanden), dann dismiss. `awardVerbformsXPIfNeeded` ist idempotent.
            if isVerbformsMode {
                awardVerbformsXPIfNeeded()
            }
            dismiss()
        }
    }

    func dismissTraining() {
        awardTrainingXPIfNeeded()
        resetTrainingSession()
        dismiss()
    }

    /// Vergibt XP/Credits/Streak für die aktuelle Verbformen-Session über den
    /// zentralen `ProgressService`. Schutz via `sessionRewardConsumed` verhindert
    /// Mehrfach-Vergabe, wenn der Hook aus mehreren Back-Pfaden aufgerufen wird
    /// (Result-Screen, TopBar-Back). Speed-Round läuft als eigene Origin.
    ///
    /// Das berechnete `SessionRewardOutcome` wird in `verbformsSessionOutcome`
    /// abgelegt und ersetzt den bisherigen Zahlen-Result-Screen durch die
    /// einheitliche `SessionSummaryView`.
    func awardVerbformsXPIfNeeded() {
        guard !verbformsSession.sessionRewardConsumed else { return }
        let origin: LearningSession.Origin = verbformsSession.isSpeedRound ? .speedRound : .verbforms
        let learningSession = LearningSession(
            origin: origin,
            correctCount: verbformsSession.sessionCorrectCount,
            wrongCount: verbformsSession.sessionWrongCount,
            longestCombo: verbformsSession.sessionLongestCombo
        )
        guard learningSession.correctCount > 0 || learningSession.wrongCount > 0 else { return }
        verbformsSession.sessionRewardConsumed = true
        let outcome = ProgressService.shared.record(session: learningSession)
        verbformsSessionOutcome = outcome
        arcadeCredits = ProgressStore.shared.progress.arcadeCredits
    }

    /// XP, Credits und Streak werden über den zentralen `ProgressService`
    /// vergeben. Single Source of Truth, konsistent mit Karteikarten und Quiz.
    /// Schutz via `sessionRewardConsumed` gegen Mehrfach-Vergabe bei
    /// wiederholtem Aufruf aus verschiedenen Back-Pfaden.
    ///
    /// Das berechnete `SessionRewardOutcome` wird in `trainingSessionOutcome`
    /// abgelegt und triggert die einheitliche `SessionSummaryView`. Diese zeigt
    /// dem Nutzer XP-Aufschlüsselung, Credits, Level-Progress — analog zu den
    /// Karteikarten.
    func awardTrainingXPIfNeeded() {
        guard !session.sessionRewardConsumed else { return }
        // Speed Rounds fließen als eigene Origin; normales Training als
        // `.training`. Das Session-Minimum unterscheidet sich (siehe
        // `GamificationConfig.SessionMinimum`).
        let origin: LearningSession.Origin = session.isSpeedRound ? .speedRound : .training
        let learningSession = LearningSession(
            origin: origin,
            correctCount: session.sessionCorrectCount,
            wrongCount: session.sessionWrongCount,
            longestCombo: session.sessionLongestCombo
        )
        guard learningSession.correctCount > 0 || learningSession.wrongCount > 0 else { return }
        session.sessionRewardConsumed = true
        let outcome = ProgressService.shared.record(session: learningSession)
        trainingSessionOutcome = outcome
        arcadeCredits = ProgressStore.shared.progress.arcadeCredits
        // Session ist abgeschlossen → Resume-Snapshot verwerfen. Ohne
        // diesen Cleanup würde der User beim nächsten Setup in eine
        // scheinbar „laufende" Runde zurückgeworfen, obwohl er gerade die
        // Summary gesehen hat.
        session.clearResumeSnapshot()
    }

    func applyLaunchContextIfNeeded() {
        session.applyLaunchContextIfNeeded(
            launchContext,
            listStore: listStore,
            updateAppDirectionRaw: { selectedAppDirectionRaw = $0 }
        )
    }

    func ensureTrainingSelectionValidity() {
        session.ensureTrainingSelectionValidity(
            listStore: listStore,
            launchContext: launchContext,
            selectedAppDirection: selectedAppDirection
        )
    }

    func ensureDirectionValidity() {
        session.ensureDirectionValidity(
            listStore: listStore,
            launchContext: launchContext,
            selectedAppDirection: selectedAppDirection,
            updateAppDirectionRaw: { selectedAppDirectionRaw = $0 }
        )
    }

    func refreshDictionaryTrainingListIfNeeded() {
        session.refreshDictionaryTrainingListIfNeeded(
            launchContext: launchContext,
            listStore: listStore,
            selectedAppDirection: selectedAppDirection,
            updateAppDirectionRaw: { selectedAppDirectionRaw = $0 }
        )
    }

    func resetTrainingSession() {
        let trace = Thread.callStackSymbols.prefix(8).joined(separator: "\n")
        print("🏋️ [Training] ⚠️ resetTrainingSession called from:\n\(trace)")
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        session.resetTrainingSessionState()
        lastResult = nil
        speaker?.stop()
        speechController?.stopRecording()
        speechController?.transcript = ""
        speechController?.recordError = nil
        typedAnswer = ""
        showingTypedAnswerInput = !isAudioModeEnabled
        typedAnswerFieldFocused = false
        isMicPulseVisible = false
        articleAnswer = nil
        articleLocked = false
        showingArticleTranslation = false
        verbMCOptions = []
        verbMCSelected = nil
        verbMCLocked = false
        showingVerbTranslation = false
        speedCountdownPhase = nil
        // **2026-05-06 Cancel-Fix** — Pending Intro-Items
        // ausschalten, damit kein Audio-Tick oder verzögerter
        // Engine-Start nach dem Reset feuert.
        trainingCountdownTask?.cancel()
        trainingCountdownTask = nil
        stopSpeedRoundTimer()
    }

    func startSpeedRoundTimer() {
        session.speedRoundScore = 0
        // Speed-Round-Dauer kommt aus der globalen Settings-Einstellung
        // (`SpeedRoundSettings.currentSeconds`). Default ist
        // `SpeedRoundDuration.defaultDuration`, der User kann in den
        // Settings zwischen allen `SpeedRoundDuration`-Cases wählen.
        let duration = SpeedRoundSettings.currentSeconds
        session.speedRoundTimeRemaining = duration
        session.speedRoundTotalSeconds = duration
        session.speedRoundTimer?.invalidate()
        session.speedRoundTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak session] _ in
            Task { @MainActor in
                guard let session, session.speedRoundTimer != nil else { return }
                session.speedRoundTimeRemaining -= 1
                if session.speedRoundTimeRemaining <= 5, session.speedRoundTimeRemaining > 0 {
                    self.feedbackPlayer.playToggle()
                }
                if session.speedRoundTimeRemaining <= 0 {
                    self.feedbackPlayer.playRoundClear()
                    // Zentraler Finalize-Hook bei Ablauf der Speed Round:
                    //   1. Timer invalidieren (verhindert Nachläufer-Ticks)
                    //   2. Speaker stumm + Speech-Recognition stoppen
                    //      (TTS darf nach Summary-Start nicht weiterlaufen,
                    //       Mikrofon-Listening darf keine Eingaben mehr
                    //       produzieren)
                    //   3. Noch ausstehenden Auto-Advance abbrechen
                    //   4. `awardTrainingXPIfNeeded()` setzt
                    //      `trainingSessionOutcome` → die View-Branch in
                    //      `trainingRootContent` wechselt **ausschließlich**
                    //      zur globalen `SessionSummaryView`. Die frühere
                    //      Inline-Speed-Round-Completion-Card wird durch
                    //      denselben Mechanismus maskiert.
                    session.speedRoundTimer?.invalidate()
                    session.speedRoundTimer = nil
                    self.runtimeSpeaker?.stop()
                    self.speechController?.stopRecording()
                    self.cancelPendingFeedback()
                    self.awardTrainingXPIfNeeded()
                }
            }
        }
    }

    func stopSpeedRoundTimer() {
        session.speedRoundTimer?.invalidate()
        session.speedRoundTimer = nil
    }

    func startTraining() {
        print("🏋️ [Training] startTraining mode=\(session.trainingMode) activeItems=\(activeItems.count) selectedIDs=\(session.selectedTrainingListIDs.count) verbSetSize=\(StandardVocabularyLoader.verbSet.count)")
        ensureTrainingSelectionValidity()
        guard session.startTraining(
            listStore: listStore,
            launchContext: launchContext,
            selectedAppDirection: selectedAppDirection
        ) else {
            print("🏋️ [Training] ❌ startTraining failed — empty pool")
            showEmptyPoolToast()
            resetTrainingSession()
            return
        }
        showingTypedAnswerInput = false
        typedAnswerFieldFocused = false
        if session.isSpeedRound {
            // **2026-05-06 Refactor** — Geteilter Sequencer ersetzt
            // den inline 3-2-1-Countdown. Fünf Phasen (Achtung… → 3
            // → 2 → 1 → Los geht's!) mit zentralisierter Audio-/
            // Haptik-Kette, identisch zu Akzente und Verbformen.
            //
            // **2026-05-06 Cancel-Fix** — Vorherige Task canceln
            // (Defensive für Re-Start nach Abbruch), neuen Task in
            // `trainingCountdownTask` halten. Cleanup-Pfade
            // (resetTrainingSession, body.onDisappear) cancellen
            // ihn dann.
            trainingCountdownTask?.cancel()
            trainingCountdownTask = SpeedRoundCountdownSequencer.start(
                feedbackPlayer: feedbackPlayer,
                apply: { phase in speedCountdownPhase = phase },
                onComplete: {
                    startSpeedRoundTimer()
                    if isVerbMode { prepareVerbMCOptions() }
                }
            )
            return
        }
        if isArticleMode {
            return
        }
        if isVerbMode {
            prepareVerbMCOptions()
            return
        }
        if isNounChoiceMode {
            // Nomen-Wortauswahl: MC-Optionen für die erste Karte aufbauen —
            // KEINE TTS-Ansprache, User antwortet per Tap. `prepareNounMCOptions`
            // wird bei jedem Karten-Wechsel via `onChange(currentTrainingItem)`
            // erneut aufgerufen (siehe Layout-onChange).
            prepareNounMCOptions()
            return
        }
        speakCurrentPromptAfterScreenUpdate(initialDelay: 0.12)
    }

    func loadNextTrainingCard() {
        // **Stufe 4b-4 (2026-05-02, Branch `feature/training-session-flow`)** —
        // Soft-Cutoff-Force-Done für den Chain-Timer im Training-
        // Modus (vocabulary / nouns / articles / verbs). Wenn der User
        // auf einer Chain-Step-Training-Session sitzt UND der Chain-
        // Timer im `TrainingChainStore` schon abgelaufen ist,
        // schließen wir die Session HIER ab — beim natürlichen
        // Übergang zur nächsten Karte. Der gerade beantwortete Card-
        // Submit ist zu diesem Zeitpunkt komplett ausgewertet
        // (R7-Schutz: scheduleNextCard hat 0.55s Eval-Delay vor diesem
        // Aufruf). Statt zur nächsten Karte zu wechseln, springen wir
        // direkt auf den `trainingSummaryScreen` mit dem Stufe-3-
        // Chain-aware-CTA. Verbformen-Pfad läuft nicht hier durch,
        // siehe `handleVerbformsNext()` für den dortigen Hook.
        // **Modal-Race-Fix 2026-05-02** — User-Befund: bei Chain-
        // Nomen-Wortauswahl mit kurzer Eval-Animation (~1.0–1.2 s)
        // konnte der Force-Done-Pfad das `ChainCutoffModal` mid-render
        // pre-empten. SwiftUI hat den Modal-State (`cutoffModalVisible
        // = true`) zwar gesetzt, aber die View-Transition zum
        // Summary-Screen löste die Modal-Animation auf, bevor sie
        // sichtbar wurde. Lösung: solange das Modal sichtbar ist,
        // hat der User-Choice Vorrang — Force-Done läuft entweder
        // explizit über den „Jetzt weiter"-CTA des Modals oder über
        // den nächsten Submit, NACHDEM User „Aufgabe fertigmachen"
        // getappt hat (`cutoffModalVisible` zurück auf false).
        if TrainingChainStore.shared.timerExpired,
           !TrainingChainStore.shared.cutoffModalVisible,
           !isVerbformsMode,
           trainingSessionOutcome == nil {
            forceTrainingDoneFromChainTimer()
            return
        }
        speechController?.transcript = ""
        speechController?.recordError = nil
        lastResult = nil
        typedAnswer = ""
        showingTypedAnswerInput = false
        typedAnswerFieldFocused = false
        session.loadNextTrainingCard()
    }

    /// **Stufe 4b-4 (2026-05-02)** — Forciert das Training-Session-
    /// Ende durch den Chain-Timer-Soft-Cutoff. Stoppt Speed-Round-
    /// Timer + TTS + Mikrofon-Listening, ruft `awardTrainingXPIfNeeded`
    /// (idempotent über `session.sessionRewardConsumed`). Falls der
    /// User noch nicht eine einzige Aufgabe beantwortet hat (0/0 →
    /// `awardTrainingXPIfNeeded` early-returns), setzen wir
    /// `trainingSessionOutcome` defensiv auf `.empty` damit die
    /// View-Branch in `trainingRootContent` (Z. 33-38) zum
    /// `trainingSummaryScreen` wechselt — sonst hängt der User auf
    /// dem Session-Screen mit aktiver Modal-Backdrop oder schwarzer
    /// Card-Anzeige. Idempotent gegen Re-Call via
    /// `trainingSessionOutcome != nil`-Guard.
    func forceTrainingDoneFromChainTimer() {
        guard trainingSessionOutcome == nil else { return }
        // Defensive Cleanup analog zum natürlichen Speed-Round-Ende
        // (Z. 189-194 in dieser Datei): Timer killen, Audio-Pfade
        // stoppen, Pending-Eval canceln. Verhindert dass nach Force-
        // Done noch ein Auto-Advance / TTS / Speech-Recognition-Tick
        // im Hintergrund weiterläuft.
        session.speedRoundTimer?.invalidate()
        session.speedRoundTimer = nil
        runtimeSpeaker?.stop()
        speechController?.stopRecording()
        cancelPendingFeedback()
        awardTrainingXPIfNeeded()
        if trainingSessionOutcome == nil {
            trainingSessionOutcome = .empty
        }
        #if DEBUG
        print("🛑 [Training] Force-Done via chain-timer-soft-cutoff")
        #endif
    }

    /// **Stufe 4b-5 (2026-05-02)** — View-Wrapper um
    /// `verbformsSession.next()`. Schaltet bei abgelaufenem Chain-
    /// Timer auf `forceVerbformsDoneFromChainTimer()` um — sonst
    /// regulärer Pass-through. Wird von beiden „Weiter"-Buttons im
    /// Verbformen-Layout (Z. 1644 in der Multiple-Choice-Variante,
    /// Z. 1863 in der Typing-Variante) aufgerufen statt direkt
    /// `verbformsSession.next()`. R7-Schutz: der vorhergehende
    /// Match/Submit hat seine Eval (Audio + Animation + State) bereits
    /// komplett abgeschlossen, der „Weiter"-Tap ist der explizite
    /// User-Trigger zur nächsten Aufgabe — der Cutoff-Check sitzt
    /// genau hier am natural-transition-to-next-Punkt.
    func handleVerbformsNext() {
        // **Modal-Race-Fix 2026-05-02** — siehe `loadNextTrainingCard`:
        // Modal hat Vorrang vor Force-Done-Pre-Emption.
        if TrainingChainStore.shared.timerExpired,
           !TrainingChainStore.shared.cutoffModalVisible,
           !verbformsSession.isFinished {
            forceVerbformsDoneFromChainTimer()
            return
        }
        verbformsSession.next()
    }

    /// **Stufe 4b-5 (2026-05-02)** — Forciert das Verbformen-Session-
    /// Ende. Setzt `verbformsSession.isFinished = true` (mirror des
    /// natürlichen Endes in `VerbformsSessionController.next()` Z. 298,
    /// Z. 374, Z. 383, Z. 436). View-Branch in `trainingRootContent`
    /// (Z. 28-30) wechselt daraufhin zum `verbformsResultScreen`,
    /// dessen `.onAppear` (Z. 2009-2018) ruft
    /// `awardVerbformsXPIfNeeded()` synchron — wir rufen es hier
    /// trotzdem schon explizit, damit `verbformsSessionOutcome`
    /// garantiert vor dem Render gesetzt ist. Falls 0/0 (User hat
    /// noch nichts beantwortet), setzen wir das Outcome defensiv auf
    /// `.empty` für saubere Summary-Render. Idempotent gegen Re-Call
    /// via `!verbformsSession.isFinished`-Guard.
    func forceVerbformsDoneFromChainTimer() {
        guard !verbformsSession.isFinished else { return }
        verbformsSession.isFinished = true
        verbformsSession.isActive = false
        verbformsSession.stopSpeedRoundTimer()
        runtimeSpeaker?.stop()
        speechController?.stopRecording()
        awardVerbformsXPIfNeeded()
        if verbformsSessionOutcome == nil {
            verbformsSessionOutcome = .empty
        }
        #if DEBUG
        print("🛑 [Verbformen] Force-Done via chain-timer-soft-cutoff")
        #endif
    }

    func revealSolution() {
        guard let currentCard, canRevealSolution else { return }
        cancelPendingFeedback()
        shouldEvaluateAfterStop = false
        speechController?.stopRecording()
        speechController?.transcript = ""
        speechController?.recordError = nil
        typedAnswerFieldFocused = false
        lastResult = ScoreResult(label: "Lösung", detail: currentCard.answer)

        // **Mikro-Auto-Resume (2026-05-02)** — User-Spec: nach
        // „Lösung anzeigen" soll das Mikro automatisch wieder
        // anspringen, damit der User die jetzt-bekannte Lösung
        // selbst sprechen kann ohne den Mikro-Button manuell
        // antippen zu müssen. Kurzer Delay (0.4 s) gibt der oben
        // gestoppten Audio-Session Zeit, sauber abzubauen, bevor
        // wir per `beginAutomaticListeningIfNeeded` einen neuen
        // Recording-Start triggern — direkter Restart riskiert
        // einen iOS „Engine bereits aktiv"-Fehler. Self-gated über
        // die Mode-Guards in `beginAutomaticListeningIfNeeded`:
        // greift in Vokabeln- und Nomen-Speech-Modus, ist No-Op
        // für Article-/Verb-/Noun-Choice-Modi.
        scheduleFeedbackTask(after: 0.4) {
            beginAutomaticListeningIfNeeded()
        }
    }

    func repeatCurrentPrompt() {
        guard let currentCard else { return }
        scheduleFeedbackTask(after: 0.35) {
            guard isShowing(currentCard) else { return }
            speakCurrentPromptAfterScreenUpdate(initialDelay: 0.02)
        }
    }

    func scheduleNextCard() {
        guard let currentCard else { return }
        scheduleFeedbackTask(after: 0.55) {
            guard isShowing(currentCard) else { return }
            loadNextTrainingCard()
            if session.hasStartedTraining {
                speakCurrentPromptAfterScreenUpdate(initialDelay: 0.06)
            }
        }
    }

    func scheduleFeedbackTask(after delay: TimeInterval, action: @escaping () -> Void) {
        cancelPendingFeedback()
        let workItem = DispatchWorkItem(block: action)
        pendingFeedbackTask = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    func cancelPendingFeedback() {
        pendingFeedbackTask?.cancel()
        pendingFeedbackTask = nil
    }

    func isShowing(_ card: FlashCard) -> Bool {
        guard let currentCard else { return false }
        return isSameTrainingCard(currentCard, card)
    }

    func isSameTrainingCard(_ lhs: FlashCard, _ rhs: FlashCard) -> Bool {
        lhs.prompt == rhs.prompt
            && lhs.answer == rhs.answer
            && lhs.category == rhs.category
    }

    // MARK: - Empty-Pool-Hint (2026-04-29)

    /// Zeigt den Empty-Pool-Toast und plant das Auto-Dismiss.
    ///
    /// **Auto-Dismiss-Dauer 2.5s** — bewusst länger als das ListsView-
    /// Pattern (1.8s). Begründung: ListsView-Toasts sind „erfolgreich-
    /// gespeichert"-Bestätiger, die User nur kurz wahrnehmen müssen.
    /// Hier ist die Message **erklärend** — User muss verstehen, dass
    /// die Auswahl leer ist UND was zu tun ist (andere Liste / mehr
    /// Lernjahre). 2.5s deckt zwei Lese-Durchgänge ab.
    ///
    /// Pattern analog `ListsView.showToast(...)`: re-entrant safe via
    /// Cancel des vorigen DispatchWorkItem, animierter Eintritt/Austritt
    /// per `.transition(...)` am Render-Site, kein Tap-to-Dismiss
    /// (ListsView-Pattern hat das auch nicht — keine Aufbohrung nur
    /// für diesen Use-Case).
    func showEmptyPoolToast() {
        emptyPoolToastDismissWorkItem?.cancel()
        withAnimation(.easeInOut(duration: 0.22)) {
            emptyPoolToastMessage = "F\u{00FC}r deine Auswahl gibt es keine Eintr\u{00E4}ge. W\u{00E4}hle eine andere Liste oder erweitere die Lernjahre."
        }

        let work = DispatchWorkItem {
            withAnimation(.easeInOut(duration: 0.22)) {
                emptyPoolToastMessage = nil
            }
        }
        emptyPoolToastDismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: work)
    }
}
