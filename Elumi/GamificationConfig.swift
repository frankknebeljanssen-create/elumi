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
    // **Balancing-Phase 7** (User-Spec „XP langsamer und realistischer"):
    // die bisherigen Werte (10 Basis, 25 Combo, 75 Flawless, 20 Mastery)
    // haben in Verbindung mit dem neuen `xpPerBonusCredit = 250` dazu
    // geführt, dass Spiele trotz angehobener XP-Schwelle noch zu dicht
    // entstehen — eine 15-Fragen-Session konnte bereits 200+ XP
    // erzeugen. Wir senken die Basis um ~50 % und skalieren die Boni
    // anteilig nach unten, damit jede Quelle weiterhin spürbar bleibt,
    // ohne dass ein Spiel pro Session automatisch heraus fällt.

    /// Basis-XP pro richtig beantworteter Lerneinheit. Gilt für alle Module
    /// gleich — Karteikarte richtig, Quizfrage richtig, Verbform richtig usw.
    ///
    /// **Phase 7**: 10 → 5 (−50 %).
    static let xpPerCorrectAnswer = 5

    /// Combo-Bonus alle N richtigen Antworten in Folge (innerhalb einer Session).
    ///
    /// **Phase 7**: 25 → 15. Combos bleiben emotional eine Belohnung
    /// (3-fache Basis pro 5er-Kette), fluten das XP-Konto aber nicht mehr.
    static let xpComboThreshold = 5
    static let xpComboBonus = 15

    /// Pauschal-Bonus für eine fehlerfrei abgeschlossene Session.
    ///
    /// **Phase 7**: 75 → 40. Mit 5 XP/Antwort entspricht 40 jetzt
    /// ~8 zusätzlichen Antworten — ein „ganzer Session-Teil extra"-Gefühl,
    /// ohne dass Flawless allein bereits ein Spiel (250 XP) pro Session
    /// rechtfertigt.
    static let xpFlawlessSessionBonus = 40

    /// Bonus pro Karte, die in Karteikarten endgültig gemeistert wurde
    /// (also `consecutiveCorrect ≥ masteryThreshold` erreicht hat). Belohnt
    /// gründliches Lernen — gleicht Karteikarten gegen schnellere Modi aus.
    ///
    /// **Phase 7**: 20 → 10. Passt zur halbierten Basis, behält die Mastery-
    /// „zählt doppelt"-Aussage (2× Basis pro gemeisterter Karte).
    static let xpMasteredCardBonus = 10

    /// Tagesabschluss-Bonus — **nicht mehr direkt genutzt** seit Phase 5.
    /// Wird jetzt vom `DailyChallengeStore` als Challenge-Reward vergeben
    /// (pro Typ individuell, 40–60 XP). Der Konstantenwert bleibt stehen,
    /// falls noch irgendwo referenziert — der echte Wert kommt aus der
    /// `DailyChallenge.reward.xp`-Struktur.
    static let xpDailyCompletionBonus = 50

    // MARK: - Level Curve (progressive, Phase 7)
    //
    // **Phase 7 Rebalancing** (User-Spec): Kurve leicht gestreckt, damit
    // Level mit der halbierten XP-Basis (5 statt 10 XP/Antwort) echt
    // wertvoller bleiben. Frühe Level bleiben schnell („erstes Level-Up
    // nach wenigen Minuten"), späte Level strecken sich deutlich.
    //
    // Neue Delta-Kurve (XP-Kosten L→L+1):
    //   L1→L2:  100    (kleiner Einstieg)
    //   L2→L3:  180
    //   L3→L4:  300
    //   L4→L5:  450
    //   L5→L6:  650
    //   L6→L7:  850
    //   Lx→Lx+1 (x≥6): +200 pro weiterem Level
    //
    // Kumulierte XP zum Erreichen von Level L:
    //   L1:    0    (Start)
    //   L2:    100
    //   L3:    280
    //   L4:    580
    //   L5:   1030
    //   L6:   1680
    //   L7:   2530
    //   L8:   3580
    //   …
    //
    // Mit xpPerCorrectAnswer = 5 entspricht Level 6 damit ~336 richtigen
    // Antworten über alle Sessions hinweg — erreichbar über 2-4 Wochen
    // regelmäßiger Nutzung, nicht an einem Nachmittag.

    /// XP, um vom aktuellen Level ins nächste zu kommen. Einziger Ort
    /// zum Rebalancen der Kurve.
    static func xpRequiredForNextLevel(afterLevel currentLevel: Int) -> Int {
        switch currentLevel {
        case ..<1: return 0
        case 1: return 100
        case 2: return 180
        case 3: return 300
        case 4: return 450
        case 5: return 650
        default:
            // Ab Level 6: +200 XP pro Level. Step-Funktion bewusst
            // linear — keine exponentielle Explosion, aber spürbar
            // länger pro Level.
            return 650 + (currentLevel - 5) * 200
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

    /// Credits-Belohnung pro Level-Up (= „Spiele").
    ///
    /// **Balancing-Review**: Level-Ups sind selten (Level 1→2 nach
    /// ~100 XP, spätere Levels brauchen 300+ XP). Frühere 5 Spiele pro
    /// Level-Up waren großzügig, passten aber zur alten 20-XP-Rate.
    /// Jetzt mit 250 XP = 1 Spiel wirkt 5 inflationär — **reduziert
    /// auf 3**. Erste Level-Ups fühlen sich weiterhin belohnend an
    /// (3 ganze Spiele), die Summe über mehrere Level-Ups bleibt
    /// aber im motivierenden, nicht überflutenden Rahmen.
    static let creditsPerLevelUp = 3

    // MARK: - Credits

    /// XP → Spiel-Konvertierung: alle N XP gibt es 1 Bonus-Spiel.
    /// **Von 100 auf 250 erhöht** (Game-Loop-Spec: „200–300 XP → 1 Spiel").
    /// Damit gibt nicht jede Session ein Spiel, Spiele bleiben Belohnung,
    /// kein Dauerzustand. Singuläre Wahrheits-Konstante für diese
    /// Rate — `ArcadeCreditSystem.xpPerCredit` delegiert hierher.
    static let xpPerBonusCredit = 250

    /// Credits-Bonus (= „Spiele") bei Streak-Meilensteinen.
    /// Key = erreichter Streak-Tag, Value = Spiele-Bonus (einmalig).
    ///
    /// **Balancing-Review (deutliche Reduktion)**: vorher 2 / 5 / 10 / 25
    /// — im Zusammenspiel mit Daily-Challenge (+1/Tag) und Level-Up-
    /// Bonus addierten sich die Quellen zu einem Überfluss, der dem
    /// Game-Loop-Prinzip „Spiel = Belohnung, kein Dauerbestand"
    /// widersprach. Neu: 1 / 2 / 4 / 8 — ca. halbiert, Meilenstein
    /// bleibt spürbar, ohne das System zu fluten.
    static let creditsForStreakMilestones: [Int: Int] = [
        3:  1,
        7:  2,
        14: 4,
        30: 8
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

    /// **Mini-Session-Schwelle (2026-08-08)** — so viele korrekt
    /// beantwortete Aufgaben an einem Tag reichen, um den Streak zu
    /// halten, UNABHÄNGIG davon, ob die (größere) Daily Challenge erfüllt
    /// wurde. Vorher war die volle Tagesaufgabe (z. B. 15 Fragen oder eine
    /// Speed Round) der einzige Streak-Trigger — das koppelte zwei
    /// mechanisch verschiedene Dinge (Tagesziel und Gewohnheit) aneinander.
    ///
    /// Evidenzgrundlage: Duolingo hat Streak und Tagesziel entkoppelt
    /// (eine Mini-Lektion hält den Streak, das Tagesziel läuft separat)
    /// und maß dadurch +3,3 % Retention. Siehe auch `StreakJokerStore`.
    static let streakMiniSessionThreshold = 5

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
