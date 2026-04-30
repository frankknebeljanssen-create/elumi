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

    /// Builder aus dem Slot-Ergebnis. Filtert Game-Slots aus den
    /// `plannedSteps` heraus, behält aber das vollständige Original
    /// in `sourceCenterSymbolKinds` für die End-Summary (Stufe 4).
    ///
    /// **Stufe-3-Spezialfall (5min)**: bei `totalDuration == 5` wird
    /// `plannedSteps` auf max 1 Eintrag begrenzt — Steps 2+ tauchen
    /// nur im End-Summary auf. Stufe-1-Implementierung führt diesen
    /// Cap noch nicht aus; Stufe 3 erweitert die Logik.
    ///
    /// **Jackpot-Pfad (3× Game)**: alle Slots sind `.elumi` → Filter
    /// liefert leeres `plannedSteps`-Array → Builder gibt `nil` zurück.
    /// Caller (ElumiTabView) erkennt `nil` und triggert in Stufe 5 die
    /// Jackpot-UI statt Chain-Navigation.
    static func make(
        from slotResult: SlotSpinResult,
        totalDuration: Int
    ) -> TrainingChainContext? {
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
        // Wenn alle 3 Slots Game waren (Jackpot-Pfad), gibt's keine
        // Chain — Caller (ElumiTabView) erkennt das via `nil`-Return
        // und fährt den Jackpot-Pfad (Stufe 5).
        guard !modulesOnly.isEmpty else { return nil }

        let stepsCount = modulesOnly.count
        let perStep = max(1, totalDuration / stepsCount)
        return TrainingChainContext(
            id: UUID(),
            plannedSteps: modulesOnly,
            currentIndex: 0,
            perStepDurationMin: perStep,
            sourceCenterSymbolKinds: kinds
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
            sourceCenterSymbolKinds: sourceCenterSymbolKinds
        )
    }
}
