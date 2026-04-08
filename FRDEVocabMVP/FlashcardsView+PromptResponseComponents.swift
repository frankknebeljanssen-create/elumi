import SwiftUI

extension FlashcardsView {
    var flashcardPromptCard: some View {
        Group {
            if let currentFlashCard, sessionStore.hasActiveSession {
                VStack(spacing: 10) {
                    Text(progressText)
                        .font(AppTheme.Typography.caption)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)

                    masteryProgressBar
                        .frame(height: 8)
                        .clipShape(Capsule())
                }

                ZStack(alignment: .bottomTrailing) {
                        ZStack {
                            flashcardFace(
                                text: currentFlashCard.prompt,
                                isAnswerSide: false,
                                languageCode: currentFlashCard.promptLanguageCode
                            )
                            .opacity(interaction.isFlashcardFlipped ? 0 : 1)

                            flashcardFace(
                                text: currentFlashCard.answer,
                                isAnswerSide: true,
                                languageCode: currentFlashCard.answerLanguageCode
                            )
                            .opacity(interaction.isFlashcardFlipped ? 1 : 0)
                            .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0), perspective: 0.72)
                        }
                        .rotation3DEffect(
                            .degrees(interaction.isFlashcardFlipped ? 180 : 0),
                            axis: (x: 0, y: 1, z: 0),
                            perspective: 0.72
                        )
                        .shadow(color: .black.opacity(0.08), radius: 14, x: 0, y: 8)
                        .shadow(color: AppTheme.Shadow.card.color, radius: 14, x: 0, y: 8)
                        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: interaction.isFlashcardFlipped)

                        FlashcardStackBadge(
                            remainingCount: sessionStore.remainingCount,
                            totalCount: sessionStore.totalCount
                        )
                        .padding(.trailing, 8)
                        .padding(.bottom, 8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: flashcardFaceHeight)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard isSessionReady else { return }
                        if interaction.showingSolution {
                            interaction.flipBackToFront(dismissTypedAnswerFocus: { dismissTypedAnswerFocus() })
                        } else {
                            interaction.revealSolution(
                                speechController: speechController,
                                dismissTypedAnswerFocus: { dismissTypedAnswerFocus() }
                            )
                        }
                    }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
                .offset(x: interaction.cardFlyOutOffset)
                .rotationEffect(.degrees(interaction.cardFlyOutRotation))
                .opacity(interaction.cardFlyOutOpacity)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Bereit für Karteikarten?")
                        .font(AppTheme.Typography.cardTitle)
                        .foregroundStyle(AppTheme.Colors.textPrimary)
                    Text("Starte oben deinen Karteikarten-Stapel.")
                        .font(AppTheme.Typography.body)
                        .foregroundStyle(AppTheme.Colors.textSecondary)
                        .lineLimit(3)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .appCardBackground(sectionStyle, intensity: 0.07)
            }
        }
    }

    var flashcardResponseCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isFlashcardSessionCompleted {
                Text("Alle Karten aus dem Stapel sind raus. 🙂")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.success)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if interaction.showingSolution {
                Text("Rückseite geöffnet")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(sectionStyle.accent)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if interaction.lastResult?.label == "Nicht erkannt" {
                Text("Nicht erkannt, bitte nochmal versuchen.")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            } else if sessionStore.hasActiveSession {
                Text("Antwort")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text(speechController.transcript.isEmpty ? "Noch nichts erkannt" : speechController.transcript)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(speechController.transcript.isEmpty ? AppTheme.Colors.textSecondary : AppTheme.Colors.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            } else {
                Text("Fortschritt")
                    .font(AppTheme.Typography.body)
                    .foregroundStyle(AppTheme.Colors.textPrimary)
                Text("Richtige Karten werden aus dem Stapel entfernt. Falsche Karten bleiben drin, bis du am Ende alle geschafft hast.")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            }

            if let error = speechController.recordError {
                Text("Hinweis: \(error)")
                    .font(AppTheme.Typography.caption)
                    .foregroundStyle(AppTheme.Colors.error)
                    .lineLimit(3)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: 46, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .appCardBackground(sectionStyle, intensity: 0.09)
    }

    var masteryProgressBar: some View {
        GeometryReader { geo in
            let total = max(sessionStore.totalCount, 1)
            let mastered = CGFloat(sessionStore.masteredCount) / CGFloat(total)
            let almost = CGFloat(sessionStore.almostMasteredCount) / CGFloat(total)
            let width = geo.size.width

            ZStack(alignment: .leading) {
                // Background (open)
                Capsule()
                    .fill(AppTheme.Colors.textSecondary.opacity(0.2))

                // Almost mastered (yellow)
                Capsule()
                    .fill(AppTheme.Colors.warning.opacity(0.7))
                    .frame(width: max(0, width * (mastered + almost)))

                // Mastered (green)
                Capsule()
                    .fill(AppTheme.Colors.success)
                    .frame(width: max(0, width * mastered))
            }
        }
    }
}
