import Foundation

/// Zentrale, wiederverwendbare Streak-/Combo-Logik für alle Lernmodule.
///
/// Regeln (Single Source of Truth — verhindert Drift zwischen den Modulen
/// Training, Karteikarten, Quiz, Verbformen und künftigen Modi):
/// • Eine **richtige** Antwort **auf den ersten Versuch** verlängert die Serie
///   um +1 und triggert den Combo-Toast, wenn die Serie ein Vielfaches der
///   XP-Schwelle (`GamificationConfig.xpComboThreshold`) erreicht.
/// • Eine **falsche** Antwort setzt die Serie **sofort** auf 0 zurück.
/// • Eine richtige Antwort nach mindestens einem Fehlversuch auf derselben
///   Karte wird wie eine **falsche** Antwort behandelt — die Serie bricht
///   also auch bei „später doch noch richtig" ab. Das entspricht der
///   Nutzererwartung „5x in **ununterbrochener** Folge", bei der eine
///   Karte, die erst nach mehreren Versuchen sitzt, nicht als sauberer
///   Streak-Treffer zählt.
///
/// Nutzung: alle Controller ersetzen ihre eigenen `sessionCurrentCombo`/
/// `sessionLongestCombo`-Zähler durch eine `SessionStreak`-Instanz und
/// rufen `recordAnswer(correct:firstAttempt:)` aus ihrer Antwort-Pipeline.
/// So bleiben die drei wichtigen Zahlen (current, longest, Toast-Trigger)
/// automatisch synchron, und der Toast kann nicht mehr versehentlich an
/// kumulative Treffer gekoppelt werden.
///
/// `Codable` damit Session-Resume-Snapshots (Training, Akzente, …) den
/// Streak-Stand mitschreiben können. Älterer Snapshot ohne Streak-Feld
/// → Init-Werte (`current = longest = 0`); Session fängt sauber an.
struct SessionStreak: Codable, Equatable {
    /// Laufende Serie richtiger Erstversuch-Antworten. Wird bei jeder
    /// falschen Antwort **oder** einer „erst nach Retry"-richtigen Antwort
    /// auf 0 zurückgesetzt.
    private(set) var current: Int = 0

    /// Höchster Serienwert, der während der aktuellen Session erreicht
    /// wurde. Wird für die Reward-Berechnung (`LearningSession.longestCombo`)
    /// verwendet und bleibt bei Reset der laufenden Serie erhalten.
    private(set) var longest: Int = 0

    /// Initializer für frische Sessions — Default-Werte.
    init() {}

    /// Explizit für Snapshot-Wiederherstellung. Private Setter verhindern,
    /// dass Call-Sites `current/longest` manuell beschreiben; dieser
    /// Restoration-Init bleibt der einzige Weg, einen gespeicherten
    /// Zustand zurückzuladen.
    init(restoringCurrent: Int, longest: Int) {
        self.current = max(0, restoringCurrent)
        self.longest = max(self.current, max(0, longest))
    }

    /// Setzt beide Werte auf 0 — für Session-Start und harten Reset.
    mutating func reset() {
        current = 0
        longest = 0
    }

    /// Zentrale Antwort-Registrierung. Der Parameter `firstAttempt`
    /// unterscheidet zwischen
    /// • `true` (Default) — Antwort kam direkt beim ersten Versuch,
    /// • `false` — Antwort kam erst nach mindestens einer falschen
    ///   Eingabe auf derselben Karte.
    ///
    /// Nur die Kombination `correct == true && firstAttempt == true`
    /// verlängert die Serie; alles andere setzt sie auf 0 zurück.
    ///
    /// Der Parameter `feedbackPlayer` erlaubt dem Streak, den Engine
    /// mit Sound zu füttern — ohne ihn spielt der Engine keine Sounds.
    /// Controller reichen ihren eigenen `FeedbackPlayer` durch; in
    /// Kontexten ohne Player (z. B. Tests) kann `nil` übergeben werden.
    @MainActor
    mutating func recordAnswer(
        correct: Bool,
        firstAttempt: Bool = true,
        feedbackPlayer: FeedbackPlayer? = nil
    ) {
        if correct && firstAttempt {
            current += 1
            longest = max(longest, current)
            // Der `FeedbackEngine` entscheidet zentral, welches UI-
            // Feedback (Pulse / Small / Medium / Large) gefeuert wird —
            // und hält Cooldowns ein. Der Streak selbst kennt keine
            // Tier-Logik mehr; er reicht nur die neue laufende Serie
            // an den Engine weiter.
            FeedbackEngine.shared.record(
                .correctAnswer(currentStreak: current),
                feedbackPlayer: feedbackPlayer
            )
        } else {
            current = 0
            // Falsche (oder Retry-korrekte) Antwort — Engine spielt
            // weiches Feedback, kein hartes „wrong". Der `correct`-Flag
            // landet im Engine via `.wrongAnswer` nur, wenn wirklich
            // inkorrekt (Retry-Corrects bekommen kein Error-Signal,
            // damit der User nicht doppelt bestraft wird: 1. der Reset,
            // 2. der Sound).
            if !correct {
                FeedbackEngine.shared.record(.wrongAnswer, feedbackPlayer: feedbackPlayer)
            }
        }
    }

    /// Convenience-Alias für das häufige Muster
    /// „Antwort war definitiv ein Erstversuch" (z. B. Karteikarten, wo es
    /// pro Karte nur einen Antwort-Tap gibt).
    @MainActor
    mutating func recordCorrect(feedbackPlayer: FeedbackPlayer? = nil) {
        recordAnswer(correct: true, firstAttempt: true, feedbackPlayer: feedbackPlayer)
    }

    /// Convenience-Alias für „Antwort war falsch" (unabhängig von
    /// Versuchsnummer — jede Fehleingabe resetet die Serie).
    @MainActor
    mutating func recordWrong(feedbackPlayer: FeedbackPlayer? = nil) {
        current = 0
        FeedbackEngine.shared.record(.wrongAnswer, feedbackPlayer: feedbackPlayer)
    }
}
