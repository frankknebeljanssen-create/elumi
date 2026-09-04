import Foundation

/// **Word-Runner-Spawner — Phase 7.4 Spawn-Balancing**.
///
/// Leitgedanke (Spec „Spawn Balancing"):
/// **Jede Welle hat genau einen Typ.** Keine Mischung aus Lernaufgabe
/// und Hindernis in derselben Welle, keine Lern-Option mit Rock-Kollege,
/// kein Pickup neben Blocker. Das sorgt für Klarheit und Lesbarkeit;
/// Schwierigkeit entsteht über Speed + Timing, nicht über Objekt-Dichte.
///
/// Rhythmus (Prioritätsreihenfolge Learning > Hazard > Collectible):
///
///   Wave 0  → hazard    (Warmup)
///   Wave 1  → learning
///   Wave 2  → hazard
///   Wave 3  → learning
///   Wave 4  → collectible  (erster Bonus)
///   Wave 5  → learning
///   Wave 6  → hazard
///   Wave 7  → learning
///   Wave 8  → hazard
///   Wave 9  → power-up (bestehend)
///   Wave 10 → collectible
///   Wave 11 → learning  …
///
/// Regel-Zusammenfassung:
///   • Power-Up: jede 9. Welle (Index > 0)
///   • Collectible: alle 6 Wellen (offset 4, sodass sie nie auf der
///     gleichen Position wie Power-Up landen)
///   • Ungerade Indices: learning
///   • Gerade Indices: hazard
///
/// **Fairness-Invarianten** (Phase 2+):
///   - Hazard-Wellen: max. 2 blockierte Spuren, immer ≥ 1 freie.
///   - Collectible/Power-Up-Wellen: genau 1 Objekt, 2 leere Spuren.
///   - Learning-Wellen: alle 3 Spuren mit Option-Schildern belegt,
///     genau 1 korrekt.
///   - Debug-Asserts über `WordRunnerWave.hasFairPath`.
struct WordRunnerSpawner {

    // MARK: - Intervalle (Spec: 2–3 s zwischen Wellen, keine Überlappung)

    /// **Start-Intervall** zwischen zwei Wellen (Sekunden). Phase 7.4:
    /// Untergrenze angehoben auf 2.3 s (vorher 2.7 s am Start, 1.9 s
    /// am Peak) — klare Welle-zu-Welle-Trennung, kein „Dauer-Stress".
    static let waveIntervalStart: TimeInterval = 2.8
    /// **Plateau-Intervall** nach Ablauf der Difficulty-Ramp.
    /// Nie unter 2.0 s — das ist die Spec-Untergrenze.
    static let waveIntervalPeak: TimeInterval = 2.1
    /// Wie lange die Adaptive-Ramp dauert (60 s).
    static let waveIntervalRampDuration: TimeInterval = 60.0

    /// **Adaptive Wave-Interval** — linear interpoliert von Start auf
    /// Peak über `waveIntervalRampDuration`, danach konstant. Der
    /// Spec-Korridor [2 s … 3 s] wird nie verlassen.
    static func waveInterval(at elapsed: TimeInterval) -> TimeInterval {
        let T = waveIntervalRampDuration
        let v0 = waveIntervalStart
        let vInf = waveIntervalPeak
        if elapsed <= 0 { return v0 }
        if elapsed >= T { return vInf }
        let ratio = elapsed / T
        return v0 + (vInf - v0) * ratio
    }

    /// Backward-compat: Default-Aufrufe ohne `elapsed` bekommen den
    /// Start-Wert. Aktuell unbenutzt — alle Call-Sites geben elapsed
    /// mit. Bleibt für defensive Reads.
    @available(*, deprecated, message: "Use waveInterval(at:) for adaptive difficulty")
    static let waveInterval: TimeInterval = 2.7

    // MARK: - Dependencies

    /// Delivery aus einem Task-Provider (Phase 3).
    /// `nil` → reiner Phase-2-Placeholder-Modus.
    weak var taskProvider: RunnerTaskProvider?

    init(taskProvider: RunnerTaskProvider? = nil) {
        self.taskProvider = taskProvider
    }

    // MARK: - Wave-Pipeline

