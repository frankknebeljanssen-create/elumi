import SwiftUI

extension QuizView {
var quizResultHero: some View {
    ZStack {
        Circle()
            .fill(sectionStyle.accent.opacity(0.12))
            .frame(width: 108, height: 108)

        Circle()
            .stroke(sectionStyle.accent.opacity(0.24), lineWidth: 1.5)
            .frame(width: 96, height: 96)

        if totalRewardCount > 0 {
            ElumiSnackIcon(dominantRewardSnackKind, size: 44)
        } else {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 40, weight: .bold))
                .foregroundStyle(sectionStyle.accent)
        }
    }
    .frame(maxWidth: .infinity)
}

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
    // Scrollbar verpackt: der Result-Screen kann bei vielen Rewards
    // (Level-Up + Streak-Milestone + Variable-Reward + Wrong-Answers-Button)
    // höher sein als der Viewport. Bottom-Padding deckt die Footer-AppBottomBar
    // ab, damit die unteren CTA-Buttons nicht verdeckt werden.
    ScrollView(showsIndicators: false) {
    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
        // **Block 2 (2026-05-02)** — User-Spec: im Chain-Mode auf dem
        // Result-Screen keinen eigenen Modul-Header („Ergebnis"-
        // ScreenHeaderCard) mehr. Der Chain-Header (3 Step-Cards +
        // Timer) via `ChainTimerOverlayModifier` trägt die Schritt-
        // Identität; ein zusätzlicher „Ergebnis"-Title-Banner
        // dupliziert die visuelle Hierarchie. User navigiert via
        // Chain-Header oder System-Back-Geste. Out-of-Chain bleibt
        // der Header sichtbar.
        if launchContext?.chainContext == nil {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Ergebnis",
                subtitle: "",
                systemImage: "rosette"
            )
        }

        AppSurfaceCard(tint: sectionStyle.accent) {
            VStack(spacing: AppTheme.Spacing.lg) {
                VStack(spacing: AppTheme.Spacing.xs) {
                    quizResultHero

                    Text(rewardSummaryText)
                        .font(AppTheme.Typography.screenTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(resultHeadline)
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(sectionStyle.accent)
                        .multilineTextAlignment(.center)

                }

                // Richtig / Falsch als kompakte Stats-Zeile. XP wandert
                // komplett in die `SessionSummaryView` darunter, damit beide
                // Systeme nicht parallel dieselbe Zahl zeigen.
                HStack(spacing: AppTheme.Spacing.sm) {
                    resultStatCard(
                        title: "Richtig",
                        value: "\(correctCount)",
                        tint: AppTheme.Colors.success
                    )
                    resultStatCard(
                        title: "Falsch",
                        value: "\(wrongCount)",
                        tint: AppTheme.Colors.warning
                    )
                }

                if totalRewardCount > 0 {
                    HStack(spacing: AppTheme.Spacing.sm) {
                        rewardChip(kind: .wuermchen, value: awardedHearts)
                        rewardChip(kind: .wasserfloh, value: awardedWaterfloh)
                        rewardChip(kind: .algenkugel, value: awardedAlgenkugel)
                    }
                }

                if !unlockedRewardLevels.isEmpty {
                    VStack(spacing: AppTheme.Spacing.xs) {
                        ForEach(unlockedRewardLevels) { level in
                            Text("Level \(level.level) freigeschaltet: \(level.title)")
                                .font(AppTheme.Typography.body)
                                .foregroundStyle(AppTheme.Colors.warning)
                                .multilineTextAlignment(.center)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppTheme.Spacing.md)
        }

        // Zentrale Session-Summary — gleiche Card wie Karteikarten/Training/
        // Verbformen. Zeigt XP-Aufschlüsselung, Credits, Streak, Level-Progress.
        // Die Elumi-Rewards oben bleiben als Quiz-spezifischer Celebration-Teil.
        //
        // Session-End Lücke 2 (Option A): Primary+Secondary CTA einheitlich zu
        // Training / Verbformen / Karteikarten. Die früheren drei Außen-Buttons
        // („Falsche anzeigen", „Nochmal", „Zurück") sind bewusst entfernt — die
        // Summary-Card trägt den gesamten Session-Abschluss allein. Primary
        // („Weiter lernen") setzt die Summary zurück und zeigt die Setup-Card;
        // Secondary („Zur Startseite") verlässt das Quiz-Modul komplett.
        //
        // `showingWrongAnswers` / `wrongAnswersSheet` bleiben vorerst als
        // (inaktiver) Code — sie werden nicht mehr getriggert, aber der
        // Modul-interne State ist unabhängig davon. Eine spätere Cleanup-
        // Runde kann den Sheet + den Presenter entfernen, sobald das neue
        // Pattern freigegeben ist.
        // **Stufe 3 (2026-05-01)** — Chain-Mode-Branching, siehe
        // FlashcardsView+SessionComponents.swift für Doc.
        let outcome = quizSessionOutcome ?? .empty
        let chain = launchContext?.chainContext
        let nextStepTitle = chain?.nextStep?.title
        let isChain = chain != nil
        let primaryLabel: String = isChain
            ? (nextStepTitle.map { "Weiter zu \($0)" } ?? "Training abschließen")
            : "Nächste Runde"
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
            primaryCTAPulses: isChain,
            hidesDetailedStats: isChain
        )
    }
    .padding(.horizontal, AppLayout.screenPadding)
    .padding(.top, AppLayout.contentTopPadding)
    // **2026-05-08 Padding-Cleanup** — Bottom-Padding von
    // `footerHeight + insetBottom + md` auf `Spacing.md` reduziert.
    // Footer ist nach der Migration über safeAreaInset reserviert;
    // die alte Manual-Footer-Höhe schob den Summary-Block sichtbar
    // nach oben.
    .padding(.bottom, AppTheme.Spacing.md)
    .frame(maxWidth: AppTheme.Layout.maxContentWidth, alignment: .top)
    .frame(maxWidth: .infinity, alignment: .top)
    }
    .frame(maxHeight: .infinity)
    .onAppear {
        persistHeartsIfNeeded()
    }
    .sheet(isPresented: $showingWrongAnswers) {
        wrongAnswersSheet
    }
}

private var wrongAnswersSheet: some View {
    NavigationStack {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(wrongQuestionPairs.enumerated()), id: \.offset) { _, pair in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pair.prompt)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                        Text(pair.correctAnswer)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.success)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(AppTheme.Colors.secondarySurface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
            }
            .padding(AppLayout.screenPadding)
        }
        .appScreenBackground(.quiz)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Fertig") {
                    showingWrongAnswers = false
                }
                .font(.system(size: 16, weight: .bold, design: .rounded))
            }
        }
        .navigationTitle("Falsche Antworten")
        .navigationBarTitleDisplayMode(.inline)
    }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
}

private var wrongQuestionPairs: [(prompt: String, correctAnswer: String)] {
    var pairs: [(String, String)] = []
    for (index, result) in session.answeredResults.enumerated() {
        guard !result, index < session.questions.count else { continue }
        let question = session.questions[index]
        switch question {
        case .multipleChoice(let q):
            pairs.append((q.prompt, q.correctAnswer))
        case .matching(let q):
            for pair in q.pairs {
                pairs.append((pair.prompt, pair.answer))
            }
        case .typing(let q):
            pairs.append((q.prompt, q.correctAnswer))
        case .fillBlanks(let q):
            pairs.append((q.sentenceWithBlank, q.correctAnswer))
        }
    }
    return pairs
}
}
