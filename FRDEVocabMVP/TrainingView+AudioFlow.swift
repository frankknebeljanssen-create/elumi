import SwiftUI

extension TrainingView {
    func speakCurrentPrompt() {
        guard !isArticleMode, !isVerbMode else { return }
        guard let currentCard else {
            return
        }
        stopListeningForTyping()
        guard isAudioModeEnabled else {
            print("🔊 [Speak] ❌ audioMode disabled (sounds=\(feedbackPlayer.areSoundsEnabled))")
            showingTypedAnswerInput = true
            return
        }
        guard let speaker else {
            print("🔊 [Speak] ❌ no speaker (runtimeSpeaker=\(runtimeSpeaker != nil))")
            showingTypedAnswerInput = true
            return
        }
        print("🔊 [Speak] ✅ speaking: \(currentCard.prompt)")
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
        guard !verbMCLocked, session.currentTrainingItem != nil else { return }
        let isSpeed = session.isSpeedRound && session.speedRoundTimeRemaining > 0
        verbMCLocked = true
        verbMCSelected = option
        let isCorrect = option.lowercased() == verbCorrectAnswer.lowercased()

        if isCorrect {
            feedbackPlayer.playStudySuccess()
            if isSpeed { session.speedRoundScore += 1 }
            trainingCorrectCount += 1
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
        // TrainingSessionController+DictionarySelection). Distraktoren sind also
        // ebenfalls Infinitive — same form as correct answer.
        let allVerbOptions: [String] = StandardVocabularyLoader.allEntries
            .filter { $0.wordClass == "verb" && !$0.target.isEmpty && !$0.sourceDisplay.isEmpty }
            .map { isAnswerGerman ? $0.target : $0.sourceDisplay }

        // Dedup case-insensitive, schließe correctAnswer aus (nur ein Treffer in options)
        var seenKeys: Set<String> = [correctKey]
        var pool: [String] = []
        for candidate in allVerbOptions {
            let k = candidate.lowercased()
            if seenKeys.contains(k) { continue }
            seenKeys.insert(k)
            pool.append(candidate)
        }

        let distractors = Array(pool.shuffled().prefix(7))
        var options = [correctAnswer] + distractors
        // SAFETY: garantiert, dass correctAnswer IMMER in den Optionen enthalten ist
        // (schützt vor Edge-Cases, z.B. leerem Pool).
        if !options.contains(where: { $0.lowercased() == correctKey }) {
            options.append(correctAnswer)
        }
        options.shuffle()
        verbMCOptions = options
    }

    func submitArticle(_ article: String) {
        guard !articleLocked, let correctArticle else { return }
        let isSpeed = session.isSpeedRound && session.speedRoundTimeRemaining > 0
        articleLocked = true
        let isCorrect = article.lowercased() == correctArticle.lowercased()

        if isCorrect {
            feedbackPlayer.playStudySuccess()
            if isSpeed { session.speedRoundScore += 1 }
            trainingCorrectCount += 1
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
        // Don't auto-listen in article or verb mode
        guard !isArticleMode, !isVerbMode else { return }

        let started = session.hasStartedTraining
        let hasCard = currentCard != nil
        let audioOn = isAudioModeEnabled
        let speechOK = canUseSpeechRecognition
        let typing = showingTypedAnswerInput
        let focused = typedAnswerFieldFocused
        let hasController = speechController != nil
        let recording = speechController?.isRecording == true
        let authStatus = speechController?.authorizationStatus.rawValue ?? -1

        print("🎤 [AutoListen] started=\(started) card=\(hasCard) audio=\(audioOn) speechPerm=\(speechOK)(auth=\(authStatus)) typing=\(typing) focused=\(focused) controller=\(hasController) recording=\(recording)")

        guard started, hasCard else { return }
        guard audioOn, speechOK else {
            print("🎤 [AutoListen] ❌ blocked: audioMode=\(audioOn) speechPerm=\(speechOK)")
            return
        }
        guard !typing, !focused else {
            print("🎤 [AutoListen] ❌ blocked: typing=\(typing) focused=\(focused)")
            return
        }
        guard let speechController else {
            print("🎤 [AutoListen] ❌ no speechController, preparing...")
            Task {
                await prepareTrainingAudioDependenciesIfNeeded()
            }
            return
        }
        guard !recording else { return }
        print("🎤 [AutoListen] ✅ STARTING recording")
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
