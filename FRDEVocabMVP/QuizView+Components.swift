import SwiftUI

extension QuizView {
var quizSetupScreen: some View {
    // Migration auf das Master-Session-Setup-System:
    //   • Header, Spacing, CTA kommen zentral aus `SessionSetupScreen`
    //   • Listen-Card bleibt `ListCategoryPickerView` — wir wollen die POS-
    //     Breakdown-Info + Multi-List-Anzeige nicht verlieren
    //   • Fragen-Anzahl als generisches `OptionChipGrid` (funktional identisch)
    SessionSetupScreen(
        title: "Quiz",
        accent: sectionStyle.accent,
        estimate: quizSessionEstimate,
        // **Naming-Sweep 2026-05-06** — CTA-Vereinheitlichung: alle
        // Modul-Setups (Quiz, Karteikarten, Training, Akzente)
        // tragen jetzt „Los geht's!" als Primary-Button. Daily-Drop
        // bleibt mit „Drop starten" als Brand-Begriff.
        primaryButtonTitle: session.isPreparingQuiz ? "Quiz wird gestartet …" : "Los geht's!",
        isPrimaryEnabled: canStartQuiz && !session.isPreparingQuiz,
        // **Chain-Mode XP-Card-Hide (2026-05-02)** — wenn Quiz als
        // Chain-Step geöffnet wird (`launchContext?.chainContext != nil`),
        // ist die per-Modul-XP-Schätzung („+90 XP · ~2 min") irreführend:
        // der Chain-Timer ist die einzige Begrenzung, die Anzeige passt
        // weder zum tatsächlichen Reward (Chain-aggregiert) noch zur
        // tatsächlichen Dauer (Chain-Step-Sekunden). Default true bleibt
        // für Home-Tile-Pfad unverändert.
        showsGamificationBar: launchContext?.chainContext == nil,
        moduleIcon: .quiz,
        showsDirectionToggle: true,
        onBack: { handleBackNavigation() },
        onStart: { startQuiz() },
        contextContent: {
            // **Gruppe-3-Migration (2026-05-22)** — `onTap` setzt
            // `quizListPickerActive = true` → `.navigationDestination`
            // im `body`-Chain pusht `UnifiedListCategoryPicker`.
            ListCategoryPickerView(
                availableLists: availableQuizLists,
                selectedListIDs: session.selectedListIDs,
                accent: sectionStyle.accent,
                style: sectionStyle,
                feedbackPlayer: feedbackPlayer,
                summaryText: quizListSummary,
                itemLabel: "Einträge",
                onSelectionChanged: { session.selectedListIDs = $0 },
                onHome: goHome,
                onTap: { quizListPickerActive = true }
            )
        },
        optionsContent: {
            // **Naming-Sweep 2026-05-06** — „ANZAHL FRAGEN" →
            // „FRAGEN". Die Chip-Auswahl mit den Zahlen erklärt
            // sich selbst, „Anzahl" war Beamten-Sprache.
            SessionOptionGroupCard(title: "FRAGEN") {
                OptionChipGrid(
                    options: QuizQuestionCountOption.allCases,
                    title: { $0.title },
                    selected: session.questionCountOption,
                    accent: sectionStyle.accent,
                    onSelect: { option in
                        // User-Request: Tap-Sound fehlte. Systemweiter
                        // Toggle-Sound wie in anderen Setup-Chips.
                        feedbackPlayer.playTabSwitch()
                        withAnimation(.easeInOut(duration: 0.12)) {
                            session.questionCountOption = option
                        }
                    }
                )
            }

            if !canStartQuiz {
                Text("Wähle mindestens eine Liste mit Einträgen, um zu starten.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.elumiBlue)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    )
    .background(AppTheme.Colors.surface.ignoresSafeArea())
}

// **C3-Cleanup (2026-05-06)** — `quizDirectionCard` (Body-Card mit
// FR↔DE-Toggle-Buttons) ist entfernt. Vorher rendere die Card eine
// 2-Button-Reihe „FR→DE" / „DE→FR" mit Flag-Badges; mittlerweile sitzt
// der Direction-Toggle einheitlich oben rechts in der `ModuleHeaderCard`
// (`showsDirectionToggle: true`) und nutzt `LanguageDirectionSwitch`
// (`size: .compact`). Die Body-Card war seit der Header-Migration toter
// Code — definiert, aber an keiner Call-Site eingebunden.

/// Kompakter Header für den Quiz-Setup-Screen — nackter Back-Pfeil links,
/// zentrierter „Quiz"-Titel, rechts leer. Systemweiter AppBackButton +
/// screenHeaderBottomPadding — identisch zu allen anderen Headern.
var quizSetupHeader: some View {
    ZStack {
        Text("Quiz")
            .font(.system(size: 28, weight: .black, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .center)

        HStack {
            AppBackButton(action: { handleBackNavigation() }, tint: sectionStyle.accent)

            Spacer()
        }
    }
    .padding(.horizontal, quizSetupCardInset)
    .padding(.top, 4)
    .padding(.bottom, AppLayout.screenHeaderBottomPadding)
}

// `quizQuestionCountCard` und `quizCountButton` wurden im Master-Session-
// Setup-Umbau durch die generische `OptionChipGrid` im neuen
// `SessionSetupScreen` ersetzt. Funktional identisch — selbe Options,
// selber State, nur im einheitlichen Chip-Stil.

var quizSessionScreen: some View {
    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
        // Kompakter Header analog Karteikarten — kleiner „< Zurück" links,
        // „Quiz"-Titel mittig. Zurück führt zur Setup-Card (handleBackNavigation),
        // nicht raus zu Home. ScreenHeaderCard + großer Zurück-Button raus.
        quizSetupHeader

        AppSurfaceCard(tint: sectionStyle.accent) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                // **Block 3.7.3 (2026-05-03)** — Im Chain-Modus
                // sind die modul-eigenen Counter „X von Y" und
                // „N richtig · M falsch" redundant zum
                // Chain-Header („ÜBUNG X VON Y"-Step-Indikator).
                // Progress-Bar bleibt sichtbar — die ist visuell
                // kompakter und liefert direktes Per-Antwort-
                // Feedback unabhängig vom Chain-Step-Counter.
                if launchContext?.chainContext == nil {
                    HStack {
                        Text("\(min(session.currentQuestionIndex + 1, displayedQuestionCount)) von \(displayedQuestionCount)")
                            .font(AppTheme.Typography.cardTitle)
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Spacer(minLength: 0)
                        Text("\(correctCount) richtig · \(wrongCount) falsch")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                    }
                }

                quizProgressBar
            }
        }

        if let currentQuestion {
            switch currentQuestion {
            case .multipleChoice(let question):
                multipleChoiceCard(question)
            case .matching(let question):
                if question.isWordCombo {
                    wordComboCard(question)
                } else {
                    matchingCard(question)
                }
            case .typing(let question):
                typingCard(question)
            case .fillBlanks(let question):
                fillBlanksCard(question)
            }
        } else if session.isLoadingRemainingQuestions {
            AppSurfaceCard(tint: sectionStyle.accent) {
                HStack(spacing: AppTheme.Spacing.sm) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(sectionStyle.accent)

                    Text("Nächste Frage wird geladen ...")
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.textPrimary)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }

        Spacer(minLength: 0)
    }
    .padding(.horizontal, AppLayout.screenPadding)
    .padding(.top, AppLayout.contentTopPadding)
    .padding(.bottom, AppLayout.screenPadding)
    .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
}

var quizResultScreen: some View {
    // **Konsolidiert (2026-05-22)** — eigene Celebration-Card (108-pt-
    // Würmchen-Hero + Richtig/Falsch-Boxen + Snack-Chips + rewardSummaryText)
    // + „Ergebnis"-ScreenHeaderCard + ScrollView ENTFERNT. Quiz nutzt jetzt
    // — wie alle anderen Module — nur die geteilte `SessionSummaryView`:
    //   • Quote „X von Y richtig" trägt die Headline (resultHeadline)
    //   • Würmchen/Wasserfloh/Algenkugel kompakt via `snackRewards`-Block
    //   • Richtig/Falsch-Boxen entfallen (redundant zur Headline)
    // Elumi-Level-Freischaltungen (selten, live via rewardOutcome) bleiben als
    // kleiner Block ÜBER der Card erhalten — sonst ginge die Anzeige verloren.
    // No-Scroll: die Konsolidierung spart die ~250-pt-Celebration-Card → der
    // Standard-Screen passt ohne ScrollView (analog KK/Training).
    let outcome = quizSessionOutcome ?? .empty
    let chain = launchContext?.chainContext
    let nextStepTitle = chain?.nextStep?.title
    let isChain = chain != nil
    let primaryLabel: String = isChain
        ? (nextStepTitle.map { "Weiter zu \($0)" } ?? "Training abschließen")
        : "Nächste Runde"
    return VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
        // Elumi-Level-Freischaltung (rar) — bleibt als kleiner Hinweis.
        if !isChain, !unlockedRewardLevels.isEmpty {
            VStack(spacing: AppTheme.Spacing.xs) {
                ForEach(unlockedRewardLevels) { level in
                    Text("Level \(level.level) freigeschaltet: \(level.title)")
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.warning)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }

        SessionSummaryView(
            outcome: outcome,
            progress: progressStore.progress,
            primaryCTALabel: primaryLabel,
            onPrimaryCTA: {
                if isChain {
                    chainAdvance?(outcome)
                } else {
                    resetQuizToSetup()
                }
            },
            secondaryCTALabel: isChain ? nil : "Zur Startseite",
            onSecondaryCTA: isChain ? nil : {
                dismissToHome()
            },
            // Würmchen/Wasserfloh/Algenkugel als kompakter Snack-Block in der
            // Standard-Card. Chain: leer (Mid-Step ohne Detail-Rewards).
            snackRewards: isChain ? [] : quizSnackRewards,
            primaryCTAPulses: isChain,
            hidesDetailedStats: isChain
        )
    }
    .padding(.horizontal, AppLayout.screenPadding)
    .padding(.top, AppLayout.contentTopPadding)
    .padding(.bottom, AppTheme.Spacing.md)
    .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .top)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    .onAppear {
        persistHeartsIfNeeded()
    }
}
}
