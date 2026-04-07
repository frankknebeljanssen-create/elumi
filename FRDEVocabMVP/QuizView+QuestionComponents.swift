import SwiftUI

extension QuizView {
    func resultStatCard(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: AppTheme.Spacing.xxs) {
            Text(value)
                .font(AppTheme.Typography.screenTitle)
                .foregroundStyle(tint)
            Text(title)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(tint.opacity(0.92))
        }
        .padding(.vertical, AppTheme.Spacing.xs)
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(tint.opacity(0.14))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(tint.opacity(0.42), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }

    @ViewBuilder
    func rewardChip(kind: ElumiSnackKind, value: Int) -> some View {
        if value > 0 {
            HStack(spacing: 6) {
                ElumiSnackIcon(kind, size: 18)
                Text("+\(value)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
            }
            .padding(.horizontal, AppTheme.Spacing.sm)
            .padding(.vertical, AppTheme.Spacing.xs)
            .background(AppTheme.Colors.secondarySurface)
            .clipShape(Capsule())
        }
    }

    func multipleChoiceCard(_ question: QuizMultipleChoiceQuestion) -> some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            AppSurfaceCard(tint: sectionStyle.accent) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xs) {
                    Text("Multiple Choice")
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)

                    Text(visibleQuizPromptText(question.prompt, category: question.category))
                        .font(quizPromptTypography(for: question.prompt, category: question.category))
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(quizPromptLineLimit(for: question.prompt, category: question.category))
                        .minimumScaleFactor(quizPromptMinimumScale(for: question.prompt, category: question.category))
                        .multilineTextAlignment(.leading)
                }
            }

            AppSurfaceCard(tint: sectionStyle.accent) {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                    ForEach(question.options, id: \.self) { option in
                        Button {
                            submitMultipleChoice(option, for: question)
                        } label: {
                            HStack(spacing: AppTheme.Spacing.sm) {
                                Text(visibleQuizAnswerText(option, category: question.category))
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .foregroundStyle(multipleChoiceTextColor(for: option, correctAnswer: question.correctAnswer))
                                    .multilineTextAlignment(.leading)
                                    .lineLimit(3)
                                    .minimumScaleFactor(0.78)
                                Spacer(minLength: 0)
                                Image(systemName: multipleChoiceIcon(for: option, correctAnswer: question.correctAnswer))
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(multipleChoiceTextColor(for: option, correctAnswer: question.correctAnswer))
                            }
                            .padding(.horizontal, AppTheme.Spacing.sm)
                            .padding(.vertical, AppTheme.Spacing.sm)
                            .background(multipleChoiceBackground(for: option, correctAnswer: question.correctAnswer))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(multipleChoiceLocked)
                    }
                }
            }
        }
    }

    func matchingCard(_ question: QuizMatchingQuestion) -> some View {
        AppSurfaceCard(tint: sectionStyle.accent) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Paare finden")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)

                Text(draggingPromptID == nil ? "Ziehe links zur passenden Karte rechts." : "Ziehe auf die passende Karte und lass los.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(draggingPromptID == nil ? AppTheme.Colors.textSecondary : sectionStyle.accent)

                HStack(alignment: .top, spacing: AppTheme.Spacing.sm) {
                    VStack(spacing: AppTheme.Spacing.xs) {
                        ForEach(question.pairs) { pair in
                            Text(visibleQuizPromptText(pair.prompt, category: question.category))
                                .font(AppTheme.Typography.body)
                                .foregroundStyle(matchingTextColor(for: pair.id))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 72)
                                .padding(.horizontal, AppTheme.Spacing.sm)
                                .background(matchingBackground(for: pair.id))
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                        .stroke(matchingBorderColor(for: pair.id), lineWidth: matchingBorderWidth(for: pair.id))
                                )
                                .shadow(color: matchingShadowColor(for: pair.id), radius: draggingPromptID == pair.id ? 18 : 8, x: 0, y: draggingPromptID == pair.id ? 10 : 4)
                                .scaleEffect(draggingPromptID == pair.id ? 1.035 : 1)
                                .offset(draggingPromptID == pair.id ? dragOffset : .zero)
                                .opacity(matchedPairIDs.contains(pair.id) ? 0.7 : 1)
                                .zIndex(draggingPromptID == pair.id ? 10 : 0)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: QuizPromptFramePreferenceKey.self,
                                            value: [pair.id: geo.frame(in: .named("quizMatchingArea"))]
                                        )
                                    }
                                )
                                .gesture(
                                    DragGesture(coordinateSpace: .named("quizMatchingArea"))
                                        .onChanged { value in
                                            guard !matchedPairIDs.contains(pair.id) else { return }
                                            draggingPromptID = pair.id
                                            dragOffset = value.translation
                                            updateHoveredAnswer(for: pair.id)
                                        }
                                        .onEnded { _ in
                                            finishDrag(for: pair.id, in: question)
                                        }
                                )
                        }
                    }

                    VStack(spacing: AppTheme.Spacing.xs) {
                        ForEach(question.shuffledAnswers) { pair in
                            Text(visibleQuizAnswerText(pair.answer, category: question.category))
                                .font(AppTheme.Typography.body)
                                .foregroundStyle(matchingTextColor(for: pair.id, isAnswerSide: true))
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity, minHeight: 72)
                                .padding(.horizontal, AppTheme.Spacing.sm)
                                .background(matchingBackground(for: pair.id, isAnswerSide: true))
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                        .stroke(matchingBorderColor(for: pair.id, isAnswerSide: true), lineWidth: matchingBorderWidth(for: pair.id, isAnswerSide: true))
                                )
                                .shadow(color: matchingShadowColor(for: pair.id, isAnswerSide: true), radius: 8, x: 0, y: 4)
                                .scaleEffect(1)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: QuizAnswerFramePreferenceKey.self,
                                            value: [pair.id: geo.frame(in: .named("quizMatchingArea"))]
                                        )
                                    }
                                )
                        }
                    }
                }
                .coordinateSpace(name: "quizMatchingArea")
                .onPreferenceChange(QuizPromptFramePreferenceKey.self) { frames in
                    promptFrames = frames
                }
                .onPreferenceChange(QuizAnswerFramePreferenceKey.self) { frames in
                    answerFrames = frames
                }
            }
        }
    }

    var quizProgressBar: some View {
        HStack(spacing: 6) {
            ForEach(Array((0..<displayedQuestionCount).enumerated()), id: \.offset) { index, _ in
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(progressColor(for: index))
                    .frame(maxWidth: .infinity)
                    .frame(height: 10)
            }
        }
    }

    func progressColor(for index: Int) -> Color {
        guard index < session.answeredResults.count else {
            return AppTheme.Colors.secondarySurface
        }
        return session.answeredResults[index] ? AppTheme.Colors.success : AppTheme.Colors.error
    }

    func multipleChoiceBackground(for option: String, correctAnswer: String) -> Color {
        guard multipleChoiceLocked else {
            return AppTheme.Colors.secondarySurface
        }
        if normalizedLookupText(option) == normalizedLookupText(correctAnswer) {
            return AppTheme.Colors.success.opacity(0.18)
        }
        if selectedMultipleChoiceOption == option {
            return AppTheme.Colors.error.opacity(0.18)
        }
        return AppTheme.Colors.secondarySurface
    }

    func multipleChoiceTextColor(for option: String, correctAnswer: String) -> Color {
        guard multipleChoiceLocked else {
            return AppTheme.Colors.textPrimary
        }
        if normalizedLookupText(option) == normalizedLookupText(correctAnswer) {
            return AppTheme.Colors.success
        }
        if selectedMultipleChoiceOption == option {
            return AppTheme.Colors.error
        }
        return AppTheme.Colors.textPrimary
    }

    func multipleChoiceIcon(for option: String, correctAnswer: String) -> String {
        guard multipleChoiceLocked else { return "circle.fill" }
        if normalizedLookupText(option) == normalizedLookupText(correctAnswer) {
            return "checkmark.circle.fill"
        }
        if selectedMultipleChoiceOption == option {
            return "xmark.circle.fill"
        }
        return "circle.fill"
    }

    func matchingBackground(for pairID: UUID, isAnswerSide: Bool = false) -> Color {
        if matchedPairIDs.contains(pairID) {
            return AppTheme.Colors.success.opacity(0.18)
        }
        if pairID == flashingPromptID || pairID == flashingAnswerID {
            return AppTheme.Colors.error.opacity(0.2)
        }
        if !isAnswerSide, pairID == draggingPromptID {
            return AppTheme.Colors.warning.opacity(0.22)
        }
        if !isAnswerSide, pairID == selectedPromptID {
            return AppTheme.Colors.primary.opacity(0.14)
        }
        if isAnswerSide, pairID == selectedAnswerID {
            return AppTheme.Colors.primary.opacity(0.14)
        }
        return AppTheme.Colors.secondarySurface
    }

    func matchingTextColor(for pairID: UUID, isAnswerSide: Bool = false) -> Color {
        if matchedPairIDs.contains(pairID) {
            return AppTheme.Colors.success
        }
        if pairID == flashingPromptID || pairID == flashingAnswerID {
            return AppTheme.Colors.error
        }
        if !isAnswerSide, pairID == draggingPromptID {
            return AppTheme.Colors.warning
        }
        if !isAnswerSide, pairID == selectedPromptID {
            return AppTheme.Colors.primary
        }
        if isAnswerSide, pairID == selectedAnswerID {
            return AppTheme.Colors.primary
        }
        return AppTheme.Colors.textPrimary
    }

    func matchingBorderColor(for pairID: UUID, isAnswerSide: Bool = false) -> Color {
        if matchedPairIDs.contains(pairID) {
            return AppTheme.Colors.success.opacity(0.7)
        }
        if pairID == flashingPromptID || pairID == flashingAnswerID {
            return AppTheme.Colors.error.opacity(0.75)
        }
        if !isAnswerSide, pairID == draggingPromptID {
            return AppTheme.Colors.warning.opacity(0.92)
        }
        if !isAnswerSide, pairID == selectedPromptID {
            return AppTheme.Colors.primary.opacity(0.45)
        }
        if isAnswerSide, pairID == selectedAnswerID {
            return AppTheme.Colors.primary.opacity(0.45)
        }
        return AppTheme.Colors.borderStrong
    }

    func matchingBorderWidth(for pairID: UUID, isAnswerSide: Bool = false) -> CGFloat {
        if !isAnswerSide, pairID == draggingPromptID {
            return 2
        }
        if matchedPairIDs.contains(pairID) || pairID == flashingPromptID || pairID == flashingAnswerID {
            return 1.6
        }
        return 1
    }

    func matchingShadowColor(for pairID: UUID, isAnswerSide: Bool = false) -> Color {
        if matchedPairIDs.contains(pairID) {
            return AppTheme.Colors.success.opacity(0.18)
        }
        if pairID == flashingPromptID || pairID == flashingAnswerID {
            return AppTheme.Colors.error.opacity(0.18)
        }
        if !isAnswerSide, pairID == draggingPromptID {
            return AppTheme.Colors.warning.opacity(0.24)
        }
        return AppTheme.Colors.shadow
    }
}
