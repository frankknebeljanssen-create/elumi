import Foundation
import SwiftUI

/// Zentraler Store für die Tagesaufgabe.
///
/// Rolle im System (saubere Trennung):
///   • `ProfileStore`           → Identität/Personalisierung
///   • `ProgressStore`          → XP/Level/Credits/Streak-Werte
///   • **`DailyChallengeStore`** → Tages-Task, Status, Reset, Reward-Trigger
///
/// Der Store kapselt:
///   • automatische Generierung der Tagesaufgabe (Rotation nach dayIndex)
///   • Fortschritts-Aktualisierung beim Session-Abschluss
///   • Reward-Vergabe (XP + Credit) über `ProgressStore` — **nicht** parallel
///     über eigene Zähler, damit Credits/XP weiterhin an *einer* Stelle leben
///   • Streak-Advancement (da ab Phase 5 nur die Challenge einen Tag als
///     „erfüllt" markiert — nicht mehr jede beliebige Session)
///
/// Persistenz: einzelnes Codable-JSON in UserDefaults, analog zum Muster
/// von `ProfileStore` / `ProgressStore`. Beim App-Start wird über den
/// `dayIndex` geprüft, ob die gespeicherte Challenge noch aktuell ist.
@MainActor
final class DailyChallengeStore: ObservableObject {
    static let shared = DailyChallengeStore()

    /// Die aktuelle Tagesaufgabe. `nil` nur beim allerersten Start, sonst
    /// immer mit einer gültigen Challenge für `GamificationConfig.currentDayIndex`.
    @Published private(set) var challenge: DailyChallenge?

    /// Letztes Completion-Outcome — UI-Komponenten wie die Home-Card oder
    /// die Session-Summary können darauf reagieren (Toast, Animation etc.).
    /// Wird bei Reset auf nil gesetzt.
    @Published private(set) var lastCompletionOutcome: DailyChallengeCompletionOutcome?

    // MARK: - Init

    init() {
        load()
        refreshForTodayIfNeeded()
    }

    // MARK: - Public API

    /// Sicherstellen, dass die aktuell gehaltene Challenge zum heutigen
    /// `dayIndex` passt. Falls nicht (Tageswechsel seit App-Start), wird
    /// eine neue generiert und persistiert. Idempotent — safe to call oft.
    func refreshForTodayIfNeeded() {
        let today = GamificationConfig.currentDayIndex
        if let existing = challenge, existing.dayIndex == today { return }
        let fresh = Self.generateChallenge(dayIndex: today)
        challenge = fresh
        lastCompletionOutcome = nil
        persist()
    }

    /// Wird von `ProgressService.record(session:)` aufgerufen. Aktualisiert
    /// den Challenge-Fortschritt und löst — falls das Ziel damit erreicht
    /// wird — den Reward + Streak-Advance aus.
    ///
    /// Rückgabe: Completion-Outcome **nur** in dem Call, der das Ziel
    /// schließlich überschreitet. Alle anderen Calls geben `nil`.
    @discardableResult
    func recordSession(_ session: LearningSession) -> DailyChallengeCompletionOutcome? {
        refreshForTodayIfNeeded()
        guard var c = challenge, c.status != .done else { return nil }

        let increment = c.type.progressIncrement(for: session)
        guard increment > 0 else { return nil }

        c.currentProgress = min(c.target, c.currentProgress + increment)

        if c.currentProgress >= c.target, c.status != .done {
            c.status = .done
            c.completedAt = Date()
            let outcome = awardCompletionReward(for: c)
            challenge = c
            lastCompletionOutcome = outcome
            persist()
            return outcome
        }

        c.status = c.currentProgress > 0 ? .inProgress : .open
        challenge = c
        persist()
        return nil
    }

    /// Generiert eine frische Challenge für heute und verwirft den
    /// letzten Completion-Outcome. Wird vom `GameStateResetService`
    /// (User-sichtbar) und `DebugResetService` (DEBUG) aufgerufen —
    /// `#if DEBUG`-Wrapper entfernt, damit der produktive Reset-Pfad
    /// in Release läuft. Name-Harmonisierung analog zu `DailyStatsStore`.
    func reset() {
        let today = GamificationConfig.currentDayIndex
        let fresh = Self.generateChallenge(dayIndex: today)
        challenge = fresh
        lastCompletionOutcome = nil
        persist()
    }

