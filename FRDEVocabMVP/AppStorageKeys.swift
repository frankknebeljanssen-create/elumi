// Shared app storage keys extracted from ContentView.swift

// MARK: - Profile
// Nutzerprofil lebt im ProfileStore (JSON-Codable in UserDefaults).
// `appFirstNameKey` bleibt als Legacy-Mirror bestehen, damit ältere
// @AppStorage-Reader während der Migrationsphase kompatibel bleiben.
let appFirstNameKey = "myVoc.account.firstName.v1"
let appLearnerProfileKey = "elumi.profile.learner.v1"
let appOnboardingCompletedKey = "elumi.profile.onboarding.completed.v1"

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

/// Pro-Modul-Key für die zuletzt ausgewählten Trainings-Listen. Jeder TrainingMode
/// merkt sich seine eigene Listenauswahl, damit beim Wechsel zwischen Modulen
/// (z. B. von Vokabeln zu Verben und zurück) die jeweils letzte Auswahl wieder
/// erscheint. `appTrainingSelectedListIDsKey` (v1) ist der Legacy-Fallback für
/// Bestandsnutzer, die noch keine mode-spezifischen Werte haben.
func trainingSelectedListIDsKey(for rawMode: String) -> String {
    "training.selectedListIDs.\(rawMode).v2"
}
