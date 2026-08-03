import SwiftUI

extension QuizView {
    var quizRootContent: some View {
        ZStack(alignment: .top) {
            Group {
                if session.isShowingResult {
                    // **Daily Drop Modul 2.5** — Count-Chain: nahtlos, keine
                    // Zwischen-Summary (Auto-Advance via onChange). `Color.clear`
                    // verhindert einen „0 von 5"-Flash bis `replaceTop` greift.
                    if isCountChainStep {
                        Color.clear
                    } else {
                        quizResultScreen
                    }
                } else if session.questions.isEmpty {
                    // **Daily Drop Modul 2.7** — Count-Modus: kein Setup-Blitz
                    // während die Fragen async laden; sauberes `Color.clear`
                    // bis die erste Frage steht (echte Frage wird nie versteckt,
                    // weil dieser Zweig nur bei `questions.isEmpty` greift).
                    if isCountChainStep {
                        Color.clear
                    } else {
                        quizSetupScreen
                    }
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
            // **Erstnutzer-Hint (2026-06-09)** — erklärt, was das Quiz
            // ist und welche Einstellungen man vorher trifft.
            .hintBubble(
                id: "quiz_intro",
                text: """
                Im Quiz findest du raus, was schon wirklich sitzt.
                Du bekommst gemischte Fragen: mal ankreuzen, mal selbst eintippen.
                Vorher wählst du die Liste und wie viele Fragen es sein sollen.
                Am Ende siehst du, was du schon kannst — und was noch wackelt.
                """
            )
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
            // **Daily Drop Modul 2.8 (2026-05-23)** — Tippfeld-Fokus → globalen
            // Footer ausblenden (bewiesener Chat-Mechanismus, hält die
            // Tastatur davon ab, die View hochzuschieben). Reset in
            // handleQuizDisappear.
            .onChange(of: isTypingFieldFocused) { _, isFocused in
                setKeyboardChromeHidden?(isFocused)
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