    // MARK: - Generation

    /// Deterministische Rotation basierend auf dem Day-Index. Jeder Tag
    /// bekommt einen festen Typ, aber die Typen wechseln sich ab → der
    /// User erlebt Abwechslung ohne Zufalls-Varianz zwischen Geräten.
    private static func generateChallenge(dayIndex: Int) -> DailyChallenge {
        let rotation: [(DailyChallengeType, DailyChallengeReward)] = [
            (.answers(target: 15), DailyChallengeReward(xp: 50, credits: 1)),
            (.completeSession,     DailyChallengeReward(xp: 40, credits: 1)),
            (.speedRound,          DailyChallengeReward(xp: 60, credits: 1))
        ]
        let idx = ((dayIndex % rotation.count) + rotation.count) % rotation.count
        let pick = rotation[idx]
        return DailyChallenge(
            id: UUID(),
            dayIndex: dayIndex,
            type: pick.0,
            target: pick.0.defaultTarget,
            currentProgress: 0,
            status: .open,
            reward: pick.1,
            completedAt: nil
        )
    }

    // MARK: - Reward + Streak

    /// Rewarded + Streak-Update in einem atomaren `ProgressStore.mutate`.
    /// **Kein** paralleler Credit-/XP-Zähler — die zentralen Stores bleiben
    /// Single Source of Truth.
    private func awardCompletionReward(for challenge: DailyChallenge) -> DailyChallengeCompletionOutcome {
        let today = GamificationConfig.currentDayIndex
        let store = ProgressStore.shared

        var streakAdvanced = false
        var newStreak = store.progress.currentStreak
        var milestoneCredits = 0

        store.mutate { p in
            // 1) Reward ausschütten
            p.totalXP += challenge.reward.xp
            p.arcadeCredits += challenge.reward.credits

            // 2) Daily-Bonus-Marker setzen — damit das bestehende
            //    `isDailyBonusAvailable` konsistent auf „heute erledigt"
            //    kippt (UI-Komponenten, die noch darauf lesen, bleiben ohne
            //    Umbau korrekt).
            p.lastDailyBonusDayIndex = today

            // 3) Streak vorrücken — nur wenn heute noch nicht passiert.
            //    Ab Phase 5 ist die Challenge der *einzige* Streak-Trigger.
            if p.lastSessionDayIndex != today {
                let gap = today - p.lastSessionDayIndex
                if p.lastSessionDayIndex < 0 || gap > 1 {
                    p.currentStreak = 1
                } else if gap == 1 {
                    p.currentStreak += 1
                }
                p.bestStreak = max(p.bestStreak, p.currentStreak)
                p.lastSessionDayIndex = today
                streakAdvanced = true
                newStreak = p.currentStreak

                // 4) Streak-Milestone-Credits (einmalig 3/7/14/30).
                if let bonus = GamificationConfig.creditsForStreakMilestones[p.currentStreak],
                   !p.awardedStreakMilestones.contains(p.currentStreak) {
                    p.arcadeCredits += bonus
                    p.awardedStreakMilestones.insert(p.currentStreak)
                    milestoneCredits = bonus
                }
            }
        }

        return DailyChallengeCompletionOutcome(
            xpAwarded: challenge.reward.xp,
            creditsAwarded: challenge.reward.credits,
            streakAdvanced: streakAdvanced,
            newStreak: newStreak,
            creditsFromStreakMilestone: milestoneCredits
        )
    }

    // MARK: - Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: appDailyChallengeKey),
              let decoded = try? JSONDecoder().decode(DailyChallenge.self, from: data) else {
            return
        }
        self.challenge = decoded
    }

    private func persist() {
        guard let challenge, let data = try? JSONEncoder().encode(challenge) else { return }
        UserDefaults.standard.set(data, forKey: appDailyChallengeKey)
    }
}
