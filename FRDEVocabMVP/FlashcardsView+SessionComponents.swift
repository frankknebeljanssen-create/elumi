import SwiftUI

extension FlashcardsView {
    var flashcardCompletionCard: some View {
        // Übergangs-Lösung: zeigt die neue `SessionSummaryView` mit dem
        // Outcome aus `ProgressService.record(session:)` an. Reward-Vergabe
        // findet einmal pro Session statt (Schutz via `sessionRewardConsumed`).
        //
        // **Stufe 3 (2026-05-01, Branch `feature/training-session-flow`)** —
        // Chain-Mode-Branching: bei aktivem `chainContext` wechselt der
        // Primary-CTA-Label/Action auf „Weiter zu …" / „Training
        // abschließen" und ruft den `appChainAdvanceAction`-Closure
        // mit dem Outcome. Andernfalls Bestand-Verhalten („Weiter
        // lernen" → Setup-Reset).
        let outcome = flashcardSessionOutcome ?? .empty
        let chain = launchContext?.chainContext
        let nextStepTitle = chain?.nextStep?.title
        let isChain = chain != nil
        let primaryLabel: String = isChain
            ? (nextStepTitle.map { "Weiter zu \($0)" } ?? "Training abschließen")
            : "Weiter lernen"
        return SessionSummaryView(
            outcome: outcome,
            progress: ProgressStore.shared.progress,
            primaryCTALabel: primaryLabel,
            onPrimaryCTA: {
                if isChain {
                    chainAdvance?(outcome)
                } else {
                    returnToFlashcardSetup()
                }
            },
            // „Zur Startseite"-Secondary-CTA entfernt — das Karteikarten-
            // Summary wurde damit für kleinere Screens zu lang. Der User
            // kommt jederzeit über das Home-Icon in der AppBottomBar auf
            // die Startseite zurück, daher ist der explizite Secondary-
            // Button hier entbehrlich.
            primaryCTAPulses: isChain,
            hidesDetailedStats: isChain
        )
        .onAppear {
            consumeFlashcardSessionReward()
        }
    }

    /// Berechnet die Reward einmalig bei Session-Ende (geschützt vor doppeltem
    /// `onAppear`) und cached das Outcome für die UI-Anzeige.
    func consumeFlashcardSessionReward() {
        guard !sessionStore.sessionRewardConsumed else { return }
        sessionStore.sessionRewardConsumed = true
        let session = LearningSession(
            origin: .flashcards,
            correctCount: sessionStore.session?.correctCount ?? 0,
            wrongCount: sessionStore.session?.wrongCount ?? 0,
            longestCombo: sessionStore.sessionLongestCombo,
            masteredCardCount: sessionStore.sessionMasteredThisRun
        )
        let outcome = ProgressService.shared.record(session: session)
        flashcardSessionOutcome = outcome
        // Mirror auf den Legacy-AppStorage-Wert, damit andere Views, die
        // noch direkt `arcadeCredits` lesen, konsistent bleiben.
        arcadeCredits = ProgressStore.shared.progress.arcadeCredits
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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
