import Foundation

/// **Trainings-Session-Auto-Verkettung — Chain-Context**
/// (Stufe 1, 2026-04-30, Branch `feature/training-session-flow`).
///
/// Die Slot-Machine im Elumi-Tab produziert ein 3-Slot-Ergebnis aus
/// Modul-Symbolen + Game-Slots (Bonus-Token). `TrainingChainContext`
/// verpackt dieses Ergebnis in eine sequentielle Übungs-Verkettung:
/// das erste nicht-Game-Modul startet, der User durchläuft die Übung,
/// klickt am Done-Screen „Weiter zu Übung N+1" (Stufe 2), und wir
/// rotieren durch `plannedSteps` bis das letzte Modul abgeschlossen ist.
///
/// **Game-Slots werden in `make(...)` herausgefiltert** — sie geben
/// Credits beim Slot-Stop (siehe `ElumiTabView.handleSlotLanded`) und
/// tauchen in der Chain selbst nicht mehr auf. `sourceCenterSymbolKinds`
/// bewahrt die vollständige Original-Reel-Sequenz für die End-Summary
/// in Stufe 4 („Reel 2: Game — gewertet als +3 Credits").
///
/// Stufe 1 baut nur die Datenstruktur und initialisiert sie beim
/// `startTraining()`-Tap. Die CTA-Override-Logik (Modul-Done-Screens
/// erkennen `chainContext` und springen weiter) folgt in Stufe 2.
struct TrainingChainContext: Hashable {
    /// Stable ID pro Chain-Run — für Idempotenz-Checks und Debug-Logs.
    let id: UUID

    /// Geplante Modul-Reihenfolge ohne Game-Slots.
    /// Beispiel: Slot-Result `[Karteikarten, Game, Quiz]` →
    /// `plannedSteps = [.karteikarten, .quiz]`.
    let plannedSteps: [HomeHeroModule]

    /// 0-basierter Index in `plannedSteps`. `currentIndex == plannedSteps.count`
    /// signalisiert „Chain abgeschlossen, End-Summary anzeigen" (Stufe 4).
    let currentIndex: Int

    /// Trainingsdauer pro Step in Minuten (gleichmäßig auf nicht-Game-
    /// Slots verteilt). Bei 10min Total + 2 Modul-Slots → 5min/Step.
    /// V1 nutzt diesen Wert nur als Anzeige-Hint; das eigentliche
    /// Modul-Timing folgt der modul-eigenen Konfiguration.
    let perStepDurationMin: Int

    /// Original-Reel-Symbole im Original-Slot-Order (3 Einträge).
    /// Hashable-tauglich via `SourceSlotKind`-Enum statt `ReelSymbol`,
    /// damit `TrainingChainContext` als `LaunchContext`-Feld
    /// Hashable-konform bleibt (ReelSymbol hat UUID-Identity, nicht
    /// stable-hashbar für Hashable-Konformität via NavigationPath).
    let sourceCenterSymbolKinds: [SourceSlotKind]

    /// **Daily Drop Modul 2 (2026-05-23)** — Per-Step-Aufgabenzahl im
    /// Count-Modus. `nil` = Zeit-Modus (klassische Chain mit
    /// `perStepDurationMin` + Timer). Non-nil → die Chain läuft
    /// anzahl-gegatet (kein Timer); jeder Step endet nach genau N
    /// Aufgaben (über die Modul-1-Caps in den Launch-Contexts).
    let perStepCount: Int?

    enum SourceSlotKind: Hashable {
        case module(HomeHeroModule)
        case game
    }

    /// Ist die Chain abgeschlossen (alle plannedSteps konsumiert)?
    var isFinished: Bool {
        currentIndex >= plannedSteps.count
    }

    /// Aktueller Modul-Step, oder nil wenn Chain bereits abgeschlossen.
    var currentStep: HomeHeroModule? {
        guard plannedSteps.indices.contains(currentIndex) else { return nil }
        return plannedSteps[currentIndex]
    }

    /// Nächster Step nach dem aktuellen — für Inter-Step-CTA-Label
    /// („Weiter zu Quiz →"). Nil bei letztem Step (CTA wechselt dann
    /// auf „Training abschließen").
    var nextStep: HomeHeroModule? {
        let next = currentIndex + 1
        guard plannedSteps.indices.contains(next) else { return nil }
        return plannedSteps[next]
    }

    /// 1-basierter Schritt-Zähler für UI-Anzeige („Übung 2 von 3").
    var displayStepNumber: Int { currentIndex + 1 }

    /// Gesamt-Step-Zahl für UI-Anzeige (immer == plannedSteps.count).
    var totalStepCount: Int { plannedSteps.count }

    /// **Daily Drop Modul 2 (2026-05-23)** — Count-Modus aktiv?
    var isCountMode: Bool { perStepCount != nil }

    /// **Daily Drop Modul 2 (2026-05-23)** — Gesamt-Aufgabenzahl der
    /// Chain (Per-Step-Count × Anzahl Steps, even-split). `0` außerhalb
    /// des Count-Modus — die Count-Bar wird dann ohnehin nicht gezeigt.
    var totalExerciseCount: Int {
        guard let perStepCount else { return 0 }
        return perStepCount * plannedSteps.count
    }

