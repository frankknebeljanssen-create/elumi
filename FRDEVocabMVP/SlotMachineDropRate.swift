import Foundation

/// **Elumi-Drop-Rate-Controller** — gewichtete Wahrscheinlichkeitssteuerung
/// für das Elumi-Bonus-Symbol der Slot-Machine.
///
/// Nach User-Spec 2026-04-22 (Nachmittag):
///   • Kein reines Random — gefühlte Fairness steht über mathematischer
///     Perfektion
///   • Basis-Chance 22 % pro Reel für Elumi
///   • Bad-Luck-Protection: +10 % nach 3 Spins ohne Elumi, nochmal +10 %
///     (also +20 % total) nach 5 Spins ohne Elumi — setzt sich bei jedem
///     Treffer zurück
///   • Soft-Cap nach großen Gewinnen: 2er-Elumi-Treffer → -5 % nächster
///     Spin, 3er → -10 % nächster Spin (wirkt nur einen Spin lang)
///
/// Alle Tuning-Werte zentral unter `Tuning` — einfach anpassbar ohne
/// die State-Logik zu berühren.
///
/// **Reentrance**: Alle Methoden sind MainActor-safe, kein Lock nötig —
/// die Slot-Machine-UI ruft sie sequenziell auf dem MainThread.
@MainActor
final class ElumiDropRateControllerStore: ObservableObject {

    // MARK: - Tuning

    /// Alle wichtigen Drop-Rate-Parameter an einer Stelle. Direkt
    /// tunebar, falls Test-Feedback des Users zeigt, dass es sich
    /// zu selten oder zu häufig anfühlt.
    enum Tuning {
        /// Basis-Elumi-Wahrscheinlichkeit pro Reel (22 %)
        static let baseChance: Double = 0.22
        /// Nach `badLuckThreshold1` Spins ohne Elumi: +10 %
        static let badLuckStep1: Double = 0.10
        /// Nach `badLuckThreshold2` Spins ohne Elumi: zusätzliche +10 %
        static let badLuckStep2: Double = 0.10
        /// Nach 2-Elumi-Treffer: nächster Spin -5 %
        static let penalty2: Double = 0.05
        /// Nach 3-Elumi-Treffer: nächster Spin -10 %
        static let penalty3: Double = 0.10

        /// Spins-ohne-Elumi-Grenzwert für Step 1
        static let badLuckThreshold1: Int = 3
        /// Spins-ohne-Elumi-Grenzwert für Step 2
        static let badLuckThreshold2: Int = 5

        /// Harte Obergrenze, damit Bad-Luck-Protection + Base zusammen
        /// nicht unrealistisch hoch werden (z. B. 60 % wäre Casino-
        /// dumpf).
        static let maxChance: Double = 0.55
        /// Untere Grenze, damit Soft-Cap nicht in negative Wahrscheinlichkeit
        /// kippt.
        static let minChance: Double = 0.05
    }

    // MARK: - State

    /// Anzahl Spins seit dem letzten Elumi-Treffer (beliebiger Count ≥ 1).
    /// Nach einem Treffer zurück auf 0.
    @Published private(set) var spinsSinceLastElumi: Int = 0

    /// Elumi-Count des zuletzt abgeschlossenen Spins (0..3). Wird für
    /// die Soft-Cap-Berechnung des nächsten Spins benötigt.
    @Published private(set) var lastSpinElumiCount: Int = 0

    // MARK: - Public API

    /// Berechnet die effektive Elumi-Wahrscheinlichkeit pro Reel für den
    /// **nächsten** Spin. Berücksichtigt Bad-Luck-Bonus und Soft-Cap.
    func currentElumiChance() -> Double {
        var chance = Tuning.baseChance
        // Bad-Luck-Protection — nur aktiv, wenn seit mehreren Spins
        // kein Treffer gelandet ist.
        if spinsSinceLastElumi >= Tuning.badLuckThreshold2 {
            chance += Tuning.badLuckStep1 + Tuning.badLuckStep2
        } else if spinsSinceLastElumi >= Tuning.badLuckThreshold1 {
            chance += Tuning.badLuckStep1
        }
        // Soft-Cap nach großem Gewinn im vorherigen Spin.
        switch lastSpinElumiCount {
        case 3: chance -= Tuning.penalty3
        case 2: chance -= Tuning.penalty2
        default: break
        }
        return min(max(chance, Tuning.minChance), Tuning.maxChance)
    }

