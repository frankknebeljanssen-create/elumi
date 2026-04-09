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
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(sectionStyle.accent)
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: AppLayout.largeSelectionHeight)
                .padding(.horizontal, AppTheme.Spacing.md)
                .appCardBackground(sectionStyle, intensity: 0.11, cornerRadius: AppLayout.largeCardCornerRadius)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, quizSetupCardInset)
            .padding(.bottom, AppTheme.Spacing.sm)

            quizDirectionCard
                .padding(.horizontal, quizSetupCardInset)
                .padding(.bottom, AppTheme.Spacing.sm)

            AppSurfaceCard(tint: sectionStyle.accent) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fragen")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    let options = QuizQuestionCountOption.allCases
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(options.prefix(2)) { option in
                                quizCountButton(option)
                            }
                        }
                        HStack(spacing: 8) {
                            ForEach(options.suffix(2)) { option in
                                quizCountButton(option)
                            }
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
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(.bottom, AppTheme.Spacing.sm)
    }
    .safeAreaInset(edge: .bottom) {
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
        .padding(.bottom, AppTheme.Layout.footerHeight + AppLayout.bottomBarInsetBottom + 16)
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

func quizCountButton(_ option: QuizQuestionCountOption) -> some View {
    Button {
        withAnimation(.easeInOut(duration: 0.12)) {
            session.questionCountOption = option
        }
    } label: {
        Text(option.title)
            .font(.system(size: 18, weight: .bold, design: .rounded))
            .foregroundStyle(session.questionCountOption == option ? .white : AppTheme.Colors.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 44)
            .background(session.questionCountOption == option ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }
    .buttonStyle(.plain)
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
