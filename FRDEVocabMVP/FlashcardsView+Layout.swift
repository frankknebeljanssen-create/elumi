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

            // **Pre-Screen-Pop-up 2026-05-09** — Slot-Style-Modal
            // vor dem eigentlichen Setup. Auto-Trigger via `.onAppear`
            // in flashcardSetupScreen, manueller Re-Trigger über die
            // Mengen-Anzeige-Card. Conditional-Render — bei
            // `isShowingAmountPopup == false` rendert der Branch
            // garnichts. Slot-launched Sessions setzen den State
            // niemals → Pop-up unsichtbar.
            if isShowingAmountPopup && setup.isShowingSetup {
                flashcardsAmountPopup
                    .transition(.opacity)
                    .zIndex(10)
            }
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
        // **Gruppe-3-Migration (2026-05-22)** — Listen-Kategorie-Picker
        // als Push-Screen (analog Nomen/Verben/Vokabeln). Sitzt hier in
        // `flashcardsBodyContent` (immer im Hierarchy) statt im
        // `flashcardSetupScreen` (konditionell). Push-Tauglichkeit
        // belegt durch PersonalDecksView-Destination oben.
        .navigationDestination(isPresented: $flashcardsListPickerActive) {
            UnifiedListCategoryPicker(
                availableLists: availableStackLists,
                selectedIDs: setup.selectedStackListIDs,
                onCommit: { setup.selectedStackListIDs = $0 },
                accent: sectionStyle.accent,
                singleSelect: false,
                includeWoerterbuch: false,
                itemLabel: "Karten",
                feedbackPlayer: feedbackPlayer,
                onHome: { dismissToHome() },
                onSettings: { openSettings() }
            )
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
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

                // **Button-Vereinheitlichung (2026-05-22)** — externer
                // „Zurück"-Button entfernt; die Rück-Navigation läuft jetzt
                // über den Secondary-CTA „Zur Startseite" IN der Summary-Card
                // (`flashcardCompletionCard` → SessionSummaryView), wie bei
                // allen anderen Modulen.
                flashcardCompletionCard
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
                    } else if interaction.answerMode == .view {
                        // **Ansehen-Modus (2026-05-22)** — kein Mikro/Eingabe-
                        // feld. Stattdessen die 2 Selbst-Bewertungs-Buttons
                        // (sichtbar nach dem Aufdecken). Das Typed-Overlay
                        // greift hier nicht (`.tap`-only).
                        Spacer().frame(height: 32)

                        flashcardSelfRatingActions
                            .padding(.horizontal, flashcardSessionCardInset)
                    }

                    // **2026-08-06** — Ausstieg mit Ergebnis, an derselben
                    // Position wie in allen Trainings-Modi (User-Spec:
                    // "bei Karteikarten fehlt's mir noch"). Nur während
                    // laufender Session — auf der Abschluss-Card wäre er
                    // sinnlos, dort steht schon das Ergebnis.
                    Spacer(minLength: AppTheme.Spacing.sm)

                    endFlashcardsEarlyButton
                        .padding(.horizontal, flashcardSessionCardInset)
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

    /// **2026-08-06** — Gegenstück zu `endTrainingEarlyButton` in
    /// `TrainingView+Layout.swift`: gleiche Optik, gleiche Position,
    /// gleiche Zielflagge. Karteikarten hat eine eigene View-Hierarchie,
    /// deshalb eine zweite Definition statt Wiederverwendung.
    ///
    /// `markCurrentSessionDoneFromChainTimer()` ist trotz des Namens die
    /// generische „Session jetzt beenden"-Mutation im Store (setzt
    /// `isCompleted`, räumt die aktuelle Karte ab) — genau das, was der
    /// Chain-Timer-Cutoff schon nutzt. Dadurch läuft der reguläre
    /// Abschluss-Pfad an: `flashcardCompletionCard` erscheint,
    /// `consumeFlashcardSessionReward()` vergibt XP.
    var endFlashcardsEarlyButton: some View {
        Button {
            guard sessionStore.session != nil else {
                returnToFlashcardSetup()
                return
            }
            speechController.stopRecording()
            sessionStore.markCurrentSessionDoneFromChainTimer()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 15, weight: .bold))
                Text("Für jetzt beenden")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
            }
            .foregroundStyle(AppTheme.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 48)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .fill(AppTheme.Colors.secondarySurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .stroke(AppTheme.Colors.border, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(AppCardPressStyle())
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
            helpTopic: .flashcards,
            onBack: { handleBackNavigation() },
            onStart: { startFlashcardsFromSetup(autoplayPrompt: true) },
            contextContent: {
                // **Gruppe-3-Migration (2026-05-22)** — `onTap` setzt
                // `flashcardsListPickerActive = true` → `.navigationDestination`
                // in `flashcardsBodyContent` pusht `UnifiedListCategoryPicker`.
                // `onSelectionChanged` bleibt für backward-compat (wird im
                // Push-Pfad nicht aufgerufen, Selektion via `onCommit`).
                ListCategoryPickerView(
                    availableLists: availableStackLists,
                    selectedListIDs: setup.selectedStackListIDs,
                    accent: sectionStyle.accent,
                    style: sectionStyle,
                    feedbackPlayer: feedbackPlayer,
                    summaryText: "",
                    itemLabel: "Karten",
                    onSelectionChanged: { setup.selectedStackListIDs = $0 },
                    onHome: { dismissToHome() },
                    onTap: { flashcardsListPickerActive = true }
                )
            },
            optionsContent: {
                if isDictionarySelectedInStack {
                    flashcardDictionaryLevelCard
                }

                // **Pre-Screen-Refactor 2026-05-09** — KARTEN-Slider +
                // SCHWIERIGKEIT-Buttons sind aus dem Setup-Body raus
                // und ins `flashcardsAmountPopup` gewandert (Slot-
                // Pattern Pre-Screen vor Setup). Hier nur noch eine
                // kompakte Mengen-Anzeige-Card als Read-Only-Summary +
                // Re-Edit-Trigger.
                flashcardsAmountSummaryCard

                // **Sweep C — AnswerMode (2026-05-07)** — Sprechen/
                // Tippen-Selector. Persistierung via @AppStorage in
                // `FlashcardsView` (`karteikartenAnswerModeBinding`),
                // Render-Branch in `flashcardPrimaryActions`.
                AnswerModeSelector(
                    mode: karteikartenAnswerModeBinding,
                    // **Ansehen-Modus (2026-05-22)** — NUR Karteikarten
                    // bietet den 3. Modus `.view` an. Vokabeln/Nomen nicht.
                    modes: [.speech, .tap, .view],
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
        // **2026-06-09** — Auto-Trigger entfernt (User-Spec). Der
        // Einstieg führt jetzt direkt auf den Setup-Screen; Menge und
        // Schwierigkeit stehen dort in der MENGE-Card und lassen sich
        // per Tap ändern. Vorher war dasselbe Pop-up zweimal im Weg:
        // einmal ungefragt beim Öffnen, einmal über die Card — für
        // Einsteiger ein Zusatzschritt ohne Mehrwert, weil der
        // Default („alle Karten", auf Session-Cap begrenzt) in aller
        // Regel passt.
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

    // MARK: - Pre-Screen-Pop-up (2026-05-09)

    /// **Karteikarten Pre-Screen-Pop-up** — Slot-Style-Modal vor dem
    /// eigentlichen Setup-Screen. Zeigt KARTEN-Slider + SCHWIERIGKEIT-
    /// Buttons als Last-Config-Quick-Edit. Style nachgebaut analog
    /// `ElumiTabView.setupModalOverlay` (Slot-Maschine Daily-Drop-
    /// Pop-up — keine wiederverwendbare Pre-Screen-Component im Repo
    /// vorhanden, daher inline-nachbau gemäß Frank-Spec).
    ///
    /// Reuse-Strategie: `flashcardCountLimitCard` und
    /// `flashcardMasteryThresholdCard` sind Extension-Methods auf
    /// `FlashcardsView` und werden direkt wiederverwendet — kein Code-
    /// Duplikat, keine Bindings-Plumbing nötig.
    var flashcardsAmountPopup: some View {
        ZStack(alignment: .top) {
            // Backdrop — Slot-Pattern: 0.97 opaque für klare Modal-
            // Trennung. Tap-Outside schließt das Pop-up.
            Color.black.opacity(0.97)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    dismissAmountPopup()
                }

            // Modal-Card
            VStack(spacing: 18) {
                // Top-Bar: Back-Chevron links, X-Close rechts.
                HStack {
                    Button {
                        dismissAmountPopup()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Zurück"))

                    Spacer(minLength: 0)

                    Button {
                        dismissAmountPopup()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Schließen"))
                }

                // Pre-Title + Headline (Slot-Style, identische Typo).
                VStack(spacing: 4) {
                    Text("Karteikarten")
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(sectionStyle.accent)

                    Text("Wie viele Karten und welche Schwierigkeit?")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .frame(maxWidth: .infinity)

                // Inhalt: existing Setup-Cards reused — gleiche Logic,
                // gleiche Persistenz, gleiche visuelle Repräsentation
                // wie heute im Setup-Screen-Body (post-Compaction).
                VStack(spacing: 12) {
                    flashcardCountLimitCard
                    flashcardMasteryThresholdCard
                }

                // CTA „Weiter" — schließt Pop-up, User landet auf Setup
                // mit den (möglicherweise geänderten) Werten.
                Button {
                    dismissAmountPopup()
                } label: {
                    Text("Weiter")
                        .font(AppTheme.Typography.button)
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 50)
                        .background(
                            RoundedRectangle(cornerRadius: AppLayout.sessionCTARadius, style: .continuous)
                                .fill(AppTheme.Colors.cta)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Weiter")
            }
            .padding(20)
            .frame(maxWidth: 360)
            // Slot-Pattern: intrinsische Höhe, sonst dehnt sich der
            // VStack auf Backdrop-Höhe.
            .fixedSize(horizontal: false, vertical: true)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: "#101522"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(sectionStyle.accent.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.55), radius: 24, x: 0, y: 8)
            .padding(.horizontal, 24)
            .padding(.top, 60)
        }
    }

    /// **Schließt das Pre-Screen-Pop-up** mit smoother Easing-Animation.
    /// Persistenz greift bereits durch die didSet-Hooks auf
    /// `setup.selectedCardCount` + `setup.masteryThreshold` während
    /// Slider/Button-Interaktionen — kein expliziter Save nötig.
    private func dismissAmountPopup() {
        withAnimation(.easeOut(duration: 0.2)) {
            isShowingAmountPopup = false
        }
    }

    // MARK: - Mengen-Anzeige-Card (Setup-Body)

    /// **Mengen-Anzeige-Card** — kompakte Tap-Card im Setup-Body, die
    /// die aktuell gewählten KARTEN-Anzahl + SCHWIERIGKEIT als
    /// Read-Only-Summary anzeigt. Tap öffnet das Pre-Screen-Pop-up
    /// erneut zum Ändern. Pattern-konsistent zu DEINE LISTEN-Card
    /// (Tap → Sheet/Modal mit Re-Edit).
    var flashcardsAmountSummaryCard: some View {
        let cardCount = setup.selectedCardCount
        let displayCount: String = (cardCount <= 0) ? "Alle Karten" : "\(cardCount) Karten"
        // **2026-06-09** — Multiplikator mit anzeigen (User-Spec):
        // „Normal" allein sagt nicht, wie oft eine Karte richtig
        // beantwortet werden muss, bis sie aus dem Stapel fällt.
        let thresholdLabel: String = {
            switch setup.masteryThreshold {
            case 1: return "Easy (1x)"
            case 2: return "Normal (2x)"
            case 3: return "Hart (3x)"
            case 4: return "Brutal (4x)"
            default: return "Normal (2x)"
            }
        }()

        return Button {
            feedbackPlayer.playTabSwitch()
            withAnimation(.easeInOut(duration: 0.2)) {
                isShowingAmountPopup = true
            }
        } label: {
            HStack(alignment: .center, spacing: 14) {
                // Card-Stack-Icon analog zur KARTEN-Card-Mini-Stapel-
                // Ästhetik. SF-Symbol weil das Cartoon-Set kein
                // dedicated „Mengen"-Icon hat.
                Image(systemName: "rectangle.stack.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(sectionStyle.accent)
                    .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 4) {
                    Text("MENGE")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(AppTheme.Colors.cardLabel)
                        .textCase(.uppercase)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("\(displayCount) · \(thresholdLabel)")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(sectionStyle.accent.opacity(0.7))
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .appSetupCardBackground(cornerRadius: AppLayout.largeCardCornerRadius)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Karten-Anzahl und Schwierigkeit ändern")
        .accessibilityValue("\(displayCount), Schwierigkeit \(thresholdLabel)")
    }
}
