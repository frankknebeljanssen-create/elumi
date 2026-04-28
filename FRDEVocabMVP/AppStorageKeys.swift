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
/// **Elumi-Play-Credits** (2026-04-24 Test-System) — isolierter
/// Credit-Pool NUR für das Elumi-Arcade-Spiel. Wird durch die Slot
/// Machine im Trainingsgenerator gefüllt (1/3/6 pro Elumi-Treffer),
/// im Spiel verbraucht für Hilfen (Rescue, Skip). Bewusst getrennt
/// vom `appArcadeCreditsKey` (GameHub-„1 Credit = 1 Spiel starten").
/// Word Runner greift **nicht** darauf zu.
let appElumiPlayCreditsKey = "elumi.play.credits.v1"
/// **Word Runner** — persistierte Lifetime-Stats für den Start-Screen:
/// Best-Score (höchste Runden-Punkte je erreicht) + Trophies (Summe
/// aller je eingesammelten Collectibles). Werden nach jedem Run
/// aktualisiert und im Start-Screen als Stats-Card angezeigt.
let appWordRunnerBestScoreKey = "elumi.wordrunner.bestScore.v1"
let appWordRunnerTotalTrophiesKey = "elumi.wordrunner.totalTrophies.v1"
/// **Zuletzt in WR gewählte Liste** (UUID als String). Wird beim
/// Listen-Wechsel im WR-Start-Screen gespeichert und beim nächsten
/// Aufruf der Ansicht wiederhergestellt — sodass der Spieler nicht
/// jedes Mal neu auswählen muss, auch wenn andere Module (Quiz,
/// Training, Flashcards) zwischendurch die globale Listen-ID
/// verändert haben.
let appWordRunnerLastListIDKey = "elumi.wordrunner.lastListID.v1"
let appTrainingSelectedListIDsKey = "training.selectedListIDs.v1"
/// **Cumulative Lernjahr-Auswahl** (Stufe 1, ausgerollt 2026-04-28).
/// Der gewählte „Max-Year" für hierarchische Listen mit
/// `cumulativeChildren=true` (V1: nur „Grundwortschatz A1"). Werte:
///   • nil → Parent voll gewählt = alle Lernjahre
///   • 1...5 → kumulativ Y_1 bis Y_n
///
/// Globaler Scope (kein .training-Prefix). Wirkt in allen Lern-Modulen:
/// Word Runner, Training (Vokabeln/Verben/Nomen/Articles/Verbformen),
/// Akzente, Flashcards (Standard + Personal-Deck-Snapshot), Quiz.
/// Single-Source-of-Truth-Lookup via
/// `VocabularyListSelectionResolver.currentLernjahrMax()`.
let appLernjahrMaxKey = "elumi.lernjahrMax.v1"
let appQuizSelectedListIDsKey = "quiz.selectedListIDs.v1"
let appFlashcardsSelectedListIDsKey = "flashcards.selectedListIDs.v1"
let appFlashcardsMasteryThresholdKey = "flashcards.masteryThreshold.v1"

// **Persönlicher Trainingsmodus** (Phase 8): bis zu zwei persistierte
// User-Stapel. JSON-Array von `PersonalDeck` (Codable), verwaltet von
// `PersonalDeckStore.shared`. Die Sessions-Logik lebt weiter im normalen
// FlashcardSessionStore — dieser Key speichert nur die Stapel-Definitionen
// (Listenquellen, einmalig gemischte Reihenfolge, Fortschritts-Cursor,
// gemeisterte Karten).
let appPersonalDecksKey = "elumi.flashcards.personalDecks.v1"

// **Voice-System** (Phase 9): User-Wahl der Apple-Stimmen pro Sprache.
// NUR die Auswahl wird hier gespeichert — die Sprach-Dateien selbst
// leben systemweit auf dem iPhone und werden in den iPhone-Einstellungen
// unter „Bedienungshilfen → Gesprochene Inhalte" verwaltet.
let appVoiceGermanSelectionKey = "elumi.voice.de.selection"
let appVoiceFrenchSelectionKey = "elumi.voice.fr.selection"

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
