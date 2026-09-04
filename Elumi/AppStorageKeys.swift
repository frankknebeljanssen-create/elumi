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

// MARK: - Ziel-System (2026-08-05)
// Selbstgesetztes Lernziel aus dem Onboarding, persistiert im
// `LearningGoalStore`. Vier Keys statt einem Codable-Blob, weil der
// Wochenfortschritt viel häufiger geschrieben wird als der Plan selbst —
// so muss nicht bei jedem geübten Tag das ganze Ziel neu serialisiert
// werden.
let appLearningGoalPlanKey = "elumi.goal.plan.v1"
let appLearningGoalArchiveKey = "elumi.goal.archive.v1"
let appLearningGoalPracticedDaysKey = "elumi.goal.practicedDays.v1"
let appLearningGoalWeekIndexKey = "elumi.goal.weekIndex.v1"

// **Tagesabschluss (2026-08-06)** — „Fertig für heute". `wrapUpDayKey`
// hält den Tages-Index des letzten Abschlusses (damit derselbe Tag nicht
// zweimal gefeiert wird), `reminderSlotKey` die im Wenn-Dann-Schritt
// gewählte Tageszeit für die morgige Erinnerung.
let appDailyWrapUpDayKey = "elumi.wrapUp.lastDay.v1"
let appDailyWrapUpReminderSlotKey = "elumi.wrapUp.reminderSlot.v1"

let appQuizHeartsKey = "myVoc.quiz.hearts.v1"
let appElumiWaterflohKey = "elumi.gamification.wasserfloh.v1"
let appElumiAlgenkugelKey = "elumi.gamification.algenkugel.v1"
let appElumiXPKey = "elumi.gamification.xp.v1"
let appElumiCurrentStreakKey = "elumi.gamification.currentStreak.v1"
let appElumiBestStreakKey = "elumi.gamification.bestStreak.v1"
let appElumiLastRewardDayIndexKey = "elumi.gamification.lastRewardDayIndex.v1"

/// **Daily Drop completion tracking** (2026-05-06). Datum (`TimeInterval-
/// SinceReferenceDate`) des letzten kompletten Daily-Drop-Durchlaufs.
/// Ein „kompletter Drop" gilt als erreicht, wenn die Slot-Maschine
/// in der `.revealed`-Phase landet — der User hat dann den Spin
/// angestoßen, gewartet, und das Ergebnis gesehen. Vorzeitiges
/// Verlassen (Back-Chevron auf Pre-Screen, App-Schließen vor Reveal)
/// markiert NICHT als komplett.
///
/// Die HomeView prüft `Calendar.current.isDateInToday(...)` gegen
/// den persistierten Wert, um zwischen „NEU HEUTE" und
/// „✓ HEUTE GEMACHT" auf der Daily-Drop-Card-Badge zu wechseln.
/// Tag-Wechsel passiert automatisch über `isDateInToday` —
/// kein dedizierter Reset-Pfad nötig.
///
/// `Double(0.0)` = noch nie gemacht (Default-Wert leer).
let appLastCompletedDailyDropDateKey = "elumi.dailydrop.lastCompletedDate.v1"
let appElumiArcadeHighScoreKey = "elumi.arcade.highscore.v1"
let appArcadeCreditsKey = "elumi.arcade.credits.v1"
// **Pool-Vereinheitlichung 2026-04-30** (Branch
// `feature/training-session-flow`, Stufe 1b): der frühere
// `appElumiPlayCreditsKey` (Test-System 2026-04-24, isolierter Pool
// für Rescue/Skip im Arcade-Spiel) ist entfernt. Slot-Spin füllt
// jetzt direkt `appArcadeCreditsKey` (1×→+1, 2×→+3, 3×→+6 Mapping
// erhalten); Rescue + Skip im Spiel verbrauchen ebenfalls aus diesem
// einen Pool. User-Wahrnehmung: ein einziger „Tickets"-Counter im
// Footer für sowohl Spielstart als auch In-Game-Hilfen. Stale Keys
// auf existierenden Geräten werden bei nächstem App-Open ignoriert.
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

/// **Globale Listen-Auswahl — Toggle** (Stufe 5, 2026-04-29).
/// Master-Switch: wenn `true`, nutzen alle Lern-Module (Karteikarten,
/// Quiz, Training, Word Runner) dieselbe Listen-Auswahl
/// (`appGlobalSelectedListIDsKey`). Wenn `false`, behält jedes Modul
/// seine bisherige Per-Modul-Auswahl. Akzente und Personal-Decks
/// bleiben außerhalb dieses Schalters (eigene Persistenz-Architekturen).
///
/// Default `true` (Spec 5.2). Single-Source-of-Truth-Lookup via
/// `VocabularyListSelectionResolver.currentUseGlobalListSelection()`.
/// Per-Account namespaced (siehe `AccountScopedKeys.userDefaultsKeys`)
/// — jeder Account/Familienmitglied hat eigene Präferenz.
let appUseGlobalListSelectionKey = "elumi.lists.useGlobalSelection.v1"

