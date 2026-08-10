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
///
/// **2026-08-08** — rückt den Streak NICHT mehr vor. Das ist jetzt
/// entkoppelt: `ProgressService.record(session:)` triggert den Streak
/// direkt über `ProgressStore.advanceStreakIfNeeded`, sobald an einem Tag
/// `GamificationConfig.streakMiniSessionThreshold` korrekte Antworten
/// erreicht sind — unabhängig davon, ob die (größere) Daily Challenge
/// hier fertig wird. Siehe `StreakJokerStore` für die Begründung.
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

        // **Phase E.4** — Account-Switch-Hook: der neue Account hat
        // seine eigene Daily-Challenge. Reload aus seinem Namespace,
        // danach refresh (falls die gespeicherte Challenge für heute
        // nicht mehr gilt, wird eine frische generiert).
        NotificationCenter.default.addObserver(
            forName: AccountStore.didSwitchAccount,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadForCurrentAccount()
            }
        }
    }

    /// **Phase E.4** — lädt die Daily-Challenge für den neu aktiven
    /// Account aus seinem Namespace, generiert falls nötig eine neue
    /// für den aktuellen Tag.
    func reloadForCurrentAccount() {
        challenge = nil
        lastCompletionOutcome = nil
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

    // MARK: - Reward

    /// Schüttet den Challenge-Reward aus. **Kein** paralleler Credit-/
    /// XP-Zähler — der zentrale Store bleibt Single Source of Truth.
    ///
    /// **2026-08-08** — rückt NICHT mehr den Streak vor. Der Streak ist
    /// vom vollen Tagesziel entkoppelt: er wird jetzt zentral in
    /// `ProgressService.record(session:)` über `ProgressStore.advanceStreakIfNeeded`
    /// getriggert, sobald `GamificationConfig.streakMiniSessionThreshold`
    /// korrekte Antworten an einem Tag erreicht sind — unabhängig davon,
    /// ob (und wann) die größere Daily Challenge hier fertig wird.
    private func awardCompletionReward(for challenge: DailyChallenge) -> DailyChallengeCompletionOutcome {
        let today = GamificationConfig.currentDayIndex
        let store = ProgressStore.shared

        store.mutate { p in
            p.totalXP += challenge.reward.xp
            p.arcadeCredits += challenge.reward.credits
            // Daily-Bonus-Marker setzen — damit das bestehende
            // `isDailyBonusAvailable` konsistent auf „heute erledigt"
            // kippt (UI-Komponenten, die noch darauf lesen, bleiben ohne
            // Umbau korrekt).
            p.lastDailyBonusDayIndex = today
        }

        return DailyChallengeCompletionOutcome(
            xpAwarded: challenge.reward.xp,
            creditsAwarded: challenge.reward.credits
        )
    }

    // MARK: - Persistence

    /// Per-Account-Key (Phase E.4). Fallback auf den globalen Key,
    /// solange kein Account aktiv ist (Erstinstall).
    private var scopedKey: String {
        AccountStore.shared.namespacedKey(appDailyChallengeKey)
    }

    private func load() {
        // Zuerst scoped Key lesen. Wenn nichts da ist (z. B. erster
        // Start nach Update in den ersten migrierten Account), auf
        // den globalen Legacy-Key fallen und sofort in den scoped
        // Slot persistieren.
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: scopedKey),
           let decoded = try? JSONDecoder().decode(DailyChallenge.self, from: data) {
            self.challenge = decoded
            return
        }
        if scopedKey != appDailyChallengeKey,
           let legacyData = defaults.data(forKey: appDailyChallengeKey),
           let legacy = try? JSONDecoder().decode(DailyChallenge.self, from: legacyData) {
            self.challenge = legacy
            defaults.set(legacyData, forKey: scopedKey)
        }
    }

    private func persist() {
        guard let challenge, let data = try? JSONEncoder().encode(challenge) else { return }
        UserDefaults.standard.set(data, forKey: scopedKey)
    }
}
