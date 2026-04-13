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
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Karteikarten",
                subtitle: "",
                systemImage: "rectangle.stack.fill"
            )

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
                // Navigation
                Spacer().frame(height: 4)

                Button {
                    handleBackNavigation()
                } label: {
                    Label("Zurück", systemImage: "arrow.left")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 40)
                        .font(AppTheme.Typography.button)
                        .foregroundStyle(sectionStyle.accent)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                .fill(AppTheme.Colors.secondarySurface)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                .stroke(sectionStyle.accent.opacity(0.18), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .padding(.horizontal, flashcardSessionCardInset)

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
                    // Prompt Card
                    Spacer().frame(height: AppTheme.Spacing.lg)

                    flashcardPromptCard
                        .padding(.horizontal, flashcardSessionCardInset)

                    // Action Buttons
                    Spacer().frame(height: AppTheme.Spacing.lg)

                    flashcardActionButtons
                        .padding(.horizontal, flashcardSessionCardInset)

                    // Response Card
                    Spacer(minLength: AppTheme.Spacing.lg)

                    flashcardResponseCard
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
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                    ScreenHeaderCard(
                        style: sectionStyle,
                        title: "Karteikarten",
                        subtitle: "",
                        systemImage: "rectangle.stack.fill"
                    )

                    Button {
                        handleBackNavigation()
                    } label: {
                        Label("Zurück", systemImage: "arrow.left")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppSecondaryButtonStyle(tint: sectionStyle.accent))

                    ListCategoryPickerView(
                        availableLists: availableStackLists,
                        selectedListIDs: setup.selectedStackListIDs,
                        accent: sectionStyle.accent,
                        style: sectionStyle,
                        feedbackPlayer: feedbackPlayer,
                        summaryText: selectedStackSummary,
                        onSelectionChanged: { setup.selectedStackListIDs = $0 }
                    )
                    .padding(.bottom, AppTheme.Spacing.sm)

                    if isDictionarySelectedInStack {
                        flashcardDictionaryLevelCard
                    }

                    flashcardCountLimitCard

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .top)
                .padding(.bottom, isCardCountFieldFocused ? 140 : AppTheme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                Button {
                    startFlashcardsFromSetup(autoplayPrompt: true)
                } label: {
                    Text("Los geht's!")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(AppPrimaryButtonStyle(color: canStartSetup ? AppTheme.Colors.cta : AppTheme.Colors.textDisabled))
                .disabled(!canStartSetup)
                .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + 16)
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
}
