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
        if !setup.isShowingSetup && !isFlashcardSessionCompleted && interaction.showingTypedAnswerInput {
            VStack {
                Spacer()
                flashcardTypedAnswerCard
                    .padding(.horizontal, AppLayout.screenPadding + flashcardSessionCardInset)
                    .padding(.bottom, AppTheme.Layout.footerHeight + flashcardBottomBarSpacing + AppTheme.Spacing.sm)
            }
            .zIndex(3)
        }
    }

    var flashcardsBodyContent: AnyView {
        AnyView(
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
        )
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

                    flashcardStatsRow
                        .padding(.horizontal, flashcardSessionCardInset)

                    Spacer().frame(height: AppTheme.Spacing.sm)

                    flashcardPromptCard
                        .padding(.horizontal, flashcardSessionCardInset)

                    flashcardSwipeHintCard
                        .padding(.horizontal, flashcardSessionCardInset)
                        .padding(.top, 10)

                    // **Phase 8.1** — Elemente unter der Karte ein Stück
                    // weiter nach unten, damit die jetzt größere Karte
                    // ihren Platz bekommt, ohne dass Antwort-Card und
                    // Action-Block in den Footer reinrutschen.
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
        .padding(.horizontal, AppLayout.screenPadding)
        // Systemweites Top-Padding — Header-Position wie Quiz-Setup.
        .padding(.top, AppLayout.screenHeaderTopPadding)
        .padding(.bottom, AppTheme.Layout.footerHeight + flashcardBottomBarSpacing + AppTheme.Spacing.sm)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var flashcardSetupScreen: some View {
        // Struktur identisch zu `SessionSetupScreen` (Quiz, Nomen, …):
        //   • Header liegt OBERHALB der ScrollView, damit sein
        //     `screenHeaderBottomPadding` der einzige Abstand zum ersten
        //     Content-Block bleibt. Früher saß der Header innerhalb des
        //     scroll-VStack (spacing 16), was zusätzlich 16 pt einschob —
        //     der Gap Header ↔ Ausgewählte Listen war dadurch größer als
        //     bei allen anderen Modulen.
        //   • ScrollView darunter scrollt nur den Content, Header bleibt
        //     visuell am Screen-Top.
        VStack(spacing: 0) {
            flashcardSetupHeader

            ScrollViewReader { proxy in
                // Opaker Screen-Fill — verhindert, dass während des Navigation-
                // Push-Transition die Home-View durchscheint („Was möchtest
                // du üben?" wurde sichtbar, weil die ScrollView keinen eigenen
                // Hintergrund hatte und das appScreenBackground des äußeren
                // Chrome-Wrappers erst nach dem Layout greift).
                ScrollView(showsIndicators: false) {
                    // **User-Revision 2026-04-22**: Outer-Spacing
                    // `md` (16) → `sm` (12), damit der Abstand zwischen
                    // „Meine Stapel" und „Anzahl der Karten" so eng
                    // sitzt wie der Gap zwischen den beiden Mechanik-
                    // Cards („Anzahl" ↔ „Karte fällt raus nach").
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        // **App-Konvention (User-Spec)**: Nach dem Header kommt
                        // IMMER zuerst die „Ausgewählte Listen"-Card — dann
                        // folgt der Rest modulspezifisch.
                        flashcardsListSelectionCard

                        // Direction-Row ist in den Header gewandert
                        // (FR-DE-Toggle rechts oben im ModuleHeaderCard).

                        if isDictionarySelectedInStack {
                            flashcardDictionaryLevelCard
                        }

                        // User-Nachjustierung: Spacing zwischen „Anzahl
                        // der Karten" und „Karte fällt raus nach" wieder
                        // zurück auf 12 pt — die 22 pt waren zu viel
                        // Abstand zwischen den beiden Mechanik-Cards.
                        VStack(alignment: .leading, spacing: 12) {
                            flashcardCountLimitCard
                            flashcardMasteryThresholdCard
                        }

                        // **User-Revision 2026-04-22**: Meine-Stapel-
                        // Entry-Button wandert UNTER die Mechanik-Cards.
                        // Der Hauptflow (Listen + Kartenanzahl + Mastery)
                        // steht oben, die optionale Stapel-Auswahl darunter.
                        personalDeckSection

                        // `flashcardHungerCard` + `flashcardStatsTrioCard` sind
                        // mit der Master-Setup-Migration ersatzlos entfallen:
                        // isoliertes Würmchen-Messaging und die Mini-Stat-Kacheln
                        // werden jetzt durch die globale `SessionGamificationBar`
                        // oberhalb des CTA abgedeckt.

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .top)
                    // 4 pt Atemraum zwischen Header-Unterkante und erstem
                    // Content — analog zum `SessionSetupScreen`-Master
                    // (dort: ScrollView `padding(.top, 4)`).
                    .padding(.top, 4)
                    .padding(.bottom, isCardCountFieldFocused ? 140 : AppTheme.Spacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom) {
                    // GamificationBar + CTA nutzen denselben horizontalen
                    // Rahmen wie die `SessionSetupScreen`-Master — identisches
                    // Padding auf beiden sorgt dafür, dass die beiden Cards
                    // exakt gleich breit sind. Frühere Abweichung: die Bar
                    // hatte zusätzliches `screenPadding` von 16 pt, der Button
                    // nur die äußere `screenPadding` des Screen-VStacks — Bar
                    // war dadurch 32 pt schmaler als der Button.
                    //
                    // Bottom-Padding MUSS `AppLayout.sessionCTABottomClearance`
                    // nutzen — pro User-Request „CTA muss in jedem Screen das
                    // gleiche Padding zum Footer haben und alle müssen exakt
                    // gleich groß sein". Früher standen hier `footerHeight +
                    // bottomBarInsetBottom + 4` (= 58 pt) — 10 pt weniger als
                    // Quiz / Training-Setup (dort: `sessionCTABottomClearance`
                    // = footerHeight + bottomBarInsetBottom + 14 = 68 pt).
                    // Der Karteikarten-CTA wirkte dadurch näher am Footer als
                    // die anderen Module. Die Vereinheitlichung auf die System-
                    // Konstante hebt ihn um 10 pt an und bringt ihn auf
                    // exakt die gleiche Distanz zum Footer wie alle anderen
                    // Setup-Screens.
                    // **User-Revision 2026-04-22**: Spacing zwischen
                    // Punkte-Bar und „Los geht's"-CTA reduziert (14 → 8 pt),
                    // damit die beiden Elemente optisch näher
                    // zusammengehören.
                    VStack(spacing: 8) {
                        // **Chain-Mode XP-Card-Hide (2026-05-02)** —
                        // Karteikarten rendert die Gamification-Bar
                        // direkt (nicht über `SessionSetupScreen`-
                        // Wrapper). Im Chain-Modus blenden wir sie aus,
                        // weil per-Modul-XP-Schätzung im Chain-Kontext
                        // irreführend wäre (Chain-Timer ist Begrenzung,
                        // Reward läuft Chain-aggregiert).
                        if launchContext?.chainContext == nil {
                            SessionGamificationBar(estimate: flashcardsSessionEstimate)
                        }

                        SessionPrimaryCTA(
                            title: "Los geht's!",
                            isEnabled: canStartSetup
                        ) {
                            startFlashcardsFromSetup(autoplayPrompt: true)
                        }
                        // **User-Revision 2026-04-22**: Karteikarten-spezifisch
                        // etwas näher an den Footer ran (−14 pt gegenüber der
                        // systemweiten `sessionCTABottomClearance`). Ankündigungs-
                        // Bar + CTA rutschen dadurch gemeinsam tiefer — alle
                        // anderen Setup-Screens bleiben unverändert auf der
                        // System-Konstanten.
                        .padding(.bottom, max(0, AppLayout.sessionCTABottomClearance - 14))
                    }
                }
                .onChange(of: isCardCountFieldFocused) { _, isFocused in
                    guard isFocused else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            proxy.scrollTo(flashcardCountInputScrollID, anchor: .bottom)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, AppLayout.screenPadding)
        // Systemweites Top-Padding — Header-Position wie Quiz-Setup.
        .padding(.top, AppLayout.screenHeaderTopPadding)
        .padding(.bottom, AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        // Opaker Screen-Fill auf `background` (elumiMidnight) — identisch
        // zum Home-Screen. Cards heben sich dadurch minimal heller ab
        // (`surface` = elumiNavy), statt in der gleichen Farbe wie der
        // Screen zu versinken. Dieser lokale Override ist nötig, damit
        // während der Navigation-Push-Transition die Home-View nicht
        // durchscheint — das äußere `appScreenBackground` greift erst
        // nach dem Layout.
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

    /// Custom Listen-Auswahl-Card im Speed-Round-Stil — analog zu den
    /// Trainings-Modulen. Listen werden untereinander angezeigt (max 5),
    /// Card wächst nach unten. Tap öffnet das Listen-Auswahl-Sheet.
    private var flashcardsListSelectionCard: some View {
        let selectedIDs = setup.selectedStackListIDs
        let selectedLists = availableStackLists.filter { selectedIDs.contains($0.id) }
        let hasSelection = !selectedLists.isEmpty
        let totalCards = selectedStackCardCount

        return Button {
            feedbackPlayer.playTabSwitch()
            stackListPickerActive = true
        } label: {
            // Header GANZ links oben (linksbündig über allem) statt neben
            // dem Icon. Konsistent mit den anderen Setup-Cards.
            VStack(alignment: .leading, spacing: 8) {
                flashcardSetupCardLabel("Ausgewählte Listen")

                HStack(alignment: .center, spacing: 14) {
                    // Home-Listen-Icon — identisch zur "Listen"-Kachel auf
                    // dem Home-Screen (Asset `HomeIconListen`). Systemweit
                    // identisches Icon für „Ausgewählte Listen" statt des
                    // früheren SF-Symbols `list.bullet.rectangle.fill`.
                    HomeModuleIconView(icon: .listen, size: 36)

                        VStack(alignment: .leading, spacing: 2) {
                            if hasSelection {
                                ForEach(selectedLists.prefix(AppLayout.maxSelectableLists)) { list in
                                    Text(list.name)
                                        .font(.system(size: 18, weight: .bold, design: .rounded))
                                        .foregroundStyle(AppTheme.Colors.textPrimary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.7)
                                }
                                Text("\(selectedLists.count) Liste\(selectedLists.count == 1 ? "" : "n") · \(totalCards) Karten gesamt")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.elumiBlue)
                                    .padding(.top, 2)
                            } else {
                                Text("Keine Liste gewählt")
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.textPrimary)
                                Text("Tippe zum Auswählen")
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundStyle(AppTheme.Colors.elumiBlue)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        // Stift in rundem Pill — dezent, nicht zu dominant.
                        Image(systemName: "pencil")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(sectionStyle.accent)
                            .frame(width: 32, height: 32)
                            .background(
                                Circle()
                                    .fill(sectionStyle.accent.opacity(0.18))
                            )
                    }
                }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .appSetupCardBackground(cornerRadius: AppLayout.largeCardCornerRadius)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $stackListPickerActive) {
            ListSelectionSheet(
                style: sectionStyle,
                ownLists: availableStackLists.filter { !$0.isBuiltIn || $0.isAggregateVocabulary },
                levelLists: availableStackLists.filter { $0.collectionPreset == .standardLevel },
                topicLists: availableStackLists.filter { $0.collectionPreset == .standardTopic },
                selectedListIDs: setup.selectedStackListIDs,
                onSelectionChanged: { updated in
                    setup.selectedStackListIDs = updated
                    stackListPickerActive = false
                }
            )
        }
    }
}
