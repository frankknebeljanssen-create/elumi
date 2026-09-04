import Foundation

#if DEBUG

/// Debug-only Helper zum Zurücksetzen des gesamten Spielstands.
///
/// **Nur für die Entwicklungsphase.** Die gesamte Logik ist per
/// `#if DEBUG` gekapselt — im Release-Build ist die Datei leer und die
/// aufrufende Settings-UI (devResetCard in SettingsView) verschwindet
/// ebenfalls. Kein manuelles Aufräumen später nötig.
///
/// **Umfang** (konsistent mit der Settings-Reset-Card):
/// - `ProgressStore` → XP, Streak (current + best), Arcade-Credits,
///   Day-Index-Marker, Milestone-Set
/// - `DailyStatsStore` → Tages-Counter (actionsToday, lastSessionDelta)
/// - `DailyChallengeStore` → heutige Challenge + Completion-Outcome
/// - Standalone-`@AppStorage`-Keys: Würmer (Quiz), Wasserfloh, Algenkugel,
///   Arcade-Highscore
/// - **Alle Session-Resume-Snapshots** (Training, Akzente, Quiz) —
///   sonst würde ein Debug-Reset zwar den Spielstand zurücksetzen,
///   aber eine alte „laufende" Runde bliebe weiter liegen und der
///   Tester landet beim nächsten Modul-Start mitten im Fortschritt
///   der vorherigen Session.
///
/// **Nicht enthalten** (absichtlich — kein Spielstand, sondern User-Daten):
/// Profil/Vorname, Onboarding-Flag, Custom-Listen, Lexikon-Cache,
/// Sprach-Richtung, Selected-Lists pro Trainings-Modus.
@MainActor
enum DebugResetService {
    /// Debug-Fassade — delegiert an den produktiven
    /// `GameStateResetService`. Beide Pfade (Dev-Reset-Card + Release-
    /// Settings-Card) laufen damit durch **dieselbe** Logik, kein
    /// Drift zwischen Debug und Release.
    static func resetGameState() {
        GameStateResetService.resetGameState()
    }
}

#endif
