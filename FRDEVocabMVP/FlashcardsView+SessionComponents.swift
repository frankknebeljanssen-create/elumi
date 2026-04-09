import SwiftUI

extension FlashcardsView {
    var flashcardCompletionCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "party.popper.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(AppTheme.Colors.warning)

            Text("Stapel geschafft!")
                .font(AppTheme.Typography.cardTitle)
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text(flashcardCompletionMessage)
                .font(AppTheme.Typography.body)
                .foregroundStyle(AppTheme.Colors.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                flashcardCompletionStat(
                    title: "Richtig",
                    value: "\(flashcardCompletionCorrectCount)",
                    color: AppTheme.Colors.success
                )
                flashcardCompletionStat(
                    title: "Fehler",
                    value: "\(flashcardCompletionWrongCount)",
                    color: AppTheme.Colors.warning
                )
            }

            let credits = ArcadeCreditSystem.flashcardCredits(
                masteredCount: sessionStore.masteredCount,
                totalCount: sessionStore.totalCount,
                wrongCount: sessionStore.wrongCount
            )
            if credits > 0 {
                Text("+\(credits) Arcade Credit\(credits > 1 ? "s" : "")")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.Colors.warning)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(AppTheme.Colors.warning.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .appCardBackground(sectionStyle, intensity: 0.12, cornerRadius: AppLayout.largeCardCornerRadius)
        .onAppear {
            let credits = ArcadeCreditSystem.flashcardCredits(
                masteredCount: sessionStore.masteredCount,
                totalCount: sessionStore.totalCount,
                wrongCount: sessionStore.wrongCount
            )
            if credits > 0 {
                arcadeCredits += credits
            }
        }
    }

    func flashcardCompletionStat(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(color)
            Text(title)
                .font(AppTheme.Typography.caption)
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(AppTheme.Colors.secondarySurface)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    var flashcardCompletionCorrectCount: Int {
        sessionStore.session?.correctCount ?? sessionStore.masteredCount
    }

    var flashcardCompletionWrongCount: Int {
        sessionStore.session?.wrongCount ?? sessionStore.wrongCount
    }

    var flashcardCompletionMessage: String {
        if flashcardCompletionWrongCount == 0 {
            return "Alles geschafft, ganz ohne Fehler. Sehr stark."
        }

        return "Alle Karten sind durch. Du kannst jetzt zurück zur Auswahl gehen und den nächsten Stapel starten."
    }
}
