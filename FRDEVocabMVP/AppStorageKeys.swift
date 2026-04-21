// Shared app storage keys extracted from ContentView.swift

// MARK: - Profile
// Nutzerprofil lebt im ProfileStore (JSON-Codable in UserDefaults).
// `appFirstNameKey` bleibt als Legacy-Mirror bestehen, damit ältere
// @AppStorage-Reader während der Migrationsphase kompatibel bleiben.
let appFirstNameKey = "myVoc.account.firstName.v1"
let appLearnerProfileKey = "elumi.profile.learner.v1"
let appOnboardingCompletedKey = "elumi.profile.onboarding.completed.v1"

// MARK: - Accounts (Multi-User, Phase 8)
// Liste aller angelegten Accounts auf diesem Gerät (Codable-JSON-Array
// von `AccountProfile`). `currentAccountID` zeigt auf den aktiven.
// Migration existierender Single-User-Daten läuft beim ersten Start
// nach App-Update — der vorhandene `LearnerProfile` wandert in die
// Liste als erster Account („Frank" als Test-Account des Owners).
let appAccountListKey = "elumi.accounts.list.v1"
let appCurrentAccountIDKey = "elumi.accounts.current.id.v1"
let appAccountsMigratedKey = "elumi.accounts.migrated.v1"

// MARK: - Daily Challenge
// Phase 5: Tages-Aufgabe + Streak. Wird als Codable-JSON im
// `DailyChallengeStore` persistiert. Reset passiert nicht über einen
// extra Flag, sondern über `dayIndex`-Vergleich beim App-Start.
let appDailyChallengeKey = "elumi.daily.challenge.v1"

let appQuizHeartsKey = "myVoc.quiz.hearts.v1"
let appElumiWaterflohKey = "elumi.gamification.wasserfloh.v1"
let appElumiAlgenkugelKey = "elumi.gamification.algenkugel.v1"
let appElumiXPKey = "elumi.gamification.xp.v1"
let appElumiCurrentStreakKey = "elumi.gamification.currentStreak.v1"
let appElumiBestStreakKey = "elumi.gamification.bestStreak.v1"
let appElumiLastRewardDayIndexKey = "elumi.gamification.lastRewardDayIndex.v1"
let appElumiArcadeHighScoreKey = "elumi.arcade.highscore.v1"
let appArcadeCreditsKey = "elumi.arcade.credits.v1"
let appTrainingSelectedListIDsKey = "training.selectedListIDs.v1"
let appQuizSelectedListIDsKey = "quiz.selectedListIDs.v1"
let appFlashcardsSelectedListIDsKey = "flashcards.selectedListIDs.v1"
let appFlashcardsMasteryThresholdKey = "flashcards.masteryThreshold.v1"

// MARK: - Gameplay Settings
// Zentraler Key für die globale Speed-Round-Dauer — einziger Wahrheits-
// zustand appweit. Alle Module (Training, Verbformen, Akzente, …) lesen
// über `SpeedRoundSettings.currentSeconds` bzw. direkt via @AppStorage.
// Wert ist der Roh-Int aus `SpeedRoundDuration.rawValue` (Sekunden).
// Die Konstante lebt zusätzlich in `SpeedRoundSettings.swift`, damit
// Call-Sites dort auch ohne Import dieses Files klarkommen.

/// Pro-Modul-Key für die zuletzt ausgewählten Trainings-Listen. Jeder TrainingMode
/// merkt sich seine eigene Listenauswahl, damit beim Wechsel zwischen Modulen
/// (z. B. von Vokabeln zu Verben und zurück) die jeweils letzte Auswahl wieder
/// erscheint. `appTrainingSelectedListIDsKey` (v1) ist der Legacy-Fallback für
/// Bestandsnutzer, die noch keine mode-spezifischen Werte haben.
func trainingSelectedListIDsKey(for rawMode: String) -> String {
    "training.selectedListIDs.\(rawMode).v2"
}
