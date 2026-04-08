import SwiftUI

extension TrainingView {
    func speakCurrentPrompt() {
        guard let currentCard else {
            print("🔊 [Speak] ❌ no currentCard")
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
        guard !verbMCLocked, let currentCard else { return }
        verbMCLocked = true
        verbMCSelected = option
        let gotNorm = option.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let expectedNorm = currentCard.answer.lowercased().folding(options: .diacriticInsensitive, locale: .current)
        let isCorrect = gotNorm == expectedNorm

        if isCorrect {
            feedbackPlayer.playStudySuccess()
            scheduleFeedbackTask(after: 0.8) {
                verbMCSelected = nil
                verbMCLocked = false
                loadNextTrainingCard()
                prepareVerbMCOptions()
            }
        } else {
            feedbackPlayer.playStudyError()
            session.incrementFailedAttempts()
            scheduleFeedbackTask(after: 1.5) {
                verbMCSelected = nil
                verbMCLocked = false
            }
        }
    }

    func prepareVerbMCOptions() {
        guard let currentCard else {
            verbMCOptions = []
            return
        }
        let correctAnswer = currentCard.answer
        let correctLower = correctAnswer.lowercased()

        // Pick distractors from same language as the answer
        let isAnswerGerman = currentCard.answerLanguageCode == "de-DE"
        let allVerbOptions = StandardVocabularyLoader.allEntries
            .filter { $0.wordClass == "verb" && !$0.target.isEmpty && !$0.sourceDisplay.isEmpty }
            .map { isAnswerGerman ? $0.target : $0.sourceDisplay }

        let pool = Array(Set(allVerbOptions.filter { $0.lowercased() != correctLower }))
        let shuffled = pool.shuffled()
        let distractors = Array(shuffled.prefix(7))

        var options = [correctAnswer] + distractors
        options.shuffle()
        verbMCOptions = options
    }

    func submitArticle(_ article: String) {
        guard !articleLocked, let correctArticle else { return }
        articleLocked = true
        let isCorrect = article.lowercased() == correctArticle.lowercased()

        if isCorrect {
            feedbackPlayer.playStudySuccess()
            lastResult = ScoreResult(label: "Richtig 🙂", detail: "\(correctArticle) \(articlePromptText ?? "")")
            scheduleFeedbackTask(after: 0.8) {
                articleAnswer = nil
                articleLocked = false
                lastResult = nil
                showingArticleTranslation = false
                loadNextTrainingCard()
            }
        } else {
            feedbackPlayer.playStudyError()
            session.incrementFailedAttempts()
            lastResult = ScoreResult(label: "Falsch 😕", detail: "\(correctArticle) \(articlePromptText ?? "")")
            scheduleFeedbackTask(after: 1.2) {
                articleLocked = false
                lastResult = nil
                showingArticleTranslation = false
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
