import SwiftUI

extension QuizView {
    func handleQuizAppear() {
        // Apply launch context from Import Completion
        if let ctx = launchContext, let preferredListID = ctx.preferredListID {
            session.selectedListIDs = [preferredListID]
        } else if session.selectedListIDs.isEmpty {
            session.restoreSelectedListIDs()
        }
        print("🧩 [Quiz] handleQuizAppear, availableLists=\(availableQuizLists.count), selectedIDs=\(session.selectedListIDs)")
        session.syncSelectedLists(availableLists: availableQuizLists)
        session.refreshMergedItemsIfNeeded(
            from: selectedQuizLists,
            direction: selectedAppDirection,
            force: session.cachedMergedItems.isEmpty
        )
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
    }

    func handleQuizDisappear() {
        cancelAdvanceTask()
    }
}
