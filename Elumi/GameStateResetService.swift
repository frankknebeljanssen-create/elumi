import Foundation

/// Produktiver Reset-Service — in Release + Debug verfügbar. Zwei klar
/// getrennte Aktionen:
///   • `resetGameState()` — Spielstand (XP, Streak, Credits, Sammelwerte,
///     Tages-Challenge, Session-Resume-Snapshots). Profil und Custom-
///     Listen bleiben **unberührt**. Empfohlen als Default-Reset für
///     den Standard-User, der „von vorne anfangen" will, ohne Inhalte
///     zu verlieren.
///   • `resetCustomLists()` — zusätzlich **die vom Nutzer angelegten
///     Listen** entfernen. Destruktiver; ein separater Alert im UI
///     schützt davor, dass beides versehentlich auf einen Tap passiert.
///
/// Die ältere Debug-only-Variante (`DebugResetService`) ist eine dünne
/// Fassade über diesen Service — dadurch greifen alle Ergänzungen hier
/// automatisch auch im DEBUG-Button, ohne Doppel-Pflege.
@MainActor
enum GameStateResetService {

    /// Setzt den gesamten **Spielstand** auf den Ausgangszustand zurück —
    /// exakt wie bei einem frischen Install. Profil, Custom-Listen und
    /// Lexikon-Cache bleiben erhalten.
    ///
    /// Nach dem Aufruf:
    /// - Alle `@Published`-Stores (Progress, DailyStats, DailyChallenge)
    ///   haben neue Werte → reaktive Views rendern automatisch.
    /// - Standalone-`@AppStorage`-Keys (Herzchen, Wasserfloh, Algenkugel,
    ///   Highscore) werden geleert → Reader reagieren via UserDefaults-
    ///   Notifications.
    /// - Alle Session-Resume-Snapshots (Training, Akzente, Quiz) sind
    ///   weg — kein „scheinbar laufendes Training" nach dem Reset.
    static func resetGameState() {
        // 1) ProgressStore — komplette UserProgress-Struktur auf Default.
        //    Default gibt u. a. 3 Credits als Fresh-Install-Start.
        ProgressStore.shared.mutate { progress in
            progress = UserProgress()
        }

        // 2) DailyStats + DailyChallenge explizit zurücksetzen, damit die
        //    In-Memory-`@Published`-Werte reagieren. UserDefaults-Wipe
        //    allein reicht hier nicht — Stores laden beim Init einmalig
        //    und halten danach selbst.
        DailyStatsStore.shared.reset()
        DailyChallengeStore.shared.reset()

        // **Ziel-System (2026-08-08)** — der Tagesziel-Fortschritt lebt
        // jetzt in `UserProgress.todayCorrectCount` (siehe `ProgressStore`
        // oben) und ist damit schon zurückgesetzt. Das gesetzte Ziel
        // selbst bleibt stehen — Begründung analog zu Profil und Vorname
        // weiter unten: der Plan ist ein Nutzerdatum, kein Spielstand.
        // Ein „Spielstand zurücksetzen" soll den Nutzer nicht zurück ins
        // Onboarding zwingen. Streak-Joker sind ebenfalls Spielstand.
        StreakJokerStore.shared.reset()

        // 3) Standalone-@AppStorage-Keys direkt leeren.
        let defaults = UserDefaults.standard
        defaults.set(0, forKey: appQuizHeartsKey)
        defaults.set(0, forKey: appElumiWaterflohKey)
        defaults.set(0, forKey: appElumiAlgenkugelKey)
        defaults.set(0, forKey: appElumiArcadeHighScoreKey)

        // 4) Session-Resume-Snapshots verwerfen. Ein Reset will alles
        //    zurücksetzen — ein weiterhin liegender Snapshot würde beim
        //    nächsten Modul-Start in eine „fortgesetzte" Session
        //    zurückführen und damit den Reset teilweise unterlaufen.
        TrainingSessionResumeStore.clear()
        AccentSessionResumeStore.clear()
        QuizSessionResumeStore.clear()
    }

    /// Entfernt **zusätzlich** alle vom Nutzer angelegten Listen.
    ///
    /// **Codeaudit 2026-09-03, Stufe 3 (Punkt 19)** — delegiert jetzt an
    /// `VocabularyListStore.resetToDefaults()`. Vorher löschte diese
    /// Methode hartkodiert `vocabulary-lists-v2.json` und griff damit
    /// ins Leere: sobald ein Account aktiv ist, heißt die Datei
    /// `vocabulary-lists-v2-<uuid>.json`, und die Listen standen
    /// zusätzlich im `.lastKnownGood.json`-Backup und im
    /// UserDefaults-Spiegel. Der Nutzer bestätigte das Löschen, startete
    /// wie im Alert empfohlen neu — und alle Listen waren wieder da.
    ///
    /// Diese Aktion ist **destruktiver** als `resetGameState()` und
    /// sollte in der UI einen **zweiten, eigenen Alert** haben — nicht
    /// in denselben Reset-Button wie oben packen.
    static func resetCustomLists(in listStore: VocabularyListStore) {
        // Der Store besitzt seine Persistenz — er räumt alle drei
        // Ebenen (Datei, Last-Known-Good-Backup, UserDefaults-Spiegel)
        // ab und lädt danach den Ausgangszustand mit den Startlisten.
        listStore.resetToDefaults()

        // Relevante UserDefaults-Keys leeren — damit beim nächsten Start
        // nicht eine alte „ausgewählte Liste" ins Leere zeigt.
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: appTrainingSelectedListIDsKey)
        defaults.removeObject(forKey: appQuizSelectedListIDsKey)
        defaults.removeObject(forKey: appFlashcardsSelectedListIDsKey)

        // Session-Resume-Snapshots kippen mit — sie enthalten Item-
        // Snapshots aus den gelöschten Listen, die jetzt obsolet sind.
        TrainingSessionResumeStore.clear()
        AccentSessionResumeStore.clear()
        QuizSessionResumeStore.clear()

        // Der Live-Refresh passiert jetzt im Store selbst
        // (`resetToDefaults` lädt direkt neu) — ein App-Neustart ist
        // nicht mehr nötig, damit der Effekt sichtbar wird.
    }
}
