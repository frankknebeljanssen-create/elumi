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
        case accents         // Akzent-Modul (é, è, ê, ç)
        case wordRunner      // Word Runner (Runner-Spiel mit Artikel/Verbform-Aufgaben)
        // **Schritt 3A (2026-05-10)** — Léa-Chat-Session zählt fürs
        // Tagesziel/Streak. XP wird separat über `ProgressStore.mutate`
        // vergeben (fixe +15), damit die `correctCount × 10`-Math
        // nicht greift — die Chat-Session hat keine korrekt/falsch-
        // Zählung im klassischen Sinne.
        case leaChat

        var displayName: String {
            switch self {
            case .flashcards:  return "Karteikarten"
            case .quiz:        return "Quiz"
            case .training:    return "Training"
            case .speedRound:  return "Speed Round"
            case .verbforms:   return "Verbformen"
            case .accents:     return "Akzente"
            case .wordRunner:  return "Word Runner"
            case .leaChat:     return "Chat mit Léa"
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
        // Akzente teilt die Schwelle mit Quiz (8 Aufgaben): beide sind
        // kurze Ja/Nein-Entscheidungs-Sessions mit ähnlicher Länge.
        case .accents:    return attempts >= GamificationConfig.SessionMinimum.quizQuestions
        // Word Runner ist „kurz aber intensiv" — eine Runde kann nach
        // 3-4 Entscheidungen durch einen Blocker enden. Wir nehmen
        // deshalb die Speed-Round-Schwelle (3), damit ein Quick-Run
        // trotzdem für die Streak zählt.
        case .wordRunner: return attempts >= GamificationConfig.SessionMinimum.speedRoundAnswers
        // **Schritt 3A (γ-Spec)** — Léa-Chat-Session erfüllt
        // Tagesziel, wenn die Summary-Threshold-Logik erfüllt ist:
        //   • ≥5 User-Messages, ODER
        //   • ≥1 User-Message UND Session-Dauer ≥300 s.
        // Da `LearningSession` keine Duration kennt, kodiert
        // `ChatService.recordSessionEnd(messages:duration:)` die
        // Bedingung in `correctCount`: bei 5+ Messages = echte
        // Anzahl, bei 1+Msg + 5min = inflated auf 5. Damit ist die
        // hier formulierte Schwelle exakt das, was Frank spec'd —
        // beide Pfade passen `correctCount >= 5`.
        case .leaChat:    return correctCount >= 5
        }
    }

    /// Wurde komplett ohne Fehler abgeschlossen? Voraussetzung für den
    /// Flawless-Bonus. Mindestens eine korrekte Antwort wird verlangt,
    /// damit eine 0/0-Session nicht trivial belohnt wird.
    var isFlawless: Bool {
        wrongCount == 0 && correctCount > 0
    }

    // MARK: - Summary-Text

    /// Modul-spezifische Ergebnis-Überschrift für die `SessionSummaryView`.
    /// Wird dort als Fallback genutzt, wenn die Call-Site keine eigene
    /// Headline übergibt — dadurch braucht kein Modul Boilerplate, um
    /// die Summary Spec-konform zu füllen.
    ///
    ///   • Flashcards → „N Karten gemeistert" (falls Karten gemeistert
    ///     wurden — der treibende Wert im Karteikarten-System)
    ///     sonst „X von Y richtig"
    ///   • SpeedRound → „N Treffer in Ns" (Zeit ist hier das Besondere —
    ///     die Sekundenzahl kommt dynamisch aus `SpeedRoundSettings`,
    ///     damit die Headline zur global konfigurierten Dauer passt)
    ///   • Quiz/Training/Verbformen → „X von Y richtig"
    ///   • Fallback bei 0 Versuchen → „Dein Ergebnis" (analog zum
    ///     bisherigen Default der Summary-View)
    var resultHeadline: String {
        let total = correctCount + wrongCount
        switch origin {
        case .flashcards:
            if masteredCardCount > 0 {
                return masteredCardCount == 1
                    ? "1 Karte gemeistert"
                    : "\(masteredCardCount) Karten gemeistert"
            }
            // **2026-08-06, Bug-Fix** — vorher „Session geschafft", auch
            // wenn keine einzige Aufgabe beantwortet wurde (User-Report:
            // Übung ohne Antwort beendet, Screen sagte trotzdem
            // „Session geschafft" — "das ist ja falsch"). Geschafft ist
            // nur, was auch gemacht wurde.
            if total == 0 { return "Dein Ergebnis" }
            return "\(correctCount) von \(total) richtig"
        case .speedRound:
            // Dynamische Sekundenzahl aus der globalen Settings-Einstellung.
            // Wird hier zur Headline-Bildzeit gelesen — Speed-Round-Ergebnis
            // wird unmittelbar nach dem Timer-Ablauf konstruiert, die
            // aktuelle Einstellung entspricht daher der gerade eben
            // abgelaufenen Dauer.
            let seconds = SpeedRoundSettings.currentSeconds
            return correctCount == 1
                ? "1 Treffer in \(seconds)s"
                : "\(correctCount) Treffer in \(seconds)s"
        case .quiz, .training, .verbforms, .accents:
            // **2026-08-06, Bug-Fix** — vorher „Session geschafft", auch
            // wenn keine einzige Aufgabe beantwortet wurde (User-Report:
            // Übung ohne Antwort beendet, Screen sagte trotzdem
            // „Session geschafft" — "das ist ja falsch"). Geschafft ist
            // nur, was auch gemacht wurde.
            if total == 0 { return "Dein Ergebnis" }
            return "\(correctCount) von \(total) richtig"
        case .wordRunner:
            // Word-Runner-Headline: „richtige Antworten" ist für den
            // User griffiger als „X von Y", weil die Gesamtzahl stark
            // vom Crash-Zeitpunkt abhängt — hier zählt die Trefferzahl.
            if correctCount == 0 {
                return total == 0 ? "Run beendet" : "Run beendet"
            }
            return correctCount == 1
                ? "1 richtige Antwort"
                : "\(correctCount) richtige Antworten"
        case .leaChat:
            // **Schritt 3A** — Léa-Chat-Sessions zählen Messages
            // nicht „richtig/falsch". Headline-Wert hier ist nur
            // für DailyChallengeStore-Logging gedacht; das eigentliche
            // Summary-Sheet rendert seine eigenen Sektionen
            // (`ChatSessionSummarySheet`).
            return correctCount == 1
                ? "1 Nachricht mit Léa"
                : "\(correctCount) Nachrichten mit Léa"
        }
    }

    /// Kurzbewertung (Sehr stark / Stark / Gut gemacht). Bewusst **nicht**
    /// linear auf jede Trefferquote mapped:
    ///   • nil bei `isFlawless` → das „Fehlerfrei!"-Badge in der Summary
    ///     ist die speziellere und emotional stärkere Belohnung
    ///   • nil bei <3 Versuchen → zu wenig Datenbasis, Bewertung wirkt
    ///     willkürlich
    ///   • nil bei <50% Treffer → kein „Verbesserungsbedarf"-Schimpfen,
    ///     die Summary ist ein Belohnungsmoment, kein Zeugnis
    var accuracyRating: String? {
        let total = correctCount + wrongCount
        guard total >= 3, !isFlawless else { return nil }
        let ratio = Double(correctCount) / Double(total)
        switch ratio {
        case 0.9...:  return "Sehr stark"
        case 0.75...: return "Stark"
        case 0.5...:  return "Gut gemacht"
        default:      return nil
        }
    }
}