    /// **Stufe 2 (2026-04-30)** — alle 3 Slots waren Game (3× Game).
    /// Pre-Screen rendert dann nur Game-Cards, „Übung starten"-CTA ist
    /// disabled, Hint-Text fordert zum Neu-Drehen auf. Credits sind in
    /// `ElumiTabView.startTraining` schon gutgeschrieben (Jackpot-
    /// Pfad +6 Tickets), bevor zum Pre-Screen navigiert wird. Stufe 5
    /// baut auf dieser Property die Feier-Animation auf.
    var isJackpot: Bool {
        plannedSteps.isEmpty
            && !sourceCenterSymbolKinds.isEmpty
            && sourceCenterSymbolKinds.allSatisfy { kind in
                if case .game = kind { return true }
                return false
            }
    }

    /// **Stufe 2 Update (2026-04-30)**: Builder returnt jetzt
    /// **non-Optional** — auch im Jackpot-Fall (3× Game) wird ein
    /// gültiger Context erzeugt, mit leerem `plannedSteps`-Array. Der
    /// Pre-Screen rendert dann die Game-Cards und disabled-CTA. Vorher
    /// returnte `nil` und der Caller fiel still zurück; das war
    /// inkonsistent mit der Stufe-2-Spec „Pre-Screen ist immer der
    /// Übergang nach Slot-Reveal".
    ///
    /// Filtert Game-Slots aus den `plannedSteps` heraus, behält aber
    /// das vollständige Original in `sourceCenterSymbolKinds` für die
    /// End-Summary (Stufe 4) und das Pre-Screen-Layout (Stufe 2 —
    /// Game-Cards werden visuell mit angezeigt).
    ///
    /// **Stufe-3-Spezialfall (5min)**: bei `totalDuration == 5` wird
    /// `plannedSteps` auf max 1 Eintrag begrenzt — Steps 2+ tauchen
    /// nur im End-Summary auf. Stufe-1-Implementierung führt diesen
    /// Cap noch nicht aus; Stufe 3 erweitert die Logik.
    static func make(
        from slotResult: SlotSpinResult,
        totalDuration: Int
    ) -> TrainingChainContext {
        let kinds: [SourceSlotKind] = slotResult.centerSymbols.map { symbol in
            if symbol.isElumi { return .game }
            if let module = symbol.homeModule { return .module(module) }
            // Defensive: unbekannte Slot-Variante (sollte mit aktueller
            // ReelSymbol-Definition nicht vorkommen) → behandeln wie Game,
            // d.h. aus plannedSteps filtern.
            return .game
        }
        let modulesOnly: [HomeHeroModule] = kinds.compactMap { kind in
            if case .module(let m) = kind { return m }
            return nil
        }

        // Bei Jackpot (alle 3 Slots Game) ist `modulesOnly` leer. Der
        // perStepDurationMin-Wert ist in dem Fall semantisch leer →
        // wir setzen 0 als Sentinel. Pre-Screen prüft `isJackpot`/
        // `plannedSteps.isEmpty` bevor er den Wert anzeigt, sodass die
        // 0 nicht durchschlägt. Bei mind. 1 Modul-Slot: gleichmäßige
        // Verteilung der Gesamtdauer.
        let stepsCount = modulesOnly.count
        let perStep = stepsCount > 0 ? max(1, totalDuration / stepsCount) : 0

        return TrainingChainContext(
            id: UUID(),
            plannedSteps: modulesOnly,
            currentIndex: 0,
            perStepDurationMin: perStep,
            sourceCenterSymbolKinds: kinds,
            perStepCount: nil
        )
    }

    /// **Daily Drop Modul 2 (2026-05-23)** — Count-Modus-Factory. Baut
    /// die Chain aus dem Slot-Ergebnis wie `make(from:totalDuration:)`,
    /// aber anzahl-gegatet: kein Timer, `perStepCount` Aufgaben je Step
    /// (even-split). Game-Slots werden wie gehabt aus `plannedSteps`
    /// gefiltert (bleiben in `sourceCenterSymbolKinds`). Der Daily-Drop-
    /// Slot zieht nur Quiz + Vokabeln und füllt Rest-Reels mit Game →
    /// `plannedSteps` enthält die eindeutigen Übungstypen.
    static func make(
        from slotResult: SlotSpinResult,
        perStepCount: Int
    ) -> TrainingChainContext {
        let kinds: [SourceSlotKind] = slotResult.centerSymbols.map { symbol in
            if symbol.isElumi { return .game }
            if let module = symbol.homeModule { return .module(module) }
            return .game
        }
        let modulesOnly: [HomeHeroModule] = kinds.compactMap { kind in
            if case .module(let m) = kind { return m }
            return nil
        }
        return TrainingChainContext(
            id: UUID(),
            plannedSteps: modulesOnly,
            currentIndex: 0,
            perStepDurationMin: 0,
            sourceCenterSymbolKinds: kinds,
            perStepCount: perStepCount
        )
    }

    /// Neuer Context mit `currentIndex + 1` — für Step-Advance.
    /// Wird in Stufe 2 vom CTA-Override-Pattern aufgerufen.
    func advancedToNextStep() -> TrainingChainContext {
        TrainingChainContext(
            id: id,
            plannedSteps: plannedSteps,
            currentIndex: currentIndex + 1,
            perStepDurationMin: perStepDurationMin,
            sourceCenterSymbolKinds: sourceCenterSymbolKinds,
            perStepCount: perStepCount
        )
    }
}
