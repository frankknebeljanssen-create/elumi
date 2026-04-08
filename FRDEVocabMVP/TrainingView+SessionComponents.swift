import SwiftUI

extension TrainingView {
    var sessionCard: some View {
        Group {
            if let currentCard, session.hasStartedTraining {
                VStack(alignment: .center, spacing: 8) {
                    Text(isArticleMode ? "ARTIKEL" : currentCard.category.uppercased())
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    Text(isArticleMode ? (articlePromptText ?? currentCard.prompt) : currentCard.prompt)
                        .font(isArticleMode ? .system(size: 32, weight: .black, design: .rounded) : sessionPromptFont)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                        .lineLimit(5)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity, minHeight: sessionCardMinHeight, alignment: .center)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .appCardBackground(sectionStyle, intensity: 0.07)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Keine Karten")
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text(startHintText)
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .appCardBackground(sectionStyle, intensity: 0.07)
            }
        }
    }

    var responseCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsNotRecognizedMessage {
                Text("Nicht erkannt, bitte nochmal versuchen.")
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if showsSolutionMessage, let currentCard {
                Text("Lösung")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)
                Text(currentCard.answer)
                    .font(AppTheme.Typography.screenTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
            } else if !session.hasStartedTraining {
                Text("Bereit?")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Tippe oben auf Los geht's!, dann startet die erste Karte direkt.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            } else {
                Text("Antwort")
                    .font(AppTheme.Typography.cardTitle)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text((speechController?.transcript ?? "").isEmpty ? "Noch nichts erkannt" : (speechController?.transcript ?? ""))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(AppTheme.Typography.body)
                    .foregroundStyle((speechController?.transcript ?? "").isEmpty ? AppTheme.Colors.textSecondary : AppTheme.Colors.textPrimary)
                    .lineLimit(5)
                    .minimumScaleFactor(0.55)
            }

            if let error = speechController?.recordError {
                Text("Hinweis: \(error)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.error)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
        .padding(14)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }

    var articleButtons: some View {
        VStack(spacing: 10) {
            if showsSuccessOnlyMessage {
                Text("Richtig 🙂")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .foregroundStyle(.white)
                    .background(AppTheme.Colors.success)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            } else if showsRetryOnlyMessage {
                Text("Falsch 😕")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .foregroundStyle(.white)
                    .background(Color(red: 0.9, green: 0.3, blue: 0.15))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            } else {
                HStack(spacing: 10) {
                    ForEach(["le", "la", "l'"], id: \.self) { article in
                        Button {
                            submitArticle(article)
                        } label: {
                            Text(article)
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: actionButtonHeight)
                                .foregroundStyle(.white)
                                .background(trainingActionTint)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                        }
                        .buttonStyle(.plain)
                        .disabled(articleLocked)
                    }
                }
            }

            // Translation hint button — always show German translation
            if let item = session.currentTrainingItem, !showsSuccessOnlyMessage, !showsRetryOnlyMessage {
                Button {
                    showingArticleTranslation.toggle()
                } label: {
                    if showingArticleTranslation {
                        Text(item.german)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(AppTheme.Colors.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                    } else {
                        Label("Übersetzung", systemImage: "eye")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.Colors.textSecondary)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 44)
                            .background(AppTheme.Colors.secondarySurface)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    var verbMCCard: some View {
        VStack(spacing: 8) {
            if let selected = verbMCSelected, let currentCard {
                let isCorrect = normalized(selected) == normalized(currentCard.answer)
                Text(isCorrect ? "Richtig 🙂" : "Falsch 😕 → \(currentCard.answer)")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(isCorrect ? AppTheme.Colors.success : Color(red: 0.9, green: 0.3, blue: 0.15))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            }

            let columns = [GridItem(.flexible(), spacing: 8), GridItem(.flexible(), spacing: 8)]
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(verbMCOptions, id: \.self) { option in
                    Button {
                        submitVerbMC(option)
                    } label: {
                        Text(option)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .lineLimit(2)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: 48)
                            .foregroundStyle(verbMCButtonForeground(option))
                            .background(verbMCButtonBackground(option))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .disabled(verbMCLocked)
                }
            }
        }
    }

    func verbMCButtonForeground(_ option: String) -> Color {
        guard let selected = verbMCSelected, let currentCard else {
            return .white
        }
        let correct = normalized(currentCard.answer)
        if normalized(option) == correct { return .white }
        if normalized(option) == normalized(selected) { return .white }
        return AppTheme.Colors.textPrimary.opacity(0.5)
    }

    func verbMCButtonBackground(_ option: String) -> Color {
        guard let selected = verbMCSelected, let currentCard else {
            return trainingActionTint
        }
        let correct = normalized(currentCard.answer)
        if normalized(option) == correct { return AppTheme.Colors.success }
        if normalized(option) == normalized(selected) { return Color(red: 0.9, green: 0.3, blue: 0.15) }
        return AppTheme.Colors.secondarySurface
    }


    var actionButtons: some View {
        VStack(spacing: 10) {
            Button {
                toggleRecording()
            } label: {
                Group {
                    if showsSuccessOnlyMessage {
                        Text("Richtig 🙂")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                    } else if showsRetryOnlyMessage {
                        Text("Falsch 😕")
                            .font(.system(size: 26, weight: .bold, design: .rounded))
                    } else {
                        Image(systemName: recordingSymbolName)
                            .font(.system(size: 28, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: actionButtonHeight)
                .foregroundStyle(.white)
                .background(recordingButtonColor)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .stroke(Color.white.opacity(isSpeechRecording && isMicPulseVisible ? 0.28 : 0), lineWidth: 2)
                    .animation(.easeInOut(duration: 0.55), value: isMicPulseVisible)
            }
            .disabled(!session.hasStartedTraining || currentCard == nil || !isAudioModeEnabled || !canUseSpeechRecognition)
            .opacity(!session.hasStartedTraining || currentCard == nil || !isAudioModeEnabled || !canUseSpeechRecognition ? 0.45 : (isSpeechRecording && isMicPulseVisible ? 0.72 : 1))

            typedAnswerControl

            Button {
                speakCurrentPrompt()
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 25, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .foregroundStyle(.white)
                    .background(listeningButtonColor)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(!session.hasStartedTraining || currentCard == nil || !isAudioModeEnabled)
            .opacity(!session.hasStartedTraining || currentCard == nil || !isAudioModeEnabled ? 0.45 : 1)

            HStack(spacing: 10) {
                Button {
                    revealSolution()
                } label: {
                    Label(solutionButtonTitle, systemImage: "lightbulb")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: actionButtonHeight)
                        .font(AppTheme.Typography.button)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .buttonStyle(AppSecondaryButtonStyle(tint: trainingActionTint))
                .disabled(!canRevealSolution)
                .opacity(canRevealSolution ? 1 : 0.6)

                Button {
                    cancelPendingFeedback()
                    loadNextTrainingCard()
                    speakCurrentPromptAfterScreenUpdate(initialDelay: 0.06)
                } label: {
                    Label(nextCardTitle, systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: actionButtonHeight)
                        .font(AppTheme.Typography.button)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .buttonStyle(AppSecondaryButtonStyle(tint: trainingActionTint))
                .disabled(!session.hasStartedTraining || session.preparedTrainingItems.isEmpty)
                .opacity(!session.hasStartedTraining || session.preparedTrainingItems.isEmpty ? 0.5 : 1)
            }
        }
    }

    var typedAnswerControl: some View {
        Group {
            if showingTypedAnswerInput {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(trainingActionTint)

                    TextField("Antwort tippen", text: $typedAnswer)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!session.hasStartedTraining || currentCard == nil)
                        .focused($typedAnswerFieldFocused)
                        .onSubmit {
                            submitTypedAnswer()
                        }

                    Button("Prüfen") {
                        submitTypedAnswer()
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                    .disabled(!session.hasStartedTraining || currentCard == nil || typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .appCardBackground(sectionStyle, intensity: 0.09)
            } else {
                Button {
                    guard session.hasStartedTraining, currentCard != nil else { return }
                    stopListeningForTyping()
                    showingTypedAnswerInput = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        typedAnswerFieldFocused = true
                    }
                } label: {
                    Image(systemName: "keyboard")
                        .font(.system(size: 25, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: actionButtonHeight)
                        .foregroundStyle(trainingActionTint)
                        .appCardBackground(sectionStyle, intensity: 0.11)
                }
                .buttonStyle(.plain)
                .disabled(!session.hasStartedTraining || currentCard == nil)
                .opacity(!session.hasStartedTraining || currentCard == nil ? 0.5 : 1)
            }
        }
    }
}