    /// Zieht für eine Walze ein Elumi/Not-Elumi-Ergebnis mit der aktuellen
    /// berechneten Wahrscheinlichkeit. Wird pro Reel unabhängig aufgerufen.
    func drawIsElumi(chance: Double) -> Bool {
        Double.random(in: 0..<1) < chance
    }

    /// Nach einem kompletten Spin aufrufen — aktualisiert den internen
    /// State basierend auf dem Ergebnis. Gibt den neuen `spinsSinceLastElumi`
    /// + das gezählte Elumi-Count zurück (praktisch fürs Debug-Log).
    @discardableResult
    func registerSpinResult(elumiCount: Int) -> (streak: Int, count: Int) {
        lastSpinElumiCount = elumiCount
        if elumiCount > 0 {
            spinsSinceLastElumi = 0
        } else {
            spinsSinceLastElumi += 1
        }
        #if DEBUG
        print("🎰 [DropRate] Spin-Ergebnis: \(elumiCount) Elumi(s), streak=\(spinsSinceLastElumi), next-chance=\(String(format: "%.2f", currentElumiChance()))")
        #endif
        return (spinsSinceLastElumi, elumiCount)
    }

    /// Für Debug: kompletter State-Dump als String.
    func debugStateDescription() -> String {
        "streak=\(spinsSinceLastElumi), lastCount=\(lastSpinElumiCount), chance=\(String(format: "%.2f", currentElumiChance()))"
    }

    /// Reset — wird beim erneuten Betreten des Slot-Screens aufgerufen,
    /// damit ein frischer Besuch nicht von der alten Session beeinflusst
    /// wird. (Session = ein Screen-Aufruf, nicht app-weit persistent.)
    func reset() {
        spinsSinceLastElumi = 0
        lastSpinElumiCount = 0
    }
}

// MARK: - Spin-Budget

/// **Spin-Budget-Controller** — verwaltet Base-Spins + Bonus-Credits
/// getrennt, wie in der User-Spec gefordert.
///
/// Regeln:
///   • Bei Screen-Entry: 3 Base-Spins, 0 Bonus-Credits
///   • Jeder Spin: 1 Base-Spin → 0, dann Bonus-Credit → 0
///   • Elumi-Treffer (1/2/3) → +1/+3/+6 Bonus-Credits
///   • `canSpin`: ob irgendein Spin noch möglich ist (Base > 0 ODER Bonus > 0)
@MainActor
final class SlotMachineSpinBudgetStore: ObservableObject {

    // MARK: - Tuning

    enum Tuning {
        /// Anzahl Gratis-Spins pro Screen-Session.
        static let baseSpinsPerSession: Int = 3
        /// Bonus-Credits pro Elumi-Count.
        static let bonusPerElumi: [Int: Int] = [1: 1, 2: 3, 3: 6]
    }

    // MARK: - State

    @Published private(set) var baseSpinsRemaining: Int = Tuning.baseSpinsPerSession
    @Published private(set) var bonusCredits: Int = 0

    // MARK: - Derived

    var totalSpinsAvailable: Int { baseSpinsRemaining + bonusCredits }
    var canSpin: Bool { totalSpinsAvailable > 0 }

    // MARK: - Actions

    /// Zieht einen Spin vom Budget ab. Base-Spins gehen zuerst, dann
    /// Bonus-Credits. Gibt zurück, ob der Spin gebucht werden konnte.
    @discardableResult
    func consumeSpin() -> Bool {
        if baseSpinsRemaining > 0 {
            baseSpinsRemaining -= 1
            return true
        }
        if bonusCredits > 0 {
            bonusCredits -= 1
            return true
        }
        return false
    }

    /// Vergibt Bonus-Credits basierend auf dem Elumi-Count des
    /// gerade gelandeten Spins. Gibt die vergebenen Credits zurück
    /// (für die UI-Animation „+3 Credits").
    @discardableResult
    func awardBonusCredits(for elumiCount: Int) -> Int {
        guard let award = Tuning.bonusPerElumi[elumiCount] else { return 0 }
        bonusCredits += award
        return award
    }

    /// Reset beim Screen-Entry.
    func reset() {
        baseSpinsRemaining = Tuning.baseSpinsPerSession
        bonusCredits = 0
    }
}
