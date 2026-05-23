import SwiftUI

extension QuizView {
    func handleQuizAppear() {
        // Apply launch context from Import Completion
        if let ctx = launchContext, let preferredListID = ctx.preferredListID {
            session.selectedListIDs = [preferredListID]
        } else {
            // **Bug-Fix 2026-05-04 (Punkt 2 follow-up)** — Restore
            // unconditional. Vorher nur wenn `selectedListIDs.isEmpty` —
            // dadurch wurde eine Listen-Tab-Auswahl, die zwischen
            // zwei Quiz-Opens passiert ist, nicht übernommen, weil das
            // alte selectedListIDs-Set noch vom vorherigen Open lebte.
            // Restore liest jetzt jedes Mal aus der globalen Single-
            // Source-of-Truth (`VocabularyListSelectionResolver`).
            session.restoreSelectedListIDs()
        }
        appDebugLog("🧩 [Quiz] handleQuizAppear, availableLists=\(availableQuizLists.count), selectedIDs=\(session.selectedListIDs)")
        session.syncSelectedLists(availableLists: availableQuizLists)
        session.refreshMergedItemsIfNeeded(
            from: selectedQuizLists,
            direction: selectedAppDirection,
            force: session.cachedMergedItems.isEmpty
        )
        // **Daily Drop Modul 1 (2026-05-23)** — Count-Cap-Modus aus dem
        // Launch-Context. WICHTIG: `atomicOnly` ZUERST setzen — das
        // Setzen von `questionCountOption` triggert via onChange den
        // Prebuild (`handleQuizQuestionCountChange`), der `atomicOnly`
        // schon sehen muss. `invalidatePreparedQuestions()` verwirft
        // einen evtl. bereits vorbereiteten (nicht-atomaren) Batch,
        // damit `startQuiz()` frisch atomar baut. nil-gated → regulär.
        if let ddCount = launchContext?.dailyDropCount {
            session.atomicOnly = launchContext?.atomicOnly ?? false
            if let option = QuizQuestionCountOption(rawValue: ddCount) {
                session.questionCountOption = option
            }
            session.invalidatePreparedQuestions()
        }

        // Auto-start quiz from Import Completion
        if launchContext?.shouldAutoStart == true, session.questions.isEmpty {
            startQuiz()
        }
    }

    func handleQuizCustomListsChange() {
        session.clearMergedCache()
        session.syncSelectedLists(availableLists: availableQuizLists)
        session.refreshMergedItemsIfNeeded(
            from: selectedQuizLists,
            direction: selectedAppDirection,
            force: true
        )
    }

    func handleQuizSelectedListsChange() {
        session.refreshMergedItemsIfNeeded(
            from: selectedQuizLists,
            direction: selectedAppDirection
        )
    }

    func handleQuizDirectionChange() {
        session.refreshMergedItemsIfNeeded(
            from: selectedQuizLists,
            direction: selectedAppDirection
        )
    }

    func handleQuizQuestionCountChange() {
        session.invalidatePreparedQuestions()
        session.prepareQuestionsIfPossible()
    }

    func handleQuizResultVisibilityChange(_ isShowingResult: Bool) {
        guard isShowingResult else { return }
        prepareQuizRewards()
        // **Daily Drop Modul 2.5 (2026-05-23)** — Count-Chain: nahtlos.
        // Reward persistieren (setzt `quizSessionOutcome`) und direkt zur
        // nächsten Aufgabe; beim letzten Step liefert `advanceChain`
        // `.trainingChainComplete` → Complete-Summary. Zeit-Chain und der
        // isolierte Modul-1-Test (isCountChainStep == false) zeigen die
        // Zwischen-Summary + CTA wie bisher.
        if isCountChainStep {
            persistHeartsIfNeeded()
            chainAdvance?(quizSessionOutcome ?? .empty)
        }
    }

    /// **Stufe 4b-Modal-Refactor / Chain-Auto-Start (2026-05-02)** —
    /// Wird vom `.onChange(of: session.cachedCandidates.count)`-Handler
    /// in `QuizView+Layout.body` getriggert. Retry-Pfad für Auto-Start
    /// nach asynchronem Candidate-Loading: bei Modul-Mount mit
    /// `shouldAutoStart=true` (Chain-Step oder Import-Completion) sind
    /// die Candidates noch nicht gecachet, der Sync-Aufruf von
    /// `startQuiz()` aus `handleQuizAppear` abortet, der Setup-Screen
    /// rendert. Sobald die Candidates async ankommen (Count >= 2),
    /// holen wir den Auto-Start nach. Guards halten den Pfad
    /// idempotent — Re-Mounts oder Question-Count-Changes triggern
    /// keinen unbeabsichtigten zweiten Start.
    func handleQuizCandidatesChange(candidateCount: Int) {
        guard launchContext?.shouldAutoStart == true,
              session.questions.isEmpty,
              !session.isPreparingQuiz,
              candidateCount >= 2 else {
            return
        }
        startQuiz()
    }

    func handleQuizDisappear() {
        cancelAdvanceTask()
    }
}
