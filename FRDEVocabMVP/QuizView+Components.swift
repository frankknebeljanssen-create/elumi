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
        VStack(alignment: .leading, spacing: 8) {
            ScreenHeaderCard(
                style: sectionStyle,
                title: "Quiz",
                subtitle: "",
                systemImage: "lightbulb.fill"
            )

            Button {
                showingQuizListPicker = true
            } label: {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Ausgewählte Listen")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                        Text(quizListSummary)
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(sectionStyle.accent)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: 72)
                .padding(.horizontal, 18)
                .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: 22)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, quizSetupCardInset)

            AppSurfaceCard(tint: sectionStyle.accent) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fragen")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    HStack(spacing: 8) {
                        ForEach(QuizQuestionCountOption.allCases) { option in
                            Button {
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    session.questionCountOption = option
                                }
                            } label: {
                                Text(option.title)
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(session.questionCountOption == option ? .white : AppTheme.Colors.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(minHeight: 34)
                                    .background(session.questionCountOption == option ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, quizSetupCardInset)

            if !canStartQuiz {
                Text("Wähle mindestens eine Liste mit zwei Einträgen.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .padding(.horizontal, quizSetupCardInset)
            }

            Button {
                startQuiz()
            } label: {
                Text(session.isPreparingQuiz ? "Quiz wird gestartet..." : "Quiz starten")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
            .disabled(!canStartQuiz || session.isPreparingQuiz)
            .opacity(canStartQuiz && !session.isPreparingQuiz ? 1 : 0.55)
            .padding(.horizontal, quizSetupCardInset)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.bottom, AppTheme.Spacing.sm)
    }
    .padding(.horizontal, AppLayout.screenPadding)
    .padding(.top, AppLayout.contentTopPadding)
    .padding(.bottom, AppLayout.screenPadding)
    .frame(maxWidth: AppTheme.Layout.maxContentWidth, maxHeight: .infinity, alignment: .top)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
}

var quizSessionScreen: some View {
    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
        ScreenHeaderCard(
            style: sectionStyle,
            title: "Quiz",
            subtitle: "",
            systemImage: "lightbulb.fill"
        )

        Button {
            resetQuizToSetup()
        } label: {
            Label("Zurück zur Auswahl", systemImage: "arrow.left")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppSecondaryButtonStyle(tint: sectionStyle.accent))

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
                matchingCard(question)
            case .typing(let question):
                typingCard(question)
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
                    resultStatCard(
                        title: "XP",
                        value: "\(awardedXP)",
                        tint: sectionStyle.accent
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

        Button {
            resetQuizToSetup()
        } label: {
            Text("Nochmal")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))

        Button {
            dismissToHome()
        } label: {
            Text("Zur Startseite")
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
}
}
