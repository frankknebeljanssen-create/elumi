import Foundation

extension QuizSessionController {
    func completeCurrentQuestion(correct: Bool) {
        answeredResults.append(correct)

        // **Daily Drop Modul 2 (2026-05-23)** — Smooth-Counter für die
        // persistente „Übung X von N"-Bar. No-op außerhalb Count-Modus.
        TrainingChainStore.shared.noteExerciseAnswered()

        // Lernstatus-Signal: bevor der Cursor auf die nächste Frage
        // rutscht, die aktuelle Frage in den Per-Item-Store melden. Für
        // MultipleChoice und Typing ist das Mapping eindeutig (prompt ↔
        // correctAnswer je nach Direction). Matching- und FillBlanks-
        // Fragen werden bewusst **nicht** getrackt — bei Matching gibt
        // es mehrere Paare pro Frage und nur ein einziges `correct`-Bit,
        // bei FillBlanks ist `correctAnswer` nur das Blank-Wort (kein
        // sauberer fr/de-Tupel). Lieber keine Daten als verzerrte.
        recordLernstatusForCurrentQuestion(correct: correct)

        // Combo-Tracking für ProgressService-Bonus (alle 5 richtig in Folge).
        // Matching/FillBlanks filtern „had any mistake" bereits auf View-
        // Ebene, bevor sie `completeCurrentQuestion` rufen. MC & Typing
        // haben keine Retries pro Frage — deshalb ist hier `firstAttempt`
        // effektiv immer `true`.
        streak.recordAnswer(correct: correct)

        if currentQuestionIndex + 1 >= questions.count {
            if isLoadingRemainingQuestions {
                currentQuestionIndex += 1
            } else {
                isShowingResult = true
                // Session endgültig abgeschlossen → Resume-Snapshot weg.
                QuizSessionResumeStore.clear()
            }
        } else {
            currentQuestionIndex += 1
        }

        // Nach jeder Antwort Snapshot aktualisieren, damit ein App-Kill
        // nicht zwischen zwei Fragen Fortschritt verliert. Der Snapshot
        // wird geräuschlos beim `isShowingResult = true` oben (oder bei
        // `resetToSetup`) verworfen.
        persistResumeSnapshotIfEligible()
    }

    /// Extrahiert prompt/correctAnswer/category aus der aktuellen Frage
    /// und meldet sie an den `ItemLearningStatusRecorder`. Direction wird
    /// **direkt aus `UserDefaults(appDirectionKey)`** gelesen — der
    /// `QuizSessionController` hält keine eigene Direction-Property, und
    /// der Rest des Quiz-Codes (`QuizSessionController+Generation.swift`)
    /// nutzt denselben Zugriffspfad.
    private func recordLernstatusForCurrentQuestion(correct: Bool) {
        guard currentQuestionIndex < questions.count else { return }
        let question = questions[currentQuestionIndex]

        // Nur MC + Typing liefern einen sauberen prompt/correctAnswer-Tupel.
        let prompt: String
        let correctAnswer: String
        switch question {
        case .multipleChoice(let q):
            prompt = q.prompt
            correctAnswer = q.correctAnswer
        case .typing(let q):
            prompt = q.prompt
            correctAnswer = q.correctAnswer
        case .matching, .fillBlanks:
            return
        }

        // Category → CardType (nur „Wörter" / „Phrasen" im Projekt).
        guard let cardType = CardType.allCases.first(where: { $0.categoryName == question.category }) else {
            return
        }

        // Direction aus dem globalen @AppStorage-Key. Fallback auf
        // `.frenchToGerman` — derselbe Default wie überall sonst in der App.
        let directionRaw = UserDefaults.standard.string(forKey: appDirectionKey) ?? ""
        let direction = Direction(rawValue: directionRaw) ?? .frenchToGerman

        ItemLearningStatusRecorder.recordFromQuiz(
            prompt: prompt,
            correctAnswer: correctAnswer,
            direction: direction,
            cardType: cardType,
            correct: correct
        )
    }

