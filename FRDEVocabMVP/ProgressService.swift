import Foundation
import SwiftUI

/// Ergebnis einer einzelnen Session-Auswertung. Wird der UI für die
/// Session-Summary-Card übergeben.
struct SessionRewardOutcome: Equatable {
    let session: LearningSession

    let baseXP: Int          // 10 × richtige Antworten
    let comboXP: Int         // Combos innerhalb der Session
    let masteryXP: Int       // Karten, die endgültig gemeistert wurden
    let flawlessXP: Int      // Bonus für 0 Fehler
    /// XP aus dem **Daily-Challenge-Reward** (wenn die Session die Tages-
    /// Aufgabe in diesem Call vollendet hat). Vor Phase 5 war das ein
    /// fester „100 XP für erste Session" — jetzt kommt der Wert vom
    /// `DailyChallengeStore` und variiert je nach Challenge-Typ.
    let dailyBonusXP: Int

    var totalXP: Int {
        baseXP + comboXP + masteryXP + flawlessXP + dailyBonusXP + variableReward.bonusXP
    }

    let creditsFromXP: Int               // XP-Milestones (alle 100 XP)
    let creditsFromLevelUp: Int          // Level-Ups in dieser Session
    let creditsFromStreakMilestone: Int  // Erst-Erreichen 3/7/14/30 Tage
    /// Credits aus dem **Daily-Challenge-Reward** — unabhängig vom Streak-
    /// Milestone. V1 gibt jede Challenge 1 Credit; spätere Balancing-
    /// Änderungen passieren im `DailyChallengeStore`, nicht hier.
    let creditsFromDailyChallenge: Int

    // MARK: - Phase 7: Variable Rewards
    //
    // Kleine, seltene Extra-Belohnung ober-/unterhalb des regulären
    // Outcomes. Nicht vorhersehbar → baut Erwartung auf ohne das
    // Balancing zu brechen. Wahrscheinlichkeiten & Werte kommen zentral
    // aus `VariableRewardEngine`.
    let variableReward: VariableRewardOutcome

    var totalCredits: Int {
        creditsFromXP + creditsFromLevelUp + creditsFromStreakMilestone + creditsFromDailyChallenge + variableReward.bonusCredit
    }

    let leveledUp: Bool
    let newLevel: Int
    let newStreak: Int
    let streakIncreasedToday: Bool   // wurde Streak heute neu hochgesetzt

    /// Neutraler Default-Wert für UI-Initialisierung (vor der ersten echten
    /// Auswertung). Entspricht „nichts passiert" — wird nie persistiert.
    static var empty: SessionRewardOutcome {
        SessionRewardOutcome(
            session: LearningSession(origin: .flashcards, correctCount: 0),
            baseXP: 0, comboXP: 0, masteryXP: 0, flawlessXP: 0, dailyBonusXP: 0,
            creditsFromXP: 0, creditsFromLevelUp: 0,
            creditsFromStreakMilestone: 0, creditsFromDailyChallenge: 0,
            variableReward: .none,
            leveledUp: false, newLevel: 1, newStreak: 0, streakIncreasedToday: false
        )
    }
}

/// High-Level-API für Lernfortschritts-Vergabe. Module rufen am Session-Ende
/// genau eine Methode auf — `record(session:)` — und bekommen ein
/// `SessionRewardOutcome` zurück, das sie der UI (Summary-Card) zeigen.
///
/// Der Service kapselt:
///   • XP-Berechnung nach den Regeln aus `GamificationConfig`
///   • Streak-Update (Day-Index basiert)
///   • Level-Up-Erkennung + Credits-Vergabe
///   • Daily-Bonus-Throttling (nur einmal pro Tag)
///   • Streak-Milestone-Boni (3/7/14/30 Tage, einmalig)
///
/// Nicht abgedeckt (bewusst, kommt später):
///   • Daily Challenges
///   • Badge-System
///   • Detail-Statistik pro Modul
@MainActor
final class ProgressService {
    /// App-weiter Singleton, gekoppelt an `ProgressStore.shared`.
    static let shared = ProgressService(store: .shared)

    private let store: ProgressStore

    init(store: ProgressStore) {
        self.store = store
    }

    // MARK: - Hauptaufruf