    /// Baut die nächste Welle für Index `index`.
    ///
    /// Deterministisch bzgl. `index` (Debug-Reproduzierbarkeit),
    /// innerhalb der Muster werden Spur-Wahl, Rock-Variante und
    /// Collectible-Typ zufällig gezogen.
    func makeWave(index: Int, spawnTime: TimeInterval) -> WordRunnerWave {
        let wave: WordRunnerWave = {
            switch waveType(for: index) {
            case .powerUp:
                // Power-Up alterniert: erstes = Schild, zweites = Slow-Mo.
                let powerUpIndex = index / 9
                let kind: WordRunnerPowerUp =
                    powerUpIndex.isMultiple(of: 2) ? .slowMo : .shield
                return makePowerUpWave(kind: kind, spawnTime: spawnTime)

            case .collectible:
                return makeCollectibleWave(index: index, spawnTime: spawnTime)

            case .learning:
                if let task = taskProvider?.nextTask() {
                    let taskStyle: WordRunnerObstacle.Style =
                        (index / 2).isMultiple(of: 2) ? .card : .soft
                    let theme = pickColorTheme(for: index)
                    return WordRunnerWave(
                        task: task,
                        spawnTime: spawnTime,
                        style: taskStyle,
                        colorTheme: theme
                    )
                }
                // Kein Task lieferbar → Fallback auf Hazard, damit der
                // Flow nicht mit einer Lücke pausiert. Kein Placeholder-
                // Choice mehr (strict-Live-Mode respektiert: wenn keine
                // Task da, spielen wir lieber Reaktion als Fremdmaterial).
                return makeHazardWave(spawnTime: spawnTime, index: index)

            case .hazard:
                return makeHazardWave(spawnTime: spawnTime, index: index)
            }
        }()

        #if DEBUG
        assert(wave.hasFairPath,
               "WordRunner-Welle verletzt Fairness-Invariante: \(wave)")
        #endif
        return wave
    }

    // MARK: - Wave-Typ-Ermittlung (Spawn-Balance-Kern)

    /// Welcher Typ kommt als nächstes?
    ///
    /// Prioritäten:
    ///   1. Power-Up (jede 9. Welle, rhythmischer Reward)
    ///   2. Collectible (periodisch, selten)
    ///   3. Learning (alle ungeraden Indices)
    ///   4. Hazard (alle geraden Indices)
    ///
    /// Sorgt für klare Phasen und vermeidet Dauer-Stress: der Spieler
    /// sieht zwischen zwei Lernaufgaben immer eine reine Reaktion
    /// (Hazard/Collectible), nie zwei Tasks hintereinander ohne
    /// „Atempause".
    private func waveType(for index: Int) -> WaveType {
        if index > 0 && index % 9 == 0 { return .powerUp }
        if index > 0 && index % 6 == 4 { return .collectible }
        return index.isMultiple(of: 2) ? .hazard : .learning
    }

    /// Rotiert über die vier Farbwelten (Türkis/Gold/Violett/Koralle).
    /// Phase-7.4: keine zwei direkt aufeinanderfolgenden Lern-Wellen
    /// teilen sich dieselbe Palette → Abwechslung auch wenn der
    /// Spieler viele Tasks hintereinander sieht.
    private func pickColorTheme(for index: Int) -> WordRunnerColorTheme {
        let themes = WordRunnerColorTheme.allCases
        return themes[(index / 2) % themes.count]
    }

    // MARK: - Hazard-Wave (Spec 5: max 2 belegt, immer 1 frei)

