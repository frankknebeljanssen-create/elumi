import SwiftUI

extension TrainingView {
    func speakCurrentPrompt() {
        // Nomen-Wortauswahl: kein TTS — die Vorlage wird still gezeigt,
        // der User wählt aus dem 8er-Grid. (Im Speech-Pfad bleibt die
        // bisherige Ansprache des Prompts erhalten.)
        guard !isArticleMode, !isVerbMode, !isNounChoiceMode else { return }
        guard let currentCard else {
            return
        }
        stopListeningForTyping()
        guard isAudioModeEnabled else {
            appDebugLog("🔊 [Speak] ❌ audioMode disabled (sounds=\(feedbackPlayer.areSoundsEnabled))")
            showingTypedAnswerInput = true
            return
        }
        guard let speaker else {
            appDebugLog("🔊 [Speak] ❌ no speaker (runtimeSpeaker=\(runtimeSpeaker != nil))")
            showingTypedAnswerInput = true
            return
        }
        appDebugLog("🔊 [Speak] ✅ speaking: \(currentCard.prompt)")
        lastResult = nil
        speaker.speak(text: currentCard.prompt, languageCode: currentCard.promptLanguageCode)
    }

    func toggleRecording() {
        guard session.hasStartedTraining, currentCard != nil else { return }
        cancelPendingFeedback()
        typedAnswerFieldFocused = false

        guard let speechController else {
            Task {
                await prepareTrainingAudioDependenciesIfNeeded()
            }
            return
        }

        if speechController.isRecording {
            shouldEvaluateAfterStop = false
            speechController.stopRecording()
        } else {
            speaker?.stop()
            lastResult = nil
            typedAnswer = ""
            showingTypedAnswerInput = false
            shouldEvaluateAfterStop = true
            speechController.startRecording(localeIdentifier: localeIdentifierForRecognition)
        }
    }

    func submitVerbMC(_ option: String) {
        // Session-Ende-Guard: wenn die Speed-Round-Zeit abgelaufen ist
        // oder ein Summary bereits vergeben wurde (`trainingSessionOutcome`
        // gesetzt), darf nichts mehr durchrutschen — auch wenn die
        // Button-Card noch kurz auf dem Screen ist, bevor der Summary-
        // Wechsel greift.
        guard !verbMCLocked,
              session.currentTrainingItem != nil,
              !isTrainingSessionEnded else { return }
        let isSpeed = session.isSpeedRound && session.speedRoundTimeRemaining > 0
        verbMCLocked = true
        verbMCSelected = option
        let isCorrect = option.lowercased() == verbCorrectAnswer.lowercased()

        // Lernstatus-Hook (FIX): Der MC-Button-Pfad bei Verben ging bisher
        // nie durch `evaluateResponse` und hat deshalb **nie** ein Signal
        // an den `ItemLearningStatusStore` geschickt. Recording muss an
        // den tatsächlichen Bewertungszeitpunkt — genau hier, sofort nach
        // Berechnung von `isCorrect`. Werte kommen aus
        // `session.currentTrainingItem`, das durch die Guard-Zeile
        // sichergestellt ist (wird nie mid-flight auf nil gedreht).
        //
        // `firstAttempt` entscheidet, ob diese Antwort die Streak-Serie
        // verlängert oder (wie eine falsche Antwort) auf 0 zurücksetzt —
        // so wird die Nutzererwartung "5x in ununterbrochener Folge"
        // auch bei Retries korrekt abgebildet.
        session.recordAnswer(
            correct: isCorrect,
            firstAttempt: session.failedAttemptsOnCurrentCard == 0
        )

        if isCorrect {
            feedbackPlayer.playStudySuccess()
            if isSpeed { session.speedRoundScore += 1 }
            scheduleFeedbackTask(after: isSpeed ? 0.3 : 1.2) {
                verbMCSelected = nil
                verbMCLocked = false
                loadNextTrainingCard()
                prepareVerbMCOptions()
            }
        } else {
            feedbackPlayer.playStudyError()
            session.incrementFailedAttempts()
            let maxAttempts = isSpeed ? 3 : 999
            let shouldSkip = session.failedAttemptsOnCurrentCard >= maxAttempts
            scheduleFeedbackTask(after: isSpeed ? 0.3 : 1.0) {
                verbMCSelected = nil
                verbMCLocked = false
                if shouldSkip {
                    loadNextTrainingCard()
                    prepareVerbMCOptions()
                }
            }
        }
    }