/// **Globale Listen-Auswahl — UUIDs** (Stufe 5, 2026-04-29).
/// Codable-JSON-Array der UUIDs der gewählten Listen. Wirkt nur,
/// wenn `appUseGlobalListSelectionKey = true`. Initial-Default beim
/// allerersten Toggle-On (oder per Default-Verhalten beim First-Launch
/// auf neuen Accounts) ist die UUID der „A1 Grundwortschatz"-Liste:
/// `F1E1EEE1-A100-4000-A000-000000000001` aus dem
/// `StandardVocabularyLoader.levelLists`-Set.
///
/// User-Listen UND Built-In-Listen sind im selben Pool — Variante (iii)
/// der Spec-Punkt-5.4-Diskussion: visuelle Separation in den Pickern
/// bleibt, der Selection-Pool ist gemeinsam.
///
/// Per-Account namespaced. Single-Source-Lookup via
/// `VocabularyListSelectionResolver.currentGlobalSelectedListIDs()`.
let appGlobalSelectedListIDsKey = "elumi.lists.globalSelection.v1"

/// **Léa-Chat — Lektionswörter-Fokus-Toggle** (Schritt 2B-2A, 2026-05-10).
/// Wenn `true` (Default), liest der `ChatVocabularyProvider` die aktive
/// Listen-Auswahl + Lernjahr-Max und baut den Wortschatz-Block in den
/// Léa-System-Prompt ein. Wenn `false`, läuft der Chat als „freie
/// Konversation" — kein Wortschatz, kein Niveau-Mapping aus Listen,
/// kein Listen-Auswahl-Modal-Zwang. Léa antwortet auf Default-Niveau
/// (A1) ohne explizite VOCAB-/Korrektur-Priorisierung auf Lektionswörter.
/// Single-Source-of-Truth-Lookup über UserDefaults direkt in
/// `ChatVocabularyProvider.currentContext(...)`.
let appLeaFocusOnLessonKey = "elumi.lea.focusOnLesson.v1"

let appQuizSelectedListIDsKey = "quiz.selectedListIDs.v1"
let appFlashcardsSelectedListIDsKey = "flashcards.selectedListIDs.v1"
let appFlashcardsMasteryThresholdKey = "flashcards.masteryThreshold.v1"

/// **Karteikarten Karten-Anzahl-Persistierung** (2026-05-08) — die
/// Slider-Position der „Karten"-Card im Setup. Vor dieser Persistenz
/// war `selectedCardCount` Session-only und ging beim Re-Open verloren
/// (User stellte „50 Karten" ein, kam zurück, sah „alle 200"). Default
/// `0` = „alle Karten" (Standard-Slider-Position).
let appFlashcardsSelectedCardCountKey = "flashcards.selectedCardCount.v1"

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

/// **Deprecated 2026-04-30** — historischer Seen-Marker für den
/// einmaligen Onboarding-Hinweis im Trainings-Generator (UX Stufe 4,
/// 2026-04-29). Mit der Spec-Änderung „Setup-Modal erscheint bei jedem
/// Tab-Open" wird der Wert nicht mehr gelesen oder geschrieben. Der
/// Key bleibt aus zwei Gründen erhalten:
///   • Backward-Compat: existierende User haben den Eintrag in
///     UserDefaults — kein Migration-Pfad nötig, der Eintrag liegt
///     einfach verwaist herum (analog zum `appIconSet`-Key aus
///     Stufe 6).
///   • `AccountScopedKeys.userDefaultsKeys`-Registrierung bleibt
///     erhalten, damit beim Account-Wechsel keine Stale-Pointer in
///     den Cleanup-Pfaden auftauchen.
///
/// Bei nächstem ohnehin notwendigen Migration-Pfad (Schema-Bump im
/// AccountStore o. ä.) den Key in der Migrations-Liste mit-aufräumen.
let appTrainingGeneratorOnboardingSeenKey = "elumi.training.generator.onboarding.seen.v1"

/// **Trainings-Generator Default-Trainingsdauer** (Sache B, 2026-04-29) —
/// persistierte User-Wahl der Trainingsdauer in Minuten (10/15/20).
/// Default-Wert wird zentral in `ElumiTabView.durationDefault` (= 10)
/// definiert und vom `@AppStorage`-Init referenziert. Ab Stufe 2 wird
/// der Wert beim Modal-Close idempotent geschrieben (Backdrop-Tap und
/// CTA übernehmen den aktuellen Preselect — kein „undefined state").
///
/// Per-Account namespaced via `AccountStore.namespacedKey(...)` —
/// gehört in `AccountScopedKeys.userDefaultsKeys`. Begründung:
/// Familien-Account und Owner-Account dürfen unterschiedliche
/// Default-Trainingsdauern haben.
let appTrainingGeneratorDurationKey = "elumi.training.generator.duration.v1"

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

// MARK: - AnswerMode Persistence (Sweep C, 2026-05-07)
//
// Per-Modul-Persistierung des Sprechen/Tippen-Toggle in den Setup-
// Screens der Speech-fähigen Module. Werte sind die `AnswerMode.rawValue`
// Strings ("speech" / "tap"). Default ist immer `.speech` (Frank's Spec
// für alle drei Module).
//
// Slot-launched Sessions (Mix-Training / Daily Drop) lesen denselben
// Key am Controller-Init — kein zusätzliches Launch-Context-Routing
// nötig.

/// AnswerMode-Setting für **Karteikarten**. Default `.speech`.
let appAnswerModeKarteikartenKey = "elumi.answerMode.karteikarten.v1"

/// AnswerMode-Setting für **Vokabeln**. Default `.speech`.
let appAnswerModeVokabelnKey = "elumi.answerMode.vokabeln.v1"

/// AnswerMode-Setting für **Nomen**. Default `.speech`. Ersetzt den
/// nicht-persistierten `nounAnswerMode` aus dem
/// `TrainingSessionController` (vorher Session-only).
let appAnswerModeNomenKey = "elumi.answerMode.nomen.v1"
