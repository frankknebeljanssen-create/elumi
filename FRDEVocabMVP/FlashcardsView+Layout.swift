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
                // Combo-Toast-Overlay — zeigt bei 5/10/15/... richtigen Karten
                // hintereinander einen kurzen Bonus-Hinweis.
                ComboToastOverlay()
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
    }

    var flashcardSessionScreen: some View {
        VStack(spacing: 0) {
            // Kompakter Header: kleiner „< Zurück" links + zentrierter Titel.
            // Ersetzt die alte ScreenHeaderCard + den großen Zurück-Button.
            flashcardSessionHeader

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
                    Spacer().frame(height: AppTheme.Spacing.md)

                    flashcardStatsRow
                        .padding(.horizontal, flashcardSessionCardInset)

                    Spacer().frame(height: AppTheme.Spacing.sm)

                    flashcardPromptCard
                        .padding(.horizontal, flashcardSessionCardInset)

                    flashcardSwipeHintCard
                        .padding(.horizontal, flashcardSessionCardInset)
                        .padding(.top, 6)

                    Spacer().frame(height: AppTheme.Spacing.sm)

                    flashcardResponseCard
                        .padding(.horizontal, flashcardSessionCardInset)

                    // Größerer Abstand vor dem Action-Block, damit Antwort-
                    // Card und Mikro/Lautsprecher/Tastatur klar voneinander
                    // abgesetzt sind.
                    Spacer().frame(height: 28)

                    flashcardPrimaryActions
                        .padding(.horizontal, flashcardSessionCardInset)
                }
            }
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.top, AppLayout.contentTopPadding)
        .padding(.bottom, AppTheme.Layout.footerHeight + flashcardBottomBarSpacing + AppTheme.Spacing.sm)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    var flashcardSetupScreen: some View {
        ScrollViewReader { proxy in
            // Opaker Screen-Fill — verhindert, dass während des Navigation-
            // Push-Transition die Home-View durchscheint („Was möchtest
            // du üben?" wurde sichtbar, weil die ScrollView keinen eigenen
            // Hintergrund hatte und das appScreenBackground des äußeren
            // Chrome-Wrappers erst nach dem Layout greift).
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    // Kompakter Header analog zum Session-Screen — kleiner
                    // „< Zurück" links + zentrierter Karteikarten-Titel. Die
                    // alte ScreenHeaderCard + großer Zurück-Button wurden
                    // entfernt.
                    flashcardSetupHeader

                    flashcardsListSelectionCard

                    if isDictionarySelectedInStack {
                        flashcardDictionaryLevelCard
                    }

                    flashcardCountLimitCard

                    flashcardMasteryThresholdCard

                    // `flashcardHungerCard` + `flashcardStatsTrioCard` sind
                    // mit der Master-Setup-Migration ersatzlos entfallen:
                    // isoliertes Würmchen-Messaging und die Mini-Stat-Kacheln
                    // werden jetzt durch die globale `SessionGamificationBar`
                    // oberhalb des CTA abgedeckt.

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.bottom, isCardCountFieldFocused ? 140 : AppTheme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 14) {
                    // Master-Session-Setup-Bar — verbindlich über dem CTA.
                    SessionGamificationBar(estimate: flashcardsSessionEstimate)
                        .padding(.horizontal, AppLayout.screenPadding)

                    Button {
                        startFlashcardsFromSetup(autoplayPrompt: true)
                    } label: {
                        Text("Los geht's!")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: canStartSetup ? AppTheme.Colors.cta : AppTheme.Colors.textDisabled))
                    .disabled(!canStartSetup)
                    .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + 4)
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
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.top, AppLayout.contentTopPadding)
        .padding(.bottom, AppLayout.screenPadding)
        .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.Colors.surface.ignoresSafeArea())
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
                    Image(systemName: "list.bullet.rectangle.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(sectionStyle.accent)
                            .frame(width: 36, height: 36)

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
