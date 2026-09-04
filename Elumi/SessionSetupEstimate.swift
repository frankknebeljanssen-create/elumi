import Foundation
import SwiftUI

/// Konfiguration einer geplanten Lernsession — wird **vor** dem Start
/// der Session aus den UI-Inputs zusammengebaut. Minimaler Wert-Typ,
/// damit die Preview-Mathematik nicht an modulspezifische Typen
/// gekoppelt ist.
///
/// Wichtig: das ist *nicht* die persistente Session-State-Struktur eines
/// Moduls (z. B. `FlashcardSessionSetup`). Es ist ein reines
/// **Vorhersage-Input**-Paket für die Gamification-Bar.
struct SessionConfig: Equatable {
    enum Module: String, Equatable {
        case flashcards
        case quiz
        case training
        case speedRound
        case verbforms
    }

    let module: Module

    /// Anzahl der Items, die die Session adressieren wird.
    /// Quiz: Fragen · Flashcards: Karten · Training: Vokabeln/Verben …
    let itemCount: Int

    /// Optionaler Runden-Multiplikator (Flashcards: 1×/2×/3× Mastery).
    /// Für die XP-/Dauer-Schätzung multipliziert sich die Antwortzahl.
    let roundMultiplier: Int

    init(module: Module, itemCount: Int, roundMultiplier: Int = 1) {
        self.module = module
        self.itemCount = max(0, itemCount)
        self.roundMultiplier = max(1, roundMultiplier)
    }

    var effectiveItemCount: Int { itemCount * roundMultiplier }
}

/// Vorschau-Paket für die Gamification-Bar auf allen Setup-Screens.
///
/// Alle Werte basieren auf bestehender Balancing-Logik
/// (`GamificationConfig`, `DailyChallengeStore`, Streak-Multiplikator-Tabelle) —
/// **keine neue Rechnung** nur für die Vorschau. So stimmen Preview und
/// echter Session-Ertrag überein.
struct SessionEstimate: Equatable {
    /// Erwartete XP bei vollständiger richtiger Absolvierung
    /// (realistischer Fall: 100 % korrekt + 1 Combo pro Threshold).
    let expectedXP: Int

    /// Geschätzte Dauer in ganzen Minuten.
    let expectedDuration: Int

    /// Aktueller Streak-Multiplikator — informativ, multipliziert NICHT
    /// die XP (Streak-XP-Multiplier ist bewusst nicht aktiv), sondern
    /// zeigt, wie wertvoll die aktuelle Streak-Stufe ist.
    let streakMultiplier: Double

    /// Erwartete Credits aus dieser Session (XP-Milestones + ggf.
    /// Daily-Challenge-Completion).
    let expectedCredits: Int

    static let zero = SessionEstimate(
        expectedXP: 0,
        expectedDuration: 0,
        streakMultiplier: 1.0,
        expectedCredits: 0
    )

    // MARK: - Formatted accessors (Master-Setup-Spec)
    //
    // Die View-Schicht braucht user-facing Strings und „hide-if-empty"-
    // Semantik. Statt die View eigenes Formatieren machen zu lassen,
    // liegen die Formate hier. `nil` bedeutet: Metric im Bar nicht zeigen.

    /// XP-Wert fürs Gamification-Bar-Metric.
    var estimatedXP: Int { expectedXP }

    /// Minuten — `nil` wenn wir keine sinnvolle Schätzung haben
    /// (z. B. bei items == 0).
    var estimatedMinutes: Int? {
        expectedDuration > 0 ? expectedDuration : nil
    }

    /// Streak-Multiplikator als formatierter String („×1.2") oder `nil`,
    /// wenn die Stufe noch bei ×1.0 ist (kein echter Bonus → keine
    /// visuelle Metrik, sonst wirkt der Platz leer).
    var streakMultiplierText: String? {
        guard streakMultiplier > 1.0 else { return nil }
        return String(format: "×%.1f", streakMultiplier)
    }

    /// Erwartete Credits als formatierter String („+1") oder `nil`.
    var estimatedCreditsText: String? {
        expectedCredits > 0 ? "+\(expectedCredits)" : nil
    }
}

/// Zentrale Berechnung. **Einziger Ort**, an dem die Vorschau-Mathematik
/// lebt — Views konsumieren nur das Ergebnis, rechnen nichts selbst.
enum SessionSetupEstimator {

    /// Sekunden pro Item je nach Modul. Empirisch gewählt, kann zentral
    /// angepasst werden ohne Call-Sites anzufassen.
    private static func secondsPerItem(_ module: SessionConfig.Module) -> Double {
        switch module {
        case .flashcards:  return 8.0
        case .quiz:        return 12.0
        case .training:    return 10.0
        case .speedRound:  return 4.0
        case .verbforms:   return 7.0
        }
    }

    @MainActor
    static func estimate(
        for config: SessionConfig,
        progress: UserProgress,
        dailyChallenge: DailyChallenge?
    ) -> SessionEstimate {
        let items = config.effectiveItemCount
        guard items > 0 else { return .zero }

        // XP: items × Basis + wahrscheinliche Combos
        let baseXP = items * GamificationConfig.xpPerCorrectAnswer
        let comboCount = items / GamificationConfig.xpComboThreshold
        let comboXP = comboCount * GamificationConfig.xpComboBonus
        let expectedXP = baseXP + comboXP

        // Dauer in Minuten (aufgerundet auf volle Minuten)
        let totalSeconds = Double(items) * secondsPerItem(config.module)
        let expectedDuration = max(1, Int(ceil(totalSeconds / 60.0)))

        // Streak-Multiplikator — aus bestehender Tabelle
        let streakMultiplier = GamificationConfig.streakMultiplier(
            forStreak: progress.currentStreak
        )

        // Credits: XP-Milestones + ggf. Daily-Challenge-Reward
        let currentXP = progress.totalXP
        let postXP = currentXP + expectedXP
        let xpMilestoneCredits = (postXP / GamificationConfig.xpPerBonusCredit)
            - (currentXP / GamificationConfig.xpPerBonusCredit)

        var expectedCredits = xpMilestoneCredits

        // Daily-Challenge-Completion einrechnen, falls diese Session sie
        // voraussichtlich abschließt.
        if let challenge = dailyChallenge, challenge.status != .done {
            let increment: Int
            switch challenge.type {
            case .answers:
                increment = items
            case .completeSession:
                increment = items > 0 ? 1 : 0
            case .speedRound:
                increment = (config.module == .speedRound && items > 0) ? 1 : 0
            }
            if challenge.currentProgress + increment >= challenge.target {
                expectedCredits += challenge.reward.credits
            }
        }

        return SessionEstimate(
            expectedXP: expectedXP,
            expectedDuration: expectedDuration,
            streakMultiplier: streakMultiplier,
            expectedCredits: expectedCredits
        )
    }
}