    func prepareVerbMCOptions() {
        guard let item = session.currentTrainingItem else {
            verbMCOptions = []
            return
        }
        let isFRtoDe = selectedAppDirection == .frenchToGerman || selectedAppDirection == .englishToGerman
        // WICHTIG: Original-Schreibweise beibehalten (Nomen-Großschreibung etc.).
        // Vergleich läuft per .lowercased() — Anzeige bleibt aber kapitalisiert.
        let correctAnswer = (isFRtoDe ? item.german : item.french)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !correctAnswer.isEmpty else {
            verbMCOptions = []
            return
        }
        let correctKey = correctAnswer.lowercased()
        let isAnswerGerman = isFRtoDe

        // Verb-Training trainiert NUR Infinitive (siehe activeItems Filter in
        // TrainingSessionController+DictionarySelection). Distraktor-Pool sind
        // ebenfalls Infinitive — selbe Form wie die korrekte Antwort. Der
        // `MCDistractorFilter` filtert den Pool dann nach Level-Bucket,
        // Wortanzahl und Länge, damit bei „aimer" nicht plötzlich
        // „portefeuille" als Distraktor auftaucht.
        //
        // Pool-Source `verbEntries` ist ein **statisch einmal gefilterter**
        // Cache (siehe `StandardVocabularyLoader`) — die O(n)-Filterung
        // läuft **nicht** bei jedem Karten-Wechsel, sondern exakt einmal
        // pro App-Start.
        let candidatePool: [MCDistractorFilter.Candidate] = StandardVocabularyLoader.verbEntries
            .map { entry in
                MCDistractorFilter.Candidate(
                    display: isAnswerGerman ? entry.target : entry.sourceDisplay,
                    level: entry.level,
                    topic: entry.topic
                )
            }

        let distractors = MCDistractorFilter.pickDistractors(
            correctAnswer: correctAnswer,
            correctLevel: item.level?.rawValue, // Fallback — kann nil sein (Custom-Listen)
            from: candidatePool,
            count: 7
        )

        var options = [correctAnswer] + distractors
        // SAFETY: garantiert, dass correctAnswer IMMER in den Optionen enthalten ist
        // (schützt vor Edge-Cases, z.B. leerem Pool).
        if !options.contains(where: { $0.lowercased() == correctKey }) {
            options.append(correctAnswer)
        }
        options.shuffle()
        verbMCOptions = options
    }

    // MARK: - Nomen Wortauswahl (Wortauswahl-Modus)
    //
    // Mechanisch eine 1:1-Klon-Kopie des Verben-MC-Flows: 8 Optionen
    // (1 Lösung + 7 Distraktoren), Tap sperrt die Karte, Grün/Rot-Feedback,
    // Auto-Advance nach 0.3s (Speed Round) bzw. 1.0–1.2s (normal). Die
    // Trennung (eigene `nounMC*`-States statt Shared mit Verben) ist bewusst:
    // Verben-Modul trainiert Infinitive auf einem geschärften Pool (nur
    // `wordClass == "verb"`), Nomen braucht einen anderen Distraktor-Pool
    // (`wordClass == "noun"`). Ein gemeinsamer State wäre zu leaky und
    // würde Cross-Module-Resets erzwingen.

