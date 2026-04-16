import Foundation

/// Zentrale Konfiguration für das Gamification-System (XP, Level, Streaks,
/// Credits). Single Source of Truth — alle Module konsumieren diese Werte
/// über `ProgressService` / `ProgressStore`. Balancing-Anpassungen passieren
/// hier, nicht verteilt in den Modul-Views.
///
/// Designprinzipien (siehe Auftrag):
/// • Modulübergreifend faires Belohnungssystem — keine Schieflage zwischen
///   Karteikarten / Quiz / Speed Round / Training.
/// • Werte sind bewusst einfach gehalten, leicht später feinjustierbar.
/// • Keine versteckten Multiplikatoren — alles hier sichtbar.
enum GamificationConfig {

    // MARK: - XP
    //
    // Phase-6-Tuning: XP-Werte leicht nachgezogen, damit Sessions sich
    // wertiger anfühlen — gleichzeitig bleibt die Basis bei 10 XP pro
    // richtiger Antwort, damit kein Modul plötzlich viel besser ist.

    /// Basis-XP pro richtig beantworteter Lerneinheit. Gilt für alle Module
    /// gleich — Karteikarte richtig, Quizfrage richtig, Verbform richtig usw.
    static let xpPerCorrectAnswer = 10

    /// Combo-Bonus alle N richtigen Antworten in Folge (innerhalb einer Session).
    /// Phase-6: Bonus von 20 → 25 leicht angehoben, damit Combos emotional
    /// stärker belohnt werden, ohne Farming zu provozieren (Schwelle bleibt 5).
    static let xpComboThreshold = 5
    static let xpComboBonus = 25

    /// Pauschal-Bonus für eine fehlerfrei abgeschlossene Session.
    /// Phase-6: 50 → 75 — „Fehlerfrei" soll sich spürbar lohnen.
    static let xpFlawlessSessionBonus = 75

    /// Bonus pro Karte, die in Karteikarten endgültig gemeistert wurde
    /// (also `consecutiveCorrect ≥ masteryThreshold` erreicht hat). Belohnt
    /// gründliches Lernen — gleicht Karteikarten gegen schnellere Modi aus.
    /// Phase-6: 15 → 20 (Mastery ist aufwändig, soll spürbar lohnen).
    static let xpMasteredCardBonus = 20

    /// Tagesabschluss-Bonus — **nicht mehr direkt genutzt** seit Phase 5.
    /// Wird jetzt vom `DailyChallengeStore` als Challenge-Reward vergeben
    /// (pro Typ individuell, 40–60 XP). Der Konstantenwert bleibt stehen,
    /// falls noch irgendwo referenziert — der echte Wert kommt aus der
    /// `DailyChallenge.reward.xp`-Struktur.
    static let xpDailyCompletionBonus = 50

    // MARK: - Level Curve (progressive, Phase 6)
    //
    // Bewusst *nicht* linear: frühe Level geben ein schnelles
    // Erfolgsmoment, spätere Level belohnen echtes Dranbleiben. Die
    // konkrete Kurve steht zentral **genau hier** — wer rebalancen will,
    // ändert nichts außer diese Funktion.
    //
    // Kumulierte XP zum Erreichen von Level L:
    //   L1: 0       (Start)
    //   L2: 100
    //   L3: 250
    //   L4: 470
    //   L5: 770
    //   L6: 1150
    //   L7: 1620
    //   L8: 2180
    //   Lx (x≥5): L5-Stand + Summe(300 + 80·(i−4)) für i=5…x−1
    //
    // Das fühlt sich früh motivierend an (erstes Level-Up nach wenigen
    // Minuten, 10 richtige Quizantworten), später bleibt das Level-Up
    // ein Moment ohne Frust. Die Werte sind bewusst „rund" — leicht
    // merkbar und einfach in der Kopfrechnung.

    /// XP, um vom aktuellen Level ins nächste zu kommen. Einziger Ort
    /// zum Rebalancen der Kurve.
    static func xpRequiredForNextLevel(afterLevel currentLevel: Int) -> Int {
        switch currentLevel {
        case ..<1: return 0
        case 1: return 100
        case 2: return 150
        case 3: return 220
        case 4: return 300
        default:
            // Ab Level 5 linearer Zuwachs von 80 XP pro Level → grind
            // bleibt moderat, ohne dass Level irrelevant werden.
            return 300 + (currentLevel - 4) * 80
        }
    }