    /// Klassische Reaktions-Welle: 2 Hindernisse + 1 freie Spur.
    /// Freie Spur randomisiert, Hindernis-Form alterniert zwischen
    /// STOP-Schild (`.blocker`) und Felsen (`.rock`) — beide gleich
    /// tödlich, Felsen sind über den Jump überwindbar (siehe
    /// `WordRunnerGame.tick`).
    ///
    /// Style-Rotation (nur `.blocker`): Gap-Wellen alternieren
    /// zwischen `.block` (hart eckig) und `.rounded` (weicher) —
    /// rein visuelle Abwechslung.
    private func makeHazardWave(spawnTime: TimeInterval, index: Int) -> WordRunnerWave {
        let lanes = WordRunnerLane.allCases
        let style: WordRunnerObstacle.Style =
            (index / 2).isMultiple(of: 2) ? .block : .rounded

        // **Pattern-Rotation (Phase 7.6)** — 5 Layouts, deterministisch
        // per `index` ausgewählt. Das verhindert, dass die Hazard-
        // Wellen sich wie zufällig gleiche Konfigurationen anfühlen.
        //
        //   A  Block · frei  · Block         (Mitte frei)
        //   B  Block · Block · frei          (rechts frei)
        //   C  Block · frei  · frei          (nur links Block — entspannt)
        //   D  frei  · Block · Block         (links frei)
        //   E  frei  · Block · frei          (nur Mitte Block — entspannt)
        //
        // Hazard-Index (index/2, da Hazard jede 2. Welle ist) mod 5
        // rotiert durch die Patterns. Kein echter Zufall — bleibt
        // Replay-deterministisch.
        let patternIndex = (index / 2) % 5
        let blockedLanes: [WordRunnerLane] = {
            switch patternIndex {
            case 0: return [.left, .right]           // A
            case 1: return [.left, .center]          // B
            case 2: return [.left]                   // C
            case 3: return [.center, .right]         // D
            default: return [.center]                // E
            }
        }()

        // **Hindernis-Varianten-Mix (Phase 7.6)**: Rocks · STOP · Baustelle
        // rotieren ebenfalls über `index`. Die drei sind gameplay-
        // identisch (alle fatal + via Jump überspringbar), variieren
        // nur visuell.
        let kindCycle = (index / 2) % 4
        let obstacles: [WordRunnerObstacle] = blockedLanes.map { lane in
            switch kindCycle {
            case 0:
                let variant = (lane.rawValue + index) % Self.rockVariantCount
                return WordRunnerObstacle(lane: lane, kind: .rock(variant: variant), style: style)
            case 1:
                return WordRunnerObstacle(lane: lane, kind: .blocker, style: style)
            case 2:
                return WordRunnerObstacle(lane: lane, kind: .construction, style: style)
            default:
                // Gemischte Welle: STOP + Baustelle, mit Lane-Parität
                // als Trenner — sieht visuell interessanter aus.
                let kind: WordRunnerObstacle.Kind = (lane.rawValue.isMultiple(of: 2))
                    ? .blocker
                    : .construction
                return WordRunnerObstacle(lane: lane, kind: kind, style: style)
            }
        }

        return WordRunnerWave(
            spawnTime: spawnTime,
            prompt: nil,
            contextLine: nil,
            obstacles: obstacles,
            type: .hazard
        )
    }

    /// Anzahl der Rock-Shape-Varianten. Muss mit der View
    /// (`RockObstacleView`) synchron bleiben.
    static let rockVariantCount = 5

    // MARK: - Power-Up-Wave

    /// Pickup-Welle: ein Power-Up auf einer zufälligen Spur, **alle
    /// anderen Spuren leer**. 3 freie Pfade, Pickup ist optional.
    private func makePowerUpWave(kind: WordRunnerPowerUp, spawnTime: TimeInterval) -> WordRunnerWave {
        let lane = WordRunnerLane.allCases.randomElement()!
        let pickup = WordRunnerObstacle(lane: lane, kind: .powerUp(kind))
        return WordRunnerWave(
            spawnTime: spawnTime,
            prompt: nil,
            contextLine: nil,
            obstacles: [pickup],
            type: .powerUp
        )
    }

    // MARK: - Collectible-Wave (Phase 7.4)

    /// Sammelobjekt-Welle: **genau 1** Collectible auf einer Spur,
    /// zwei Spuren leer. Typ alterniert je nach `index`:
    ///   • index % 3 == 0 → Seestern
    ///   • index % 3 == 1 → Würmchen
    ///   • index % 3 == 2 → Perle (selten, aber nicht rarer als die
    ///     anderen, weil die Collectible-Welle selbst schon selten ist)
    ///
    /// Collectibles spawnen nur in reinen Collectible-Wellen — sie
    /// treten nie gleichzeitig mit Lernaufgaben oder Hindernissen
    /// auf (Spec 6: „nicht gleichzeitig mit Lernaufgaben").
    private func makeCollectibleWave(index: Int, spawnTime: TimeInterval) -> WordRunnerWave {
        let lane = WordRunnerLane.allCases.randomElement()!
        let collectibleIndex = (index / 6) % 3
        let kind: WordRunnerCollectible = {
            switch collectibleIndex {
            case 0:  return .starfish
            case 1:  return .worm
            default: return .pearl
            }
        }()
        let obstacle = WordRunnerObstacle(lane: lane, kind: .collectible(kind))
        return WordRunnerWave(
            spawnTime: spawnTime,
            prompt: nil,
            contextLine: nil,
            obstacles: [obstacle],
            type: .collectible
        )
    }
}