    func submitNounMC(_ option: String) {
        guard !nounMCLocked,
              session.currentTrainingItem != nil,
              !isTrainingSessionEnded else { return }
        let isSpeed = session.isSpeedRound && session.speedRoundTimeRemaining > 0
        nounMCLocked = true
        nounMCSelected = option
        let isCorrect = option.lowercased() == nounCorrectAnswer.lowercased()

        // Lernstatus-Hook (FIX): Bei Nomen-Wortauswahl fehlte bisher der
        // Recording-Call — nur der Spracheingabe-Pfad rief `evaluateResponse`
        // an. Dadurch gingen alle MC-Button-Taps an der Persistenz vorbei.
        // Analog zum Verben-Fix sofort nach `isCorrect`.
        // `firstAttempt`: siehe Kommentar in `submitVerbMC`.
        session.recordAnswer(
            correct: isCorrect,
            firstAttempt: session.failedAttemptsOnCurrentCard == 0
        )

        if isCorrect {
            feedbackPlayer.playStudySuccess()
            if isSpeed { session.speedRoundScore += 1 }
            scheduleFeedbackTask(after: isSpeed ? 0.3 : 1.2) {
                nounMCSelected = nil
                nounMCLocked = false
                loadNextTrainingCard()
                prepareNounMCOptions()
            }
        } else {
            feedbackPlayer.playStudyError()
            session.incrementFailedAttempts()
            let maxAttempts = isSpeed ? 3 : 999
            let shouldSkip = session.failedAttemptsOnCurrentCard >= maxAttempts
            scheduleFeedbackTask(after: isSpeed ? 0.3 : 1.0) {
                nounMCSelected = nil
                nounMCLocked = false
                if shouldSkip {
                    loadNextTrainingCard()
                    prepareNounMCOptions()
                }
            }
        }
    }

    func prepareNounMCOptions() {
        guard let item = session.currentTrainingItem else {
            nounMCOptions = []
            return
        }
        let isFRtoDe = selectedAppDirection == .frenchToGerman || selectedAppDirection == .englishToGerman
        // Original-Schreibweise (Nomen-Großschreibung) beibehalten — der Vergleich
        // läuft per .lowercased(), die Anzeige aber kapitalisiert.
        let correctAnswer = (isFRtoDe ? item.german : item.french)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !correctAnswer.isEmpty else {
            nounMCOptions = []
            return
        }
        let correctKey = correctAnswer.lowercased()
        let isAnswerGerman = isFRtoDe

        // Distraktor-Pool: alle Lexikon-Einträge mit `wordClass == "noun"`.
        // Filter läuft über `MCDistractorFilter` — derselbe Pfad wie bei
        // Verben, damit bei „der Tisch" keine Phrasen oder C1-Wörter wie
        // „das Mikrofon im Besprechungsraum" mehr auftauchen.
        //
        // Pool-Source `nounEntries` ist statisch einmal gefiltert (siehe
        // `StandardVocabularyLoader`) — O(1)-Zugriff pro Karten-Wechsel.
        let candidatePool: [MCDistractorFilter.Candidate] = StandardVocabularyLoader.nounEntries
            .map { entry in
                MCDistractorFilter.Candidate(
                    display: isAnswerGerman ? entry.target : entry.sourceDisplay,
                    level: entry.level,
                    topic: entry.topic
                )
            }

        let distractors = MCDistractorFilter.pickDistractors(
            correctAnswer: correctAnswer,
            correctLevel: item.level?.rawValue,
            from: candidatePool,
            count: 7
        )

        var options = [correctAnswer] + distractors
        // SAFETY: Lösung muss IMMER in den Optionen enthalten sein — schützt
        // vor Edge-Cases (z. B. leerer Pool → correctAnswer würde sonst fehlen).
        if !options.contains(where: { $0.lowercased() == correctKey }) {
            options.append(correctAnswer)
        }
        options.shuffle()
        nounMCOptions = options
    }

