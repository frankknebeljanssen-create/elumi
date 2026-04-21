import SwiftUI

extension QuizView {
    var quizRootContent: some View {
        ZStack(alignment: .top) {
            Group {
                if session.isShowingResult {
                    quizResultScreen
                } else if session.questions.isEmpty {
                    quizSetupScreen
                } else {
                    quizSessionScreen
                }
            }

            // Combo-Toast-Overlay — zeigt bei 5/10/15/... richtigen Antworten
            // in Folge einen kurzen Bonus-Hinweis. Blockiert keine Eingaben.
            ComboToastOverlay()
        }
    }

    var body: some View {
        quizRootContent
            .tint(sectionStyle.accent)
            .appScreenBackground(sectionStyle)
            .dismissKeyboardOnTap()
            .toolbar(.hidden, for: .navigationBar)
            .appLocalChrome(enabled: !usesGlobalChrome) {
                AppTopBar(
                    onBack: { handleBackNavigation() },
                    onInfo: openInfo,
                    leadingModuleIcon: .quiz
                )
                    .padding(.horizontal, AppLayout.screenPadding)
                    .padding(.top, quizTopBarSpacing)
            } bottomBar: {
                AppBottomBar(
                    feedbackPlayer: feedbackPlayer,
                    onHome: { dismissToHome() },
                    onFavorite: nil,
                    onScan: nil,
                    onSettings: { openSettings() }
                )
            }
            .onAppear {
                handleQuizAppear()
            }
            .onChange(of: listStore.customLists) { _, _ in
                handleQuizCustomListsChange()
            }
            .onChange(of: session.selectedListIDs) { _, _ in
                handleQuizSelectedListsChange()
            }
            .onChange(of: selectedAppDirectionRaw) { _, _ in
                handleQuizDirectionChange()
            }
            .onChange(of: session.questionCountOption) { _, _ in
                handleQuizQuestionCountChange()
            }
            .onChange(of: session.isShowingResult) { _, isShowingResult in
                handleQuizResultVisibilityChange(isShowingResult)
            }
            .sheet(isPresented: $showingQuizListPicker) {
                FlashcardStackComposerSheet(
                    style: sectionStyle,
                    lists: availableQuizLists,
                    selectedListIDs: session.selectedListIDs,
                    language: selectedAppDirection.sourceLanguage,
                    cardTypeFilter: nil
                ) { updatedSelection in
                    session.selectedListIDs = updatedSelection
                }
            }
            .onDisappear {
                handleQuizDisappear()
            }
    }
}