    /// Kumulierte XP, die nötig sind, um in Level `L` zu sein.
    /// Level 1 beginnt per Definition bei 0 XP.
    static func cumulativeXPRequired(forLevel level: Int) -> Int {
        guard level > 1 else { return 0 }
        var sum = 0
        for lvl in 1..<level {
            sum += xpRequiredForNextLevel(afterLevel: lvl)
        }
        return sum
    }

    /// Berechnet das aktuelle Level aus der Gesamt-XP-Summe.
    /// Safety-Cap bei Level 100 schützt vor Endlos-Loops, falls totalXP
    /// extreme Werte annimmt — liegt weit jenseits jeder normalen Nutzung.
    static func level(forXP totalXP: Int) -> Int {
        var lvl = 1
        while lvl < 100, cumulativeXPRequired(forLevel: lvl + 1) <= totalXP {
            lvl += 1
        }
        return lvl
    }

    /// XP-Stand am Anfang des aktuellen Levels (für Progress-Bar-Berechnung).
    static func levelStartXP(for level: Int) -> Int {
        cumulativeXPRequired(forLevel: level)
    }

    /// XP-Stand am Anfang des nächsten Levels.
    static func levelEndXP(for level: Int) -> Int {
        cumulativeXPRequired(forLevel: level + 1)
    }

    /// Anteil 0…1 vom aktuellen XP-Stand bis zum nächsten Level.
    static func progressTowardNextLevel(totalXP: Int) -> Double {
        let lvl = level(forXP: totalXP)
        let start = levelStartXP(for: lvl)
        let end = levelEndXP(for: lvl)
        let span = max(1, end - start)
        let into = max(0, totalXP - start)
        return min(1.0, Double(into) / Double(span))
    }

    /// Credits-Belohnung pro Level-Up.
    static let creditsPerLevelUp = 5

    // MARK: - Credits

    /// XP → Credits Konvertierung: alle N XP gibt es 1 Bonus-Credit.
    /// Macht Lernen zur primären Credit-Quelle (das Spiel verbraucht nur).
    static let xpPerBonusCredit = 100

    /// Credits-Bonus bei Streak-Meilensteinen.
    /// Key = erreichter Streak-Tag, Value = Credits-Bonus (einmalig).
    static let creditsForStreakMilestones: [Int: Int] = [
        3:  2,
        7:  5,
        14: 10,
        30: 25
    ]

    // MARK: - Session-Schwellen (modulübergreifend)

    /// Mindest-Anzahl bearbeiteter Einheiten, damit eine Session als
    /// „abgeschlossen" zählt (Streak-relevant, Bonus-relevant).
    /// Verhindert Trivial-Farming („1 Karte → Streak").
    enum SessionMinimum {
        static let flashcardsAttempts = 5     // Karten bearbeitet
        static let trainingAnswers = 5        // Antworten gegeben
        static let speedRoundAnswers = 3      // Antworten in der Speed-Round
        static let quizQuestions = 5          // Fragen beantwortet (Quiz beendet)
        static let verbformsRounds = 1        // Mind. eine Runde abgeschlossen
    }

    // MARK: - Streak

    /// Streak-Multiplikator je nach erreichten Streak-Tagen. Nicht für XP
    /// genutzt (XP bleibt fair pro Antwort), sondern für die Visualisierung
    /// und ggf. spätere Bonus-Mechaniken.
    static func streakMultiplier(forStreak days: Int) -> Double {
        switch days {
        case ..<3:   return 1.0
        case 3..<7:  return 1.5
        case 7..<14: return 2.0
        case 14..<30: return 2.5
        default:     return 3.0
        }
    }

    // MARK: - Tages-Rollover

    /// Day-Index mit 6-Uhr-Rollover — zentrale Quelle für „ist heute"-Checks.
    /// Wird sowohl vom `ProgressService` (Daily-Bonus-Throttling / Streak-Update)
    /// als auch von Views (Home-Daily-Chip) konsumiert, damit Logik und Anzeige
    /// synchron sind. 6-Uhr-Cutoff entspricht `ElumiRewardVisuals`-Konvention.
    static var currentDayIndex: Int {
        let secondsPerDay = 86_400
        let offset = 6 * 3600
        return (Int(Date().timeIntervalSince1970) - offset) / secondsPerDay
    }
}
