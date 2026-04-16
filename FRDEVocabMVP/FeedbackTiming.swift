import Foundation

/// Zentrale Timing-Konstanten für das Phase-7-Feedback-Design.
///
/// Regel: Feedback darf **nie gleichzeitig** kommen — immer gestaffelt.
/// Kurze Micro-Delays (300–800 ms) sorgen dafür, dass der User jedes
/// einzelne Element wahrnehmen kann, ohne dass es langsam wirkt.
///
/// Einziger Ort zum Nachjustieren: wer „ein bisschen zackiger" oder
/// „etwas ruhiger" will, ändert genau hier. Kein verteiltes Magic
/// Timing in einzelnen Views mehr.
enum FeedbackTiming {

    // MARK: - Session Summary (Session End)

    /// Dauer des XP-Hochzählers von 0 auf `totalXP`.
    static let xpCountUpDuration: TimeInterval = 0.9

    /// Verzögerung, bis die Progress-Bar zu wandern beginnt. Kommt NACH
    /// dem ersten XP-Tick, damit die Zahl vorher Aufmerksamkeit bekommt.
    static let progressBarAnimationDelay: TimeInterval = 0.30

    /// Wie lange die Progress-Bar auf ihren Zielwert rampt.
    static let progressBarDuration: TimeInterval = 1.10

    /// Staffel-Delays für die Reward-Chips: Tagesaufgabe → Level-Up
    /// → Streak → XP-Credits. Reihenfolge = emotionale Priorität.
    static let rewardChipStagger: [TimeInterval] = [0.15, 0.25, 0.40, 0.55]

    /// Kleines Aufflackern auf Hero-Events (Level-Up, Streak-Milestone).
    static let heroPulseDelay: TimeInterval = 0.45
    static let heroPulseDuration: TimeInterval = 0.9

    // MARK: - Combo-Toast (Overlay während der Session)

    /// Sichtbare Zeit des Combo-Toasts im Overlay.
    static let comboToastVisibleDuration: TimeInterval = 1.6

    /// Einschwing-Animation des Combo-Toasts (Spring-Response).
    static let comboToastEnterResponse: Double = 0.42
    static let comboToastEnterDamping: Double = 0.78

    // MARK: - Variable Rewards

    /// Spannung-Delay: ein Variable-Reward-Chip („Bonus!", „Glückstreffer!")
    /// erscheint leicht nach dem normalen Daily-Chip — so wirkt er wie
    /// ein gesonderter Glücksmoment, nicht wie Teil des Standards.
    static let variableRewardExtraDelay: TimeInterval = 0.65
}
