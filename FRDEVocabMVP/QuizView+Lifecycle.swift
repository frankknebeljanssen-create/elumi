import SwiftUI

extension QuizView {
    func handleQuizAppear() {
        session.syncSelectedLists(availableLists: availableQuizLists)
        session.refreshMergedItemsIfNeeded(
            from: selectedQuizLists,
            direction: selectedAppDirection,
            force: session.cachedMergedItems.isEmpty
        )
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