    func resetToSetup() {
        if !questions.isEmpty {
            reusedCandidateIDs.formUnion(QuizBuildService.consumedCandidateIDs(from: questions))
        }
        quizPreparationGeneration += 1
        isPreparingQuiz = false
        questions = []
        currentQuestionIndex = 0
        answeredResults = []
        isShowingResult = false
        preparedQuestions = []
        plannedQuestionCount = 0
        isLoadingRemainingQuestions = false
        // Combo-Tracking zurücksetzen, damit nächste Session sauber startet.
        streak.reset()
        sessionRewardConsumed = false
        // Harter Reset → Resume-Snapshot verwerfen. Sonst würde der User
        // beim nächsten Start in eine scheinbar laufende Runde zurück-
        // geworfen, obwohl er gerade die Summary gesehen hat.
        QuizSessionResumeStore.clear()
    }

    // MARK: - Session-Resume

    /// Speichert den aktuellen Quiz-Zustand für spätere Wiederherstellung.
    /// Nur aktiv, wenn eine Runde läuft (Fragen generiert, nicht auf
    /// Result-Screen).
    func persistResumeSnapshotIfEligible() {
        guard !questions.isEmpty, !isShowingResult else { return }

        let directionRaw = UserDefaults.standard.string(forKey: appDirectionKey) ?? Direction.frenchToGerman.rawValue
        let sortedIDs = Array(selectedListIDs)
        let state = QuizSessionResumeState(
            directionRaw: directionRaw,
            selectedListIDs: sortedIDs,
            questionCountOptionRaw: questionCountOption.rawValue,
            questions: questions,
            currentQuestionIndex: currentQuestionIndex,
            answeredResults: answeredResults,
            streak: streak,
            configFingerprint: QuizSessionResumeStore.fingerprint(
                direction: directionRaw,
                selectedListIDs: sortedIDs,
                questionCountOptionRaw: questionCountOption.rawValue
            ),
            lastUpdatedEpoch: Date().timeIntervalSince1970
        )
        // Debounced Background-Write — nach jeder Quiz-Antwort kein
        // synchroner Main-Thread-JSON-Encode mehr.
        QuizSessionResumeStore.scheduleSave(state)
    }

    /// Versucht, eine laufende Quiz-Session aus dem Snapshot zurück-
    /// zuladen. Gibt `true` zurück, wenn restored wurde — Caller muss
    /// dann keinen frischen Build mehr anstoßen.
    @discardableResult
    func tryRestoreResumeSnapshot(
        expectedDirection: Direction,
        expectedListIDs: Set<UUID>,
        expectedCount: QuizQuestionCountOption
    ) -> Bool {
        guard let snapshot = QuizSessionResumeStore.load() else { return false }
        let expectedFP = QuizSessionResumeStore.fingerprint(
            direction: expectedDirection.rawValue,
            selectedListIDs: Array(expectedListIDs),
            questionCountOptionRaw: expectedCount.rawValue
        )
        guard snapshot.configFingerprint == expectedFP else {
            // Setup hat sich geändert → stumm verwerfen, Caller baut frisch.
            QuizSessionResumeStore.clear()
            return false
        }
        guard !snapshot.questions.isEmpty else {
            QuizSessionResumeStore.clear()
            return false
        }
        guard snapshot.currentQuestionIndex < snapshot.questions.count else {
            // Snapshot war am Ende (vor `isShowingResult = true`) — als
            // würde gerade die letzte Frage beantwortet werden. Lieber
            // eine frische Runde.
            QuizSessionResumeStore.clear()
            return false
        }

        questions = snapshot.questions
        currentQuestionIndex = snapshot.currentQuestionIndex
        answeredResults = snapshot.answeredResults
        streak = snapshot.streak
        plannedQuestionCount = snapshot.questions.count
        preparedQuestions = snapshot.questions
        sessionRewardConsumed = false
        isShowingResult = false
        isPreparingQuiz = false
        isLoadingRemainingQuestions = false
        return true
    }
}