    /// Hauptmethode: nimmt eine `LearningSession` und vergibt alle Belohnungen.
    /// Liefert ein `SessionRewardOutcome` für die UI.
    ///
    /// Ab Phase 5 (Daily-Challenge-System):
    ///  • Session-XP + XP-Milestone-Credits + Level-Up-Credits bleiben hier.
    ///  • Streak-Advance, Daily-Bonus-XP und Streak-Milestone-Credits werden
    ///    an den `DailyChallengeStore` delegiert — er entscheidet, ob die
    ///    heutige Tages-Aufgabe durch diese Session abgeschlossen wurde.
    @discardableResult
    func record(session: LearningSession) -> SessionRewardOutcome {
        let oldLevel = store.progress.level
        let oldXP = store.progress.totalXP

        // 1) Session-XP-Komponenten berechnen (ohne Daily-Anteil — der kommt
        //    später aus dem DailyChallenge-Reward).
        let base = session.correctCount * GamificationConfig.xpPerCorrectAnswer
        let combos = max(0, session.longestCombo / GamificationConfig.xpComboThreshold)
            * GamificationConfig.xpComboBonus
        let mastery = session.masteredCardCount * GamificationConfig.xpMasteredCardBonus
        let flawless = session.isFlawless ? GamificationConfig.xpFlawlessSessionBonus : 0
        let sessionXP = base + combos + mastery + flawless

        // 2) Session-XP buchen + Credits aus XP-Milestones (alle 100 XP).
        let creditsFromXP = Self.bonusCreditsCrossingMilestones(
            previousXP: oldXP,
            newXP: oldXP + sessionXP
        )
        store.mutate { p in
            p.totalXP += sessionXP
            p.arcadeCredits += creditsFromXP
        }

        // 3) Level-Up nach der Session-XP-Buchung prüfen.
        let newLevel = store.progress.level
        let levelsGained = max(0, newLevel - oldLevel)
        let creditsFromLevelUp = levelsGained * GamificationConfig.creditsPerLevelUp
        if creditsFromLevelUp > 0 {
            store.mutate { p in p.arcadeCredits += creditsFromLevelUp }
        }

        // 4) Home-Status „Heute" fortschreiben — Anzahl der Aktionen
        //    (richtig + falsch, also alles was der User wirklich bearbeitet
        //    hat). Der Store ist feedback-only, kein Zielsystem; er
        //    ersetzt visuell die alte „Dein Fokus heute"-Card auf Home.
        //    Einziger Schreib-Pfad, damit keine Zähler-Drift zwischen
        //    Modulen entstehen kann.
        let sessionActions = session.correctCount + session.wrongCount
        DailyStatsStore.shared.recordSession(actionsCount: sessionActions)

        // 5) Daily Challenge fortschreiben. Wenn dadurch das Tagesziel
        //    erreicht wurde, bekommen wir Reward-XP + Credit zurück und
        //    der Streak wird (einmal pro Tag) vom Store hochgezogen.
        let dailyOutcome = DailyChallengeStore.shared.recordSession(session)
        let dailyBonusXP = dailyOutcome?.xpAwarded ?? 0
        let creditsFromDailyChallenge = dailyOutcome?.creditsAwarded ?? 0
        let creditsFromStreakMilestone = dailyOutcome?.creditsFromStreakMilestone ?? 0
        let streakIncreasedToday = dailyOutcome?.streakAdvanced ?? false

        // 6) Variable Reward rollen (Phase 7). Seltenes Glücksmoment,
        //    Wahrscheinlichkeiten zentral in `VariableRewardEngine`.
        //    Bonus-XP und -Credits werden **zusätzlich** auf den Store
        //    gebucht, damit sie sofort wirksam sind.
        let variableReward = VariableRewardEngine.roll(for: session)
        if variableReward.hasBonus {
            store.mutate { p in
                p.totalXP += variableReward.bonusXP
                p.arcadeCredits += variableReward.bonusCredit
            }
        }

        return SessionRewardOutcome(
            session: session,
            baseXP: base,
            comboXP: combos,
            masteryXP: mastery,
            flawlessXP: flawless,
            dailyBonusXP: dailyBonusXP,
            creditsFromXP: creditsFromXP,
            creditsFromLevelUp: creditsFromLevelUp,
            creditsFromStreakMilestone: creditsFromStreakMilestone,
            creditsFromDailyChallenge: creditsFromDailyChallenge,
            variableReward: variableReward,
            leveledUp: levelsGained > 0,
            newLevel: newLevel,
            newStreak: store.progress.currentStreak,
            streakIncreasedToday: streakIncreasedToday
        )
    }

    // MARK: - Helpers

    /// Day-Index mit 6-Uhr-Rollover. Wird über `GamificationConfig` geteilt,
    /// damit Views (Home-Daily-Chip) und Service synchron sind.
    private static var currentDayIndex: Int {
        GamificationConfig.currentDayIndex
    }

    /// Wie viele Bonus-Credits wurden zwischen `previousXP` und `newXP`
    /// durch Überschreiten von 100-XP-Schwellen verdient?
    private static func bonusCreditsCrossingMilestones(previousXP: Int, newXP: Int) -> Int {
        let step = GamificationConfig.xpPerBonusCredit
        let prevTier = previousXP / step
        let newTier = newXP / step
        return max(0, newTier - prevTier)
    }
}
