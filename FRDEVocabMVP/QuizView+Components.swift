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
    ScrollView(showsIndicators: false) {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            // Kompakter Header analog zum Karteikarten-Setup —
            // kleiner „< Zurück" links + zentrierter „Quiz"-Titel.
            quizSetupHeader

            ListCategoryPickerView(
                availableLists: availableQuizLists,
                selectedListIDs: session.selectedListIDs,
                accent: sectionStyle.accent,
                style: sectionStyle,
                feedbackPlayer: feedbackPlayer,
                summaryText: quizListSummary,
                // Gleicher Listen-Label wie Training/Verbformen — so wirkt
                // die Ausgewählte-Listen-Card über alle Module einheitlich
                // („X Einträge" statt das Quiz-Default „X Karten").
                itemLabel: "Einträge",
                onSelectionChanged: { session.selectedListIDs = $0 }
            )

            quizQuestionCountCard

            if !canStartQuiz {
                Text("Wähle mindestens eine Liste mit zwei Einträgen.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.elumiBlue)
                    .padding(.horizontal, quizSetupCardInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.bottom, AppTheme.Spacing.sm)
    }
    .safeAreaInset(edge: .bottom) {
        VStack(spacing: 6) {
            // Master-Session-Setup-Bar — verbindlich über dem CTA.
            // Keine Card, kein Rahmen: kompakte horizontale Zeile.
            SessionGamificationBar(estimate: quizSessionEstimate)

            Button {
                startQuiz()
            } label: {
                Text(session.isPreparingQuiz ? "Quiz wird gestartet..." : "Quiz starten")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: canStartQuiz && !session.isPreparingQuiz ? AppTheme.Colors.cta : AppTheme.Colors.textDisabled))
            .disabled(!canStartQuiz || session.isPreparingQuiz)
            .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + 4)
        }
        .padding(.horizontal, AppLayout.screenPadding)
    }
    .padding(.horizontal, AppLayout.screenPadding)
    .padding(.top, AppLayout.contentTopPadding)
    .padding(.bottom, AppLayout.screenPadding)
    .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
}

var quizDirectionCard: some View {
    VStack(alignment: .leading, spacing: 10) {
        Text("Abfragerichtung")
            .font(AppTheme.Typography.caption)
            .foregroundStyle(AppTheme.Colors.textSecondary)

        HStack(spacing: 10) {
            Button {
                selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
            } label: {
                HStack(spacing: 10) {
                    StraightFlagBadge(countryCode: "FR", width: 34, height: 23, labelFontSize: 11)
                    Text("→")
                        .font(.system(size: 18, weight: .black))
                    StraightFlagBadge(countryCode: "DE", width: 34, height: 23, labelFontSize: 11)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .foregroundStyle(selectedAppDirection == .frenchToGerman ? .white : AppTheme.Colors.textPrimary)
                .background(selectedAppDirection == .frenchToGerman ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                selectedAppDirectionRaw = Direction.germanToFrench.rawValue
            } label: {
                HStack(spacing: 10) {
                    StraightFlagBadge(countryCode: "DE", width: 34, height: 23, labelFontSize: 11)
                    Text("→")
                        .font(.system(size: 18, weight: .black))
                    StraightFlagBadge(countryCode: "FR", width: 34, height: 23, labelFontSize: 11)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 50)
                .foregroundStyle(selectedAppDirection == .germanToFrench ? .white : AppTheme.Colors.textPrimary)
                .background(selectedAppDirection == .germanToFrench ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
    .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
}

/// Kompakter Header für den Quiz-Setup-Screen — analog zum Karteikarten-Setup.
/// Kleiner „< Zurück" links, zentrierter „Quiz"-Titel.
var quizSetupHeader: some View {
    ZStack {
        Text("Quiz")
            .font(.system(size: 28, weight: .black, design: .rounded))
            .foregroundStyle(AppTheme.Colors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .center)

        HStack {
            Button {
                handleBackNavigation()
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Zurück")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(sectionStyle.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer()
        }
    }
    .padding(.horizontal, quizSetupCardInset)
    .padding(.top, 4)
    .padding(.bottom, 6)
}

/// „Anzahl Fragen" Card im neuen Setup-Stil. Header über `setupCardLabel`,
/// Setup-Card-Hintergrund (#0F2D48 + Border), Buttons im Mastery-Look.
var quizQuestionCountCard: some View {
    VStack(alignment: .leading, spacing: 10) {
        setupCardLabel("Anzahl Fragen")

        let options = QuizQuestionCountOption.allCases
        let rows = stride(from: 0, to: options.count, by: 2).map {
            Array(options[($0)..<min($0 + 2, options.count)])
        }
        VStack(spacing: 6) {
            ForEach(rows, id: \.first) { row in
                HStack(spacing: 6) {
                    ForEach(row) { option in
                        quizCountButton(option)
                    }
                }
            }
        }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
    .appSetupCardBackground(cornerRadius: AppLayout.largeCardCornerRadius)
}

func quizCountButton(_ option: QuizQuestionCountOption) -> some View {
    let isSelected = session.questionCountOption == option
    return Button {
        withAnimation(.easeInOut(duration: 0.12)) {
            session.questionCountOption = option
        }
    } label: {
        Text(option.title)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 50)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color(hex: "#1A3A55") : Color(hex: "#1A2A40"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(
                        isSelected ? AppTheme.Colors.elumiBlue : Color(hex: "#243B55"),
                        lineWidth: isSelected ? 1.5 : 1
                    )
            )
    }
    .buttonStyle(.plain)
}

var quizSessionScreen: some View {
    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
        // Kompakter Header analog Karteikarten — kleiner „< Zurück" links,
        // „Quiz"-Titel mittig. Zurück führt zur Setup-Card (handleBackNavigation),
        // nicht raus zu Home. ScreenHeaderCard + großer Zurück-Button raus.
        quizSetupHeader

        AppSurfaceCard(tint: sectionStyle.accent) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack {
                    Text("\(min(session.currentQuestionIndex + 1, displayedQuestionCount)) von \(displayedQuestionCount)")
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Spacer(minLength: 0)
                    Text("\(correctCount) richtig · \(wrongCount) falsch")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
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
    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
        ScreenHeaderCard(
            style: sectionStyle,
            title: "Ergebnis",
            subtitle: "",
            systemImage: "rosette"
        )

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
        SessionSummaryView(
            outcome: quizSessionOutcome ?? .empty,
            progress: progressStore.progress
        )

        if wrongCount > 0 {
            Button {
                showingWrongAnswers = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16, weight: .bold))
                    Text("Falsche anzeigen (\(wrongCount))")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppSecondaryButtonStyle(tint: AppTheme.Colors.error))
        }

        Button {
            resetQuizToSetup()
            startQuiz()
        } label: {
            Text("Nochmal")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))

        Button {
            handleBackNavigation()
        } label: {
            Label("Zurück", systemImage: "arrow.left")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppSecondaryButtonStyle(tint: sectionStyle.accent))

        Spacer(minLength: 0)
    }
    .padding(.horizontal, AppLayout.screenPadding)
    .padding(.top, AppLayout.contentTopPadding)
    .padding(.bottom, AppLayout.screenPadding)
    .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
