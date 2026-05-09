import SwiftUI

extension FlashcardsView {
    @ViewBuilder
    var flashcardsRootContent: some View {
        if setup.isShowingSetup {
            flashcardSetupScreen
        } else {
            flashcardSessionScreen
        }
    }

    @ViewBuilder
    var flashcardTypedAnswerOverlay: some View {
        // **Sweep-C-Wiring-Fix 2026-05-08** — Overlay-Guard fehlte
        // der `answerMode == .tap`-Pfad. In Tap-Mode-Sessions ist
        // `showingTypedAnswerInput` initial `false` (Default-State),
        // aber die Typed-Answer-Card MUSS trotzdem als primäre
        // Eingabe gerendert werden — sie ist der einzige Eingabe-Pfad
        // im Tap-Mode (Mikro entfällt, Speaker-only Action-Row).
        // Vorher fiel der Overlay-Guard durch → Card wurde nie
        // gemountet → User sah nur den Lautsprecher, keine Eingabe.
        if !setup.isShowingSetup
            && !isFlashcardSessionCompleted
            && (interaction.showingTypedAnswerInput || interaction.answerMode == .tap) {
            VStack {
                Spacer()
                flashcardTypedAnswerCard
                    .padding(.horizontal, AppLayout.screenPadding + flashcardSessionCardInset)
                    // **2026-05-08 Padding-Cleanup** — `footerHeight`
                    // entfernt; nach der safeAreaInset-Migration
                    // reserviert das System Footer-Höhe automatisch.
                    // Atemraum bleibt mit `flashcardBottomBarSpacing
                    // + Spacing.sm`.
                    .padding(.bottom, flashcardBottomBarSpacing + AppTheme.Spacing.sm)
            }
            .zIndex(3)
        }
    }

    /// **Bug-Fix 2026-05-07** — `AnyView`-Wrapper entfernt. Vorher
    /// erasierte der Wrapper den statischen View-Type, was während
    /// der NavigationStack-Push-Animation zu einem kurzen Flash des
    /// System-Default-Back-Buttons führte (User-Befund: weißer
    /// Chevron blitzt kurz auf, bevor der Custom-Pink-Chevron
    /// erscheint). Mit `some View`-Inferenz bleibt der Type sauber
    /// trackbar, der Push-Übergang rendert direkt mit dem Custom-
    /// Chevron.
    @ViewBuilder
    var flashcardsBodyContent: some View {
        ZStack(alignment: .top) {
            flashcardsRootContent
            flashcardTypedAnswerOverlay
            // Combo-Toast-Overlay (Streak-Moments 3/5/10, siehe
            // `FeedbackConfig`) + Milestone-Overlay (seltene, größere
            // Momente wie Session-Ende).
            ComboToastOverlay()
            MilestoneOverlayView()
        }
        // **Phase 8.2 Bug-Fix**: NavigationDestination wandert vom
        // Setup-Screen-Modifier in den Body-Wrapper hoch, damit der
        // Push-Pfad SETUP ↔ SESSION überlebt. Vorher: setup.isShowingSetup
        // = false flippte den Body, was den Setup-Screen ENTFERNTE
        // → auch die `.navigationDestination` verschwand → SwiftUI
        // popte PersonalDecksView automatisch + dismiss() popte
        // nochmal → User landete eine Ebene zu tief im Setup statt
        // in der gerade frisch konfigurierten Session.
        .navigationDestination(isPresented: $isShowingPersonalDecksScreen) {
            PersonalDecksView(
                personalDeckStore: personalDeckStore,
                listStore: listStore,
                sectionStyle: sectionStyle,
                language: selectedAppDirection.sourceLanguage,
                cardTypeFilter: setup.selectedSetupContent.preferredCardType,
                onStartDeck: { deck in
                    // **Bug-Fix Phase 8.2 (v4)**: Parent steuert
                    // beides — Pop UND Session-Start. Vorher hat
                    // PersonalDecksView selbst dismiss() gerufen,
                    // das hat in Kombination mit dem Body-Flip zu
                    // einer Race geführt, in der der Setup-Screen
                    // wieder oben aufpoppte. Jetzt: erst pop, dann
                    // start — beide synchronen State-Mutationen
                    // werden von SwiftUI gebatched.
                    isShowingPersonalDecksScreen = false
                    startPersonalDeckSession(deck)
                }
            )
        }
    }

