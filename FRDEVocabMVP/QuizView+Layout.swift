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
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .appLocalChrome(enabled: !usesGlobalChrome) {
                AppTopBar(onBack: { handleBackNavigation() }, onInfo: openInfo)
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
            // **Stufe 4b-Modal-Refactor / Chain-Auto-Start (2026-05-02)** —
            // Quiz-spezifisches Async-Race-Fix. `handleQuizAppear` ruft
            // `startQuiz()` direkt nach Mount, aber Candidates werden in
            // `QuizSessionController+MergeFlow.rebuildMergedItems` über
            // ein detached Task geladen (Z. 65-82). Beim sync-Aufruf
            // direkt nach Mount sind `cachedCandidates` noch leer →
            // `session.startQuiz(direction:)` abortet via
            // `guard candidates.count >= 2`. Hier holen wir den Retry
            // nach: wenn die Candidates async ankommen UND der
            // ursprüngliche Auto-Start aus dem Chain-Context kam UND
            // noch keine Quiz-Session läuft, triggern wir `startQuiz()`
            // erneut. Idempotent über die Guards (questions.isEmpty,
            // !isPreparingQuiz). Andere Module (Karteikarten, Training,
            // Verbformen) sind nicht betroffen, weil dort der Deck-Bau
            // synchron läuft.
            .onChange(of: session.cachedCandidates.count) { _, newCount in
                handleQuizCandidatesChange(candidateCount: newCount)
            }
            .onChange(of: session.isShowingResult) { _, isShowingResult in
                handleQuizResultVisibilityChange(isShowingResult)
            }
            // **Gruppe-3-Migration (2026-05-22)** — ehemals totes
            // `.sheet(isPresented: $showingQuizListPicker)` entfernt
            // (wurde nie getriggert). Ersetzt durch:
            .navigationDestination(isPresented: $quizListPickerActive) {
                UnifiedListCategoryPicker(
                    availableLists: availableQuizLists,
                    selectedIDs: session.selectedListIDs,
                    onCommit: { session.selectedListIDs = $0 },
                    accent: sectionStyle.accent,
                    singleSelect: false,
                    includeWoerterbuch: false,
                    itemLabel: "Einträge",
                    feedbackPlayer: feedbackPlayer,
                    onHome: goHome,
                    onSettings: { openSettings() }
                )
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
            }
            .onDisappear {
                handleQuizDisappear()
            }
            // **Stufe 4b-Modal-Refactor (2026-05-02)** — registriert
            // den Quiz-spezifischen Force-Done-Closure für den
            // „Jetzt weiter"-CTA des `ChainCutoffModal`. Token-
            // basiert für Race-Safety bei Chain-Step-Transitions.
            // Closure läuft über `forceQuizDoneFromChainTimer()` —
            // Idempotenz-Guard dort eingebaut
            // (`!session.isShowingResult`).
            .onAppear {
                forceAdvanceHandlerToken = TrainingChainStore.shared.registerForceAdvanceHandler {
                    forceQuizDoneFromChainTimer()
                }
            }
            .onDisappear {
                TrainingChainStore.shared.unregisterForceAdvanceHandler(token: forceAdvanceHandlerToken)
                forceAdvanceHandlerToken = nil
            }
    }
}
