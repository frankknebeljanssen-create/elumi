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
            scheduleFeedbackTask(after: isSpeed ? 0.3 : 1.0) {
                verbMCSelected = nil
                verbMCLocked = false
                if isSpeed {
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
        let correctAnswer = (isFRtoDe ? item.german : item.french).lowercased()

        let isAnswerGerman = isFRtoDe
        let allVerbOptions = StandardVocabularyLoader.allEntries
            .filter { $0.wordClass == "verb" && !$0.target.isEmpty && !$0.sourceDisplay.isEmpty }
            .map { (isAnswerGerman ? $0.target : $0.sourceDisplay).lowercased() }

        let pool = Array(Set(allVerbOptions.filter { $0 != correctAnswer }))
        let shuffled = pool.shuffled()
        let distractors = Array(shuffled.prefix(7))

        var options = [correctAnswer] + distractors
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
            lastResult = ScoreResult(label: "Falsch 😕", detail: "\(correctArticle) \(articlePromptText ?? "")")
            scheduleFeedbackTask(after: isSpeed ? 0.25 : 1.2) {
                articleLocked = false
                lastResult = nil
                showingArticleTranslation = false
                if isSpeed {
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
