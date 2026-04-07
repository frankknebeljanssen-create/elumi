import SwiftUI

extension FlashcardsView {
    var flashcardTypedAnswerCard: some View {
        Group {
            if interaction.showingTypedAnswerInput {
                HStack(spacing: 8) {
                    TextField("Antwort tippen", text: $interaction.typedAnswer)
                        .textFieldStyle(.roundedBorder)
                        .focused($isTypedAnswerFocused)
                        .disabled(!isSessionReady)
                        .onTapGesture {
                            interaction.handleAudioModeChange(
                                isEnabled: false,
                                speechController: speechController,
                                speaker: speaker
                            )
                        }
                        .onSubmit {
                            submitTypedAnswer()
                        }

                    Button {
                        dismissTypedAnswerFocus()
                    } label: {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .font(.system(size: 22, weight: .bold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.Colors.textPrimary)

                    Button("Prüfen") {
                        submitTypedAnswer()
                    }
                    .buttonStyle(AppPrimaryButtonStyle(color: AppTheme.Colors.cta))
                    .disabled(!isSessionReady || interaction.typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(10)
                .frame(maxWidth: AppTheme.Layout.maxContentWidth)
                .appCardBackground(sectionStyle, intensity: 0.12)
                .shadow(color: AppTheme.Shadow.card.color, radius: 12, x: 0, y: 8)
            }
        }
    }

    var flashcardActionButtons: some View {
        VStack(spacing: 10) {
            Button {
                toggleRecording()
            } label: {
                Group {
                    if showsSuccessOnlyMessage {
                        Text("Korrekt! 🙂")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                    } else if showsWrongOnlyMessage {
                        Text("Falsch")
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                    } else {
                        Image(systemName: recordingSymbolName)
                            .font(.system(size: 28, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: actionButtonHeight)
                .foregroundStyle(.white)
                .background(flashcardRecordingButtonColor)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            }
            .buttonStyle(.plain)
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .stroke(Color.white.opacity(speechController.isRecording && interaction.isMicPulseVisible ? 0.28 : 0), lineWidth: 2)
                    .animation(.easeInOut(duration: 0.55), value: interaction.isMicPulseVisible)
            }
            .disabled(!isSessionReady || !isAudioModeEnabled || !canUseSpeechRecognition)
            .opacity(!isSessionReady || !isAudioModeEnabled || !canUseSpeechRecognition ? 0.45 : (speechController.isRecording && interaction.isMicPulseVisible ? 0.72 : 1))

            Button {
                speakCurrentPrompt()
            } label: {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 28, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                    .appCardBackground(sectionStyle, intensity: 0.11)
            }
            .buttonStyle(.plain)
            .disabled(!isSessionReady || !isAudioModeEnabled)
            .opacity(isSessionReady && isAudioModeEnabled ? 1 : 0.45)

            Button {
                showFlashcardTypedAnswerField()
            } label: {
                Image(systemName: "keyboard")
                    .font(.system(size: 28, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: actionButtonHeight)
                    .foregroundStyle(interaction.showingTypedAnswerInput ? .white : AppTheme.Colors.textPrimary)
                    .background(interaction.showingTypedAnswerInput ? sectionStyle.accent : AppTheme.Colors.secondarySurface)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!isSessionReady)
            .opacity(isSessionReady ? 1 : 0.45)

            HStack(spacing: 10) {
                Button {
                    restorePreviousFlashcard()
                } label: {
                    Label("Zurück", systemImage: "arrow.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(AppTheme.Typography.button)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: flashcardSecondaryActionHeight)
                .appCardBackground(sectionStyle, intensity: 0.11)
                .disabled(!canRestorePreviousFlashcard)
                .opacity(canRestorePreviousFlashcard ? 1 : 0.5)

                Button {
                    skipCard()
                } label: {
                    Label("Überspringen", systemImage: "forward.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(AppTheme.Typography.button)
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: flashcardSecondaryActionHeight)
                .appCardBackground(sectionStyle, intensity: 0.11)
                .disabled(!isSessionReady)
                .opacity(isSessionReady ? 1 : 0.5)
            }
        }
    }
}