    func submitArticle(_ article: String) {
        guard !articleLocked,
              let correctArticle,
              !isTrainingSessionEnded else { return }
        let isSpeed = session.isSpeedRound && session.speedRoundTimeRemaining > 0
        articleLocked = true
        let isCorrect = article.lowercased() == correctArticle.lowercased()

        // Lernstatus-Hook (FIX): Artikel-Buttons gingen bisher
        // komplett an der Lernstatus-Persistenz vorbei — kein einziger
        // Tap wurde im `ItemLearningStatusStore` abgelegt. Recording
        // sofort nach Bewertung, damit alle Artikel-Übungen zuverlässig
        // im Home + Detail-Screen auftauchen. Für den Call brauchen wir
        // `session.currentTrainingItem`, was beim Laden der Artikel-Karte
        // via `loadNextTrainingCard()` bereits gesetzt ist.
        // `firstAttempt`: siehe Kommentar in `submitVerbMC`.
        if session.currentTrainingItem != nil {
            session.recordAnswer(
                correct: isCorrect,
                firstAttempt: session.failedAttemptsOnCurrentCard == 0
            )
        }

        if isCorrect {
            feedbackPlayer.playStudySuccess()
            if isSpeed { session.speedRoundScore += 1 }
            lastResult = ScoreResult(label: "Richtig 🙂", detail: "\(correctArticle) \(articlePromptText ?? "")")
            scheduleFeedbackTask(after: isSpeed ? 0.25 : 0.8) {
                articleAnswer = nil
                articleLocked = false
                lastResult = nil
                showingArticleTranslation = false
                loadNextTrainingCard()
            }
        } else {
            feedbackPlayer.playStudyError()
            session.incrementFailedAttempts()
            let maxAttempts = isSpeed ? 3 : 999
            let shouldSkip = session.failedAttemptsOnCurrentCard >= maxAttempts
            lastResult = ScoreResult(label: "Falsch 😕", detail: shouldSkip ? "\(correctArticle) \(articlePromptText ?? "")" : "Nochmal!")
            scheduleFeedbackTask(after: isSpeed ? 0.35 : 1.2) {
                articleLocked = false
                lastResult = nil
                showingArticleTranslation = false
                if shouldSkip {
                    loadNextTrainingCard()
                }
            }
        }
    }

    func evaluateTranscript() {
        evaluateResponse(speechController?.transcript ?? "")
    }

    func speakCurrentPromptAfterScreenUpdate(initialDelay: TimeInterval) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(initialDelay * 1_000_000_000))
            await Task.yield()
            guard session.hasStartedTraining, currentCard != nil else { return }
            await prepareTrainingAudioDependenciesIfNeeded()
            speakCurrentPrompt()
        }
    }

    func beginAutomaticListeningIfNeeded() {
        // Don't auto-listen in article/verb mode, and — analog — nicht im
        // Nomen-Wortauswahl-Modus: dort antwortet der User durch Tap auf
        // die Grid-Option, nicht per Spracheingabe.
        guard !isArticleMode, !isVerbMode, !isNounChoiceMode else { return }

        let started = session.hasStartedTraining
        let hasCard = currentCard != nil
        let audioOn = isAudioModeEnabled
        let speechOK = canUseSpeechRecognition
        let typing = showingTypedAnswerInput
        let focused = typedAnswerFieldFocused
        let hasController = speechController != nil
        let recording = speechController?.isRecording == true
        let authStatus = speechController?.authorizationStatus.rawValue ?? -1

        appDebugLog("🎤 [AutoListen] started=\(started) card=\(hasCard) audio=\(audioOn) speechPerm=\(speechOK)(auth=\(authStatus)) typing=\(typing) focused=\(focused) controller=\(hasController) recording=\(recording)")

        guard started, hasCard else { return }
        guard audioOn, speechOK else {
            appDebugLog("🎤 [AutoListen] ❌ blocked: audioMode=\(audioOn) speechPerm=\(speechOK)")
            return
        }
        guard !typing, !focused else {
            appDebugLog("🎤 [AutoListen] ❌ blocked: typing=\(typing) focused=\(focused)")
            return
        }
        guard let speechController else {
            appDebugLog("🎤 [AutoListen] ❌ no speechController, preparing...")
            Task {
                await prepareTrainingAudioDependenciesIfNeeded()
            }
            return
        }
        guard !recording else { return }
        appDebugLog("🎤 [AutoListen] ✅ STARTING recording")
        shouldEvaluateAfterStop = true
        speechController.startRecording(localeIdentifier: localeIdentifierForRecognition)
    }

    func stopListeningForTyping() {
        shouldEvaluateAfterStop = false
        if speechController?.isRecording == true {
            speechController?.stopRecording()
        }
        speaker?.stop()
        isMicPulseVisible = false
    }

    func handleAudioModeChange(isEnabled: Bool) {
        if !isEnabled {
            stopListeningForTyping()
            showingTypedAnswerInput = true
        } else if session.hasStartedTraining, currentCard != nil, !showingTypedAnswerInput {
            speakCurrentPrompt()
        }
    }
}
