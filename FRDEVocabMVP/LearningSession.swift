import Foundation

/// Modulübergreifende Beschreibung einer abgeschlossenen Lernsession.
/// Wird von jedem Modul am Session-Ende konstruiert und an `ProgressService`
/// übergeben — der Service kümmert sich um XP-Vergabe, Credits, Streak.
///
/// Bewusst ein einfaches Wert-Objekt (struct), nicht modul-spezifische
/// Subklassen — damit das Auswerten in `ProgressService` einheitlich bleibt
/// und der Service nicht jedes Modul kennen muss.
struct LearningSession: Equatable {

    /// Welches Modul die Session erzeugt hat. Beeinflusst, wie der Service
    /// die Session-Schwelle anwendet und welcher Subtitle in der Summary
    /// angezeigt wird.
    enum Origin: String, Codable, Equatable {
        case flashcards
        case quiz
        case training        // Vokabel/Nomen/Artikel/Verben (normales Training)
        case speedRound      // Speed-Round-Variante eines Trainings
        case verbforms

        var displayName: String {
            switch self {
            case .flashcards:  return "Karteikarten"
            case .quiz:        return "Quiz"
            case .training:    return "Training"
            case .speedRound:  return "Speed Round"
            case .verbforms:   return "Verbformen"
            }
        }
    }

    let origin: Origin

    /// Anzahl korrekt beantworteter Einheiten in dieser Session.
    let correctCount: Int

    /// Anzahl falscher Antworten (für „fehlerfrei"-Bonus + Statistik).
    let wrongCount: Int

    /// Längste Combo (richtig in Folge) innerhalb der Session — falls vom
    /// Modul getrackt. Optional, weil nicht jedes Modul Combos zählen kann.
    let longestCombo: Int

    /// Karteikarten-spezifisch: Wie viele Karten wurden in dieser Session
    /// endgültig gemeistert (= aus dem Stapel gefallen). 0 bei anderen Modulen.
    let masteredCardCount: Int

    init(
        origin: Origin,
        correctCount: Int,
        wrongCount: Int = 0,
        longestCombo: Int = 0,
        masteredCardCount: Int = 0
    ) {
        self.origin = origin
        self.correctCount = correctCount
        self.wrongCount = wrongCount
        self.longestCombo = longestCombo
        self.masteredCardCount = masteredCardCount
    }

    // MARK: - Abgeleitete Eigenschaften

    /// Erfüllt die Session die modul-spezifische Mindestschwelle?
    /// → relevant für Streak-Counter und „Daily Completion Bonus".
    var meetsMinimumThreshold: Bool {
        let attempts = correctCount + wrongCount
        switch origin {
        case .flashcards: return attempts >= GamificationConfig.SessionMinimum.flashcardsAttempts
        case .quiz:       return attempts >= GamificationConfig.SessionMinimum.quizQuestions
        case .training:   return attempts >= GamificationConfig.SessionMinimum.trainingAnswers
        case .speedRound: return attempts >= GamificationConfig.SessionMinimum.speedRoundAnswers
        case .verbforms:  return attempts >= GamificationConfig.SessionMinimum.verbformsRounds
        }
    }

    /// Wurde komplett ohne Fehler abgeschlossen? Voraussetzung für den
    /// Flawless-Bonus. Mindestens eine korrekte Antwort wird verlangt,
    /// damit eine 0/0-Session nicht trivial belohnt wird.
    var isFlawless: Bool {
        wrongCount == 0 && correctCount > 0
    }
}
