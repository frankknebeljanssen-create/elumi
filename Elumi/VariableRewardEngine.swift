import Foundation

/// Engine für variable Belohnungen (Phase 7 — psychologische Feinmechanik).
///
/// Prinzip: die feste Session-XP/Credits-Mathematik aus `ProgressService`
/// bleibt unverändert und vorhersehbar. **Zusätzlich** rollen wir mit
/// kleiner Wahrscheinlichkeit einen Bonus — ein nicht-vorhersehbares
/// Glücksmoment. Das erzeugt Erwartung („Vielleicht passiert beim
/// nächsten Mal wieder was!") ohne das Balancing kaputtzumachen.
///
/// Alle Wahrscheinlichkeiten + Wertebereiche stehen **zentral hier** —
/// nicht in Views verteilt. Wer feinjustieren will, passt nur hier an.
///
/// Designregeln:
///   • Bonus niemals höher als der Kern-Reward — sonst fühlt sich das
///     Normale wie eine Strafe an.
///   • Nur bei qualifizierten Sessions (`meetsMinimumThreshold`) rollen,
///     sonst kann ein 1-Antwort-Session-Spam farmen.
///   • Nicht zu häufig — Variation ist der Punkt, nicht Inflation.
enum VariableRewardEngine {

    // MARK: - Wahrscheinlichkeiten

    /// ~8 % aller qualifizierten Sessions: kleiner XP-Bonus.
    static let bonusXPChance: Double = 0.08

    /// ~3 % aller qualifizierten Sessions: Glückstreffer-Credit.
    static let luckyCreditChance: Double = 0.03

    // MARK: - Wertbereiche

    /// XP-Range für den Bonus. Bewusst moderat (ca. 1–3 richtige Antworten
    /// wert), damit es sich wie „nice touch" anfühlt und nicht wie Jackpot.
    static let bonusXPRange: ClosedRange<Int> = 10...30

    // MARK: - Public API

    /// Rollt die variablen Belohnungen für eine Session. Rückgabe ist
    /// ein Outcome-Struct, das `ProgressService` in sein
    /// `SessionRewardOutcome` falten und `SessionSummaryView` als
    /// separaten Chip anzeigen kann.
    ///
    /// RNG ist bewusst unseeded — jede Session ist ein unabhängiger Wurf.
    /// Wenn wir später deterministisches Verhalten wollen (Testing),
    /// ziehen wir einen injizierbaren Random-Provider ein.
    static func roll(for session: LearningSession) -> VariableRewardOutcome {
        guard session.meetsMinimumThreshold else {
            return .none
        }

        var bonusXP = 0
        var bonusCredit = 0

        if Double.random(in: 0..<1) < bonusXPChance {
            bonusXP = Int.random(in: bonusXPRange)
        }

        if Double.random(in: 0..<1) < luckyCreditChance {
            bonusCredit = 1
        }

        return VariableRewardOutcome(bonusXP: bonusXP, bonusCredit: bonusCredit)
    }
}

/// Ergebnis eines Variable-Reward-Wurfs. Alles 0 → kein Chip, kein Effekt.
struct VariableRewardOutcome: Equatable {
    let bonusXP: Int
    let bonusCredit: Int

    static let none = VariableRewardOutcome(bonusXP: 0, bonusCredit: 0)

    var hasBonus: Bool {
        bonusXP > 0 || bonusCredit > 0
    }

    /// Textzusammenfassung für die Summary-UI. Faltet beide Bonus-Arten
    /// in einen ruhigen Satz — keine getrennten Mini-Chips.
    var summaryText: String? {
        switch (bonusXP > 0, bonusCredit > 0) {
        case (false, false):
            return nil
        case (true, false):
            return "Bonus +\(bonusXP) XP"
        case (false, true):
            return "Glückstreffer +1 Credit"
        case (true, true):
            return "Bonus +\(bonusXP) XP · Glückstreffer +1 Credit"
        }
    }

    /// Headline für den Chip — ein Wort, emotional.
    var headline: String {
        // Glückstreffer hat Vorrang — das seltenere Ereignis ist der
        // dramatischere Moment, darum wird es zuerst benannt.
        if bonusCredit > 0 { return "Glückstreffer!" }
        return "Bonus!"
    }
}
