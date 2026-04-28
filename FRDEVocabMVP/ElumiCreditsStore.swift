import Foundation
import SwiftUI
import Combine

/// **Elumi-Play-Credits** (2026-04-24 Testsystem).
///
/// Separater, isolierter Credit-Pool **ausschließlich** für das Elumi-
/// Arcade-Spiel. Wird durch die Slot Machine im Trainingsgenerator
/// gefüllt (1/3/6 pro Elumi-Treffer) und im Spiel verbraucht für
/// Hilfen wie „Fehler retten" und „Aufgabe überspringen".
///
/// **Bewusste Abgrenzung — existierende Systeme bleiben unberührt:**
///
///   • `appArcadeCreditsKey` / GameHub-Logik: Die bestehende
///     Credit-Economy (1 Credit = 1 Spielstart) im **Game Hub**
///     funktioniert **unabhängig** weiter. Kein Shared State, kein
///     Read/Write auf denselben Key.
///   • `SlotMachineSpinBudgetStore`: Der Slot-interne Spin-Pool (3
///     Base-Spins + Bonus-Credits für **weitere Spins**) bleibt
///     unverändert — er hat eine ganz andere Rolle (Slot-Session-
///     Budget, nicht persistiert, nicht für Spiel-Hilfen).
///   • **Word Runner**: Nutzt diesen Store bewusst **nicht**. Kein
///     Import, keine UI-Anzeige, keine Logikverbindung — Spec-Pflicht.
///
/// **Persistenz**: Eigener `UserDefaults`-Key `appElumiPlayCreditsKey`.
/// Die `@Published credits`-Property hält den gemerkten Wert — Reader
/// via `@ObservedObject` oder `@StateObject` bekommen automatische
/// UI-Updates, persistent gegen App-Neustart.
///
/// **Concurrency**: `@MainActor`, alle Mutationen synchron auf dem
/// Main-Thread. Kein Lock nötig. Die Spin-ID-Dedup-Guard schützt
/// gegen versehentliches Doppel-Granting bei schnellen Re-Triggern.
@MainActor
final class ElumiCreditsStore: ObservableObject {

    // MARK: - Singleton

    /// Shared-Instanz — ein Wahrheitsort pro App-Run. Alle Views lesen
    /// denselben State; UI-Updates fließen via `@Published`.
    static let shared = ElumiCreditsStore()

    // MARK: - Public State

    /// Aktueller Credit-Stand. **Schreibzugriff nur über die API-
    /// Methoden** (`grantForSlot`, `useCredit`, `addCredits`, `reset`).
    /// Public getter für UI-Bindings.
    @Published private(set) var credits: Int

    /// True wenn Credits > 0 — convenience für disabled-Button-Logik.
    var hasCredits: Bool { credits > 0 }

    // MARK: - Slot-Grant-Tuning

    /// Zentrale Mapping-Tabelle Slot-Ergebnis → Credits. Einzige
    /// Quelle, damit die Regel überall gleich gilt und leicht tunbar
    /// bleibt. Spec 2026-04-24:
    ///   • 1 Elumi  → +1 Credit
    ///   • 2 Elumis → +3 Credits
    ///   • 3 Elumis → +6 Credits
    enum GrantTable {
        static let perElumiCount: [Int: Int] = [1: 1, 2: 3, 3: 6]
    }

    // MARK: - Double-Grant-Protection

    /// Optionaler Dedup-Key pro Spin. Wenn der Caller eine UUID liefert,
    /// wird jede UUID höchstens EINMAL akzeptiert. Guard gegen
    /// versehentliches Doppelaufrufen derselben Callback durch UI-
    /// Races (z. B. wenn `.onChange` zweimal feuert).
    private var consumedSpinIDs: Set<UUID> = []

    // MARK: - Init

    private init() {
        // Initial-Load aus UserDefaults. Default 0, falls noch nie
        // geschrieben. `integer(forKey:)` liefert 0 bei fehlendem Key.
        self.credits = UserDefaults.standard.integer(forKey: appElumiPlayCreditsKey)
    }

    // MARK: - Slot-Grant

    /// Nach einem abgeschlossenen Slot-Spin vergeben. Muss erst nach
    /// **vollständigem Reel-Stop** aufgerufen werden (Caller-Pflicht).
    ///
    /// - Parameters:
    ///   - elumiCount: 0…3 Elumi-Symbole in der Mittelreihe
    ///   - spinID: Optional — wenn gesetzt, wird dieselbe UUID nur
    ///     einmal als vergeben gezählt (Dedup). Für neue Aufrufer:
    ///     pro Spin eine frische UUID erzeugen und mitgeben.
    /// - Returns: Tatsächlich vergebene Credit-Menge (0, 1, 3 oder 6).
    @discardableResult
    func grantForSlot(elumiCount: Int, spinID: UUID? = nil) -> Int {
        // Dedup, falls der Caller eine UUID mitliefert.
        if let id = spinID {
            guard !consumedSpinIDs.contains(id) else {
                #if DEBUG
                print("🎟️ [ElumiCredits] grant skip — duplicate spinID \(id)")
                #endif
                return 0
            }
            consumedSpinIDs.insert(id)
        }

        let grant = GrantTable.perElumiCount[elumiCount] ?? 0
        guard grant > 0 else { return 0 }

        credits += grant
        persist()
        #if DEBUG
        print("🎟️ [ElumiCredits] +\(grant) credits (Elumis: \(elumiCount)) → total=\(credits)")
        #endif
        return grant
    }

    /// Direktes Hinzufügen einer Credit-Menge. Nicht vom Slot-Grant-
    /// Pfad genutzt — nützlich für Dev-/Test-Wege und zukünftige
    /// Reward-Quellen.
    func addCredits(_ amount: Int) {
        guard amount > 0 else { return }
        credits += amount
        persist()
        #if DEBUG
        print("🎟️ [ElumiCredits] +\(amount) (manual) → total=\(credits)")
        #endif
    }

    // MARK: - Consume

    /// Verbraucht **genau einen** Credit (für Rescue/Skip im Spiel).
    ///
    /// **Race-Protection**: die Entscheidung `credits > 0 ? −1 : fail`
    /// läuft synchron auf dem MainActor, keine Lücken zwischen Check
    /// und Decrement möglich. Doppel-Taps in schneller Folge werden
    /// sauber durch die zweite Anfrage falsch beantwortet, weil der
    /// erste Decrement bereits sichtbar ist.
    ///
    /// - Returns: `true` wenn ein Credit abgezogen werden konnte,
    ///   `false` wenn keine verfügbar waren. Caller kann anhand des
    ///   Rückgabewerts die Feature-Aktion gaten.
    @discardableResult
    func useCredit() -> Bool {
        guard credits > 0 else {
            #if DEBUG
            print("🎟️ [ElumiCredits] useCredit blocked — balance=0")
            #endif
            return false
        }
        credits -= 1
        persist()
        #if DEBUG
        print("🎟️ [ElumiCredits] -1 credit → total=\(credits)")
        #endif
        return true
    }

    // MARK: - Dev-Reset

    /// **Nur für Entwicklung/Testing** (Spec #9). Setzt den Credit-
    /// Stand auf 0 und leert den Dedup-Cache. Produktiv nicht nötig.
    func resetForTesting() {
        credits = 0
        consumedSpinIDs.removeAll()
        persist()
        #if DEBUG
        print("🎟️ [ElumiCredits] reset (dev) → total=0")
        #endif
    }

    // MARK: - Persistence

    private func persist() {
        UserDefaults.standard.set(credits, forKey: appElumiPlayCreditsKey)
    }
}