    var flashcardsTopBar: some View {
        AppTopBar(onBack: { handleBackNavigation() }, onInfo: openInfo)
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.top, flashcardTopBarSpacing)
    }

    var flashcardsBottomBar: some View {
        AppBottomBar(
            feedbackPlayer: feedbackPlayer,
            onHome: { dismissToHome() },
            onFavorite: nil,
            onScan: nil,
            onSettings: { openSettings() }
        )
    }

    var flashcardsChromeContent: AnyView {
        AnyView(
            flashcardsBodyContent
                .tint(sectionStyle.accent)
                .appScreenBackground(sectionStyle)
                .dismissKeyboardOnTap()
                .simultaneousGesture(
                    TapGesture().onEnded {
                        dismissTypedAnswerFocus()
                    }
                )
                .navigationBarBackButtonHidden(true)
                .toolbar(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        if setup.isShowingSetup && !setup.isUsingAllCardCount {
                            Spacer()
                            Button("OK") {
                                setup.confirmCardCountEntry()
                            }
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                        }
                    }
                }
                .appLocalChrome(enabled: !usesGlobalChrome) {
                    flashcardsTopBar
                } bottomBar: {
                    flashcardsBottomBar
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    if setup.isShowingSetup && !setup.isUsingAllCardCount && isCardCountFieldFocused {
                        EmptyView()
                    }
                }
        )
    }

    var body: some View {
        flashcardsLifecycleContent
            // **Stufe 4b-Modal-Refactor (2026-05-02)** — registriert
            // den modul-spezifischen Force-Done-Closure für den
            // „Jetzt weiter"-CTA des `ChainCutoffModal` direkt am
            // Store. Token-basiert für Race-Safety bei Chain-Step-
            // Transitions. Closure läuft über den existierenden
            // 4b-1-Helper auf dem `FlashcardSessionStore` —
            // Idempotenz-Guard ist dort eingebaut (`isCompleted`).
            .onAppear {
                forceAdvanceHandlerToken = TrainingChainStore.shared.registerForceAdvanceHandler { [weak sessionStore] in
                    sessionStore?.markCurrentSessionDoneFromChainTimer()
                }
            }
            .onDisappear {
                TrainingChainStore.shared.unregisterForceAdvanceHandler(token: forceAdvanceHandlerToken)
                forceAdvanceHandlerToken = nil
            }
    }

    var flashcardSessionScreen: some View {
        VStack(spacing: 0) {
            // **Block 2 (2026-05-02)** — User-Spec: im Chain-Mode-on-
            // Completion kein Modul-Chevron + Title mehr. Der Chain-
            // Header (3 Step-Cards + Timer) via
            // `ChainTimerOverlayModifier` trägt die Schritt-Identität.
            // Während aktiver Session (vor Completion) bleibt der
            // Header sichtbar — auch im Chain-Mode, weil er da als
            // Setup-Skip-Header dient (Zurück → Setup-Card o.ä.).
            // Erst auf der Completion-Card im Chain wird er
            // versteckt.
            // Kompakter Header: kleiner „< Zurück" links + zentrierter Titel.
            // Ersetzt die alte ScreenHeaderCard + den großen Zurück-Button.
            if !(isFlashcardSessionCompleted && launchContext?.chainContext != nil) {
                flashcardSessionHeader
            }

            if isFlashcardSessionCompleted {
                Spacer().frame(height: AppTheme.Spacing.sm)

                flashcardCompletionCard
                    .padding(.horizontal, flashcardSessionCardInset)

                Spacer().frame(height: AppTheme.Spacing.md)

                Button {
                    handleBackNavigation()
                } label: {
                    Label("Zurück", systemImage: "arrow.left")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 46)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                .padding(.horizontal, flashcardSessionCardInset)
            } else {
                if isWaitingToStart {
                    // "Zum Starten tippen" overlay
                    Spacer()

                    VStack(spacing: 16) {
                        Image(systemName: "hand.tap.fill")
                            .font(.system(size: 44, weight: .bold))
                            .foregroundStyle(sectionStyle.accent)
                        Text("Zum Starten tippen")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        isWaitingToStart = false
                        feedbackPlayer.playCardFlip()
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 200_000_000)
                            speakCurrentPrompt()
                        }
                    }

                    Spacer()
                } else {
                    // Reihenfolge (von oben nach unten):
                    //   1. Kleiner fester Abstand zum Header
                    //   2. Stats-Row (Kann ich / Offen / Nochmal)
                    //   3. Karteikarte
                    //   4. Wisch-Hinweis
                    //   5. Antwort-Card (Spracherkennung)
                    //   6. Mikro / Lautsprecher / Tastatur — bleiben am Footer
                    //
                    // Stats bleiben ÜBER der Karte. Mikro etc. sitzen am unteren
                    // Rand für kurze Tap-Wege.
                    // **User-Revision 2026-04-22 (final)**: Indikator
                    // jetzt mit fixer Höhe (16 pt) — clipped, damit der
                    // Header oben NIE überlappt wird. Text 12 → 11 pt,
                    // Dot 7 → 6 pt für schmaleres Profil. `offset(y: -10)`
                    // schiebt den ganzen Indikator-Layer 10 pt nach
                    // oben, wie gewünscht. Spacer hält die Layout-Höhe
                    // konstant — Stats-Row darunter bewegt sich nicht.
                    ZStack(alignment: .top) {
                        Spacer().frame(height: AppTheme.Spacing.md)
                        if let deck = activePersonalDeckForSession {
                            HStack(spacing: 5) {
                                Circle()
                                    .fill(PersonalDeck.color(for: deck.colorIndex))
                                    .frame(width: 6, height: 6)
                                Text("Mein Stapel · \(deck.name)")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.75))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.7)
                            }
                            .padding(.horizontal, flashcardSessionCardInset)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .offset(y: -10)
                        }
                    }

                    // **Block 2.5 (2026-05-02)** — Stats-Row im Chain-
                    // Mode ausblenden. Subpunkt 1 (User-Spec): die
                    // drei Mini-Tiles („Kann ich" / „Offen" / „Nochmal")
                    // dominieren im Chain-Mode-Pacing visuell; Chain-
                    // Header trägt schon die Step-Identität, Stats-
                    // Tracking ist während eines kurzen Chain-Step
                    // weniger relevant. Außerhalb Chain unverändert
                    // sichtbar.
                    if launchContext?.chainContext == nil {
                        flashcardStatsRow
                            .padding(.horizontal, flashcardSessionCardInset)

                        Spacer().frame(height: AppTheme.Spacing.sm)
                    }

                    flashcardPromptCard
                        .padding(.horizontal, flashcardSessionCardInset)

                    flashcardSwipeHintCard
                        .padding(.horizontal, flashcardSessionCardInset)
                        .padding(.top, 10)

                    // **Phase 8.1** — Elemente unter der Karte ein Stück
                    // weiter nach unten, damit die jetzt größere Karte
                    // ihren Platz bekommt, ohne dass Antwort-Card und
                    // Action-Block in den Footer reinrutschen.
                    //
                    // **2026-05-08 Tap-Mode-Cleanup** — Recognition-
                    // State (`flashcardResponseCard`) + Primary-Actions
                    // (Mikro/Speaker/Tastatur) sind Speech-Mode-only.
                    // Im Tap-Mode entfallen sie komplett, inkl. ihrer
                    // Spacer — die Typed-Answer-Card im Overlay sitzt
                    // dann am Bottom als einzige Eingabe.
                    if interaction.answerMode == .speech {
                        Spacer().frame(height: AppTheme.Spacing.md)

                        flashcardResponseCard
                            .padding(.horizontal, flashcardSessionCardInset)

                        // Größerer Abstand vor dem Action-Block, damit Antwort-
                        // Card und Mikro/Lautsprecher/Tastatur klar voneinander
                        // abgesetzt sind.
                        Spacer().frame(height: 32)

                        flashcardPrimaryActions
                            .padding(.horizontal, flashcardSessionCardInset)
                    }
                }
            }
        }
        .padding(.horizontal, AppLayout.screenPadding)
        // Systemweites Top-Padding — Header-Position wie Quiz-Setup.
        .padding(.top, AppLayout.screenHeaderTopPadding)
        // **2026-05-08 Padding-Cleanup** — `footerHeight` entfernt
        // (safeAreaInset reserviert systemweit). Buffer bleibt mit
        // `flashcardBottomBarSpacing + Spacing.sm`.
        .padding(.bottom, flashcardBottomBarSpacing + AppTheme.Spacing.sm)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var flashcardSetupScreen: some View {
        // **Master-Migration 2026-05-08** — Karteikarten-Setup nutzt
        // jetzt `SessionSetupScreen` als gemeinsame Hülle (Header,
        // ScrollView, GamBar, CTA, Spacings) — identisch zu Quiz,
        // Vokabeln, Nomen, Akzente. Vorher: Eigenbau-Layout mit
        // custom ScrollView + safeAreaInset, Iter-1+2-Compaction-
        // Versuche, Quickstart-Pop-up. Alle Eigen-Pattern wurden
        // verworfen für Pure-Konsistenz mit den anderen Modulen.
        //
        // Section-Reihenfolge:
        //   contextContent: ListCategoryPickerView (DEINE LISTEN —
        //     gleiche Card wie Quiz/Vokabeln, öffnet GlobalListPickerSheet
        //     mit Lernjahr-Filter)
        //   ↓ SessionDirectionRow (showsDirection default true)
        //   optionsContent (in Reihenfolge):
        //     • DictionaryLevel-Card (conditional)
        //     • flashcardCountLimitCard (KARTEN — Karteikarten-only)
        //     • flashcardMasteryThresholdCard (SCHWIERIGKEIT — Karteikarten-only)
        //     • AnswerModeSelector (ANTWORTEN MIT — geteilt mit Vokabeln/Nomen)
        //     • personalDeckSection (EIGENE STAPEL — Karteikarten-only,
        //       conditional sichtbar bei vorhandenen Decks)
        //
        // GamBar + CTA werden vom Master-Wrapper im safeAreaInset
        // gerendert.
        SessionSetupScreen(
            title: "Karteikarten",
            accent: sectionStyle.accent,
            estimate: flashcardsSessionEstimate,
            primaryButtonTitle: "Los geht's!",
            isPrimaryEnabled: canStartSetup,
            // **Chain-Mode XP-Card-Hide (2026-05-02)** — wenn Karteikarten
            // als Chain-Step geöffnet wird, ist die per-Modul-XP-Schätzung
            // irreführend (Chain-Timer ist die einzige Begrenzung).
            showsGamificationBar: launchContext?.chainContext == nil,
            moduleIcon: .karteikarten,
            showsDirectionToggle: true,
            onBack: { handleBackNavigation() },
            onStart: { startFlashcardsFromSetup(autoplayPrompt: true) },
            contextContent: {
                ListCategoryPickerView(
                    availableLists: availableStackLists,
                    selectedListIDs: setup.selectedStackListIDs,
                    accent: sectionStyle.accent,
                    style: sectionStyle,
                    feedbackPlayer: feedbackPlayer,
                    summaryText: "",
                    itemLabel: "Karten",
                    onSelectionChanged: { setup.selectedStackListIDs = $0 },
                    onHome: { dismissToHome() }
                )
            },
            optionsContent: {
                if isDictionarySelectedInStack {
                    flashcardDictionaryLevelCard
                }

                // Karten + Schwierigkeit als gekoppeltes Mechanik-Duo
                // mit engerem 12-pt-Spacing (User-Revision 2026-04-22).
                VStack(alignment: .leading, spacing: 12) {
                    flashcardCountLimitCard
                    flashcardMasteryThresholdCard
                }

                // **Sweep C — AnswerMode (2026-05-07)** — Sprechen/
                // Tippen-Selector. Persistierung via @AppStorage in
                // `FlashcardsView` (`karteikartenAnswerModeBinding`),
                // Render-Branch in `flashcardPrimaryActions`.
                AnswerModeSelector(
                    mode: karteikartenAnswerModeBinding,
                    accent: sectionStyle.accent,
                    onChange: { _ in feedbackPlayer.playTabSwitch() }
                )

                // **2026-05-09 Hidden for v1** — `personalDeckSection`
                // (Meine-Stapel-Entry) im Setup ausgeblendet, damit
                // Karteikanten-Setup ohne Scroll auf iPhone Standard
                // passt. PersonalDeckStore + Render-Pfade +
                // FlashcardStackComposerSheet bleiben im Code als
                // späteres Feature; nur dieser Setup-Aufruf entfällt.
                // (Section-Definition in `FlashcardsView+PersonalDeck.swift`
                // unverändert.)
                // personalDeckSection
            }
        )
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .sheet(isPresented: $setup.showingStackComposer) {
            FlashcardStackComposerSheet(
                style: sectionStyle,
                lists: availableStackLists,
                selectedListIDs: setup.selectedStackListIDs,
                language: selectedAppDirection.sourceLanguage,
                cardTypeFilter: setup.selectedSetupContent.preferredCardType
            ) { updatedSelection in
                setup.selectedStackListIDs = updatedSelection
                setup.showingStackComposer = false
            }
        }
        // (NavigationDestination für PersonalDecksView ist nach
        // `flashcardsBodyContent` gewandert — siehe Bug-Fix-Kommentar
        // dort. Hier nicht mehr deklarieren, sonst doppelt.)
    }

    // **Phase 5 (2026-05-04) → B2 (2026-05-06)** — Summary-Builder
    // entfernt. Vorher baute `flashcardsListSummary(...)` einen
    // String mit eingebettetem LJ-Range. Mit dem Lernjahr-Pill-
    // Refactor steht der Range jetzt als eigenständige Pill in
    // einer HStack im Render-Pfad — der Builder hat keinen Sinn
    // mehr und wäre toter Code.

    // **Cleanup 2026-05-08** — `flashcardsListSelectionCard` (Custom-
    // Listen-Auswahl-Card mit eigenem `stackListPickerActive`-Sheet)
    // ist mit der Master-Migration entfallen. Der Listen-Picker läuft
    // jetzt über `ListCategoryPickerView` (Master-Component) →
    // `GlobalListPickerSheet` (mit Lernjahr-Filter), identisch zu Quiz/
    // Vokabeln/Nomen. Damit ist Karteikarten visuell und funktional
    // konsistent zu allen anderen Modulen.
}
