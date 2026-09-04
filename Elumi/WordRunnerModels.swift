import Foundation
import CoreGraphics

// MARK: - Run State (Phase 2)

/// Zentrales Zustands-Enum für den Word-Runner-Gesamtlauf.
///
/// Bewusst ein Enum statt loser Booleans (`isRunning`, `isGameOver`,
/// `isPaused`). Jeder illegale Zustand wird dadurch am Typ erkennbar
/// statt später in verstreuten Flag-Kombinationen.
///
/// **Phase-2-Set**: `idle`, `running`, `gameOver(reason:)`.
/// **Phase-3+ Platzhalter**: `paused`, `finished(summary:)` sind als
/// Kommentar angedeutet — einfügen, sobald eine echte Session-Logik
/// lebt (nicht vorher, damit exhaustive `switch`-Statements nicht
/// leere Cases mitschleppen müssen).
enum WordRunnerRunState: Equatable {
    case idle
    case running
    case gameOver(reason: GameOverReason)
    /// **Phase 4**: Summary nach abgeschlossenem Run. Payload kommt
    /// nicht mit ins Enum rein (SessionRewardOutcome ist nicht
    /// Equatable), die View liest `WordRunnerGame.pendingOutcome`.
    case summary
    // case paused // Phase 4+

    enum GameOverReason: Equatable {
        case hitBlocker
        case wrongChoice
    }

    var isRunning: Bool {
        if case .running = self { return true }
        return false
    }

    var isGameOver: Bool {
        if case .gameOver = self { return true }
        return false
    }

    var isSummary: Bool {
        if case .summary = self { return true }
        return false
    }
}

// MARK: - Lane

/// Drei feste Spuren. `Int`-Raw-Value, damit ±1-Arithmetik am Rand
/// sauber clampen kann (siehe `WordRunnerGame.moveLane(by:)`).
enum WordRunnerLane: Int, CaseIterable, Equatable, Hashable {
    case left = 0, center = 1, right = 2

    /// X-Anteil der Screen-Breite in **Spielerzone** (z=1).
    ///
    /// Phase 6.5: **0.18 / 0.50 / 0.82** → Track ist nun ~64 % der
    /// Screen-Breite (Spec: „Strecke = Hauptfokus, 60–70 %").
    /// Spuren haben mehr Abstand untereinander (bessere Lesbarkeit,
    /// weniger gequetschter Eindruck), links + rechts bleiben
    /// trotzdem je ~18 % für Welt/Mittelgrund.
    var xFraction: CGFloat {
        switch self {
        case .left:   return 0.18
        case .center: return 0.50
        case .right:  return 0.82
        }
    }
}

// MARK: - Obstacle (Phase 2 + 3)

/// Ein einzelnes Objekt auf einer Spur.
///
/// Zwei Kinds, bewusst schlank gehalten:
///
///   • `.blocker` — immer tödlich. Pure Reaktion, keine Entscheidung.
///
///   • `.option(label:isCorrect:)` — trägt ein kurzes Label (z. B.
///     „le", „vais", oder in Phase-2-Placeholder-Waves schlicht
///     „A"/„B"/„C"). Tödlich, wenn `isCorrect == false`. Die
///     Korrektheit wird extern bestimmt (Seed-Task in Phase 3, oder
///     Pseudo-Zufall in Phase-2-Placeholder-Modus).
///
/// `y`-Position wird nie persistiert — die View berechnet sie live
/// aus `WordRunnerWave.spawnTime` × Scroll-Speed. Das hält das Modell
/// deterministisch und drift-frei.
struct WordRunnerObstacle: Identifiable, Equatable {
    let id: UUID
    let lane: WordRunnerLane
    let kind: Kind
    /// **Phase 5** — rein visueller Stil. Gameplay-agnostisch: der
    /// Runner interpretiert Style nicht, die View wählt auf Basis
    /// davon eine andere Render-Variante (harte Kante vs. runde
    /// Card vs. halbtransparent). Das reduziert visuelle
    /// Monotonie ohne dass Wellen schwerer zu lesen werden.
    let style: Style

    enum Kind: Equatable {
        case blocker
        /// **Baustelle** — visuelle Variante zum STOP-Schild (Phase 7.6).
        /// Gameplay identisch tödlich + via Jump überspringbar; nur
        /// Rendering unterscheidet sich (oranges Dreieck-Schild mit
        /// SF-Symbol). Vergrößert die visuelle Vielfalt bei Hazard-
        /// Wellen, ohne neue Mechanik.
        case construction
        case option(label: String, isCorrect: Bool)
        /// **Felsen** — visuelle Variante zum STOP-Schild. Gameplay
        /// identisch tödlich, lediglich anderes Render-Format.
        /// Der `variant`-Index wählt aus den 5 Rock-Shape-Varianten
        /// (Phase 7.4: visuelle Vielfalt). View-only; der Spawner
        /// setzt den Wert aus einem seeded Zufall pro Rock.
        case rock(variant: Int)
        /// **Power-Up Pickup** — beim Drüberfahren wird der Effekt
        /// aktiviert, das Obstacle ist **nicht** tödlich.
        case powerUp(WordRunnerPowerUp)
        /// **Sammelobjekt** (Phase 7.4) — beim Drüberfahren gibt's
        /// Score/Counter-Bonus, nicht tödlich. Kommt **nie** in der
        /// gleichen Welle wie Lernaufgaben oder Hindernisse vor
        /// (siehe Spawner-Balance-Regeln).
        case collectible(WordRunnerCollectible)
    }

    enum Style: Equatable, CaseIterable {
        /// Harte Kante, kräftige Farbe, eckig.
        case block
        /// Abgerundete Ecken, weiche Haptik.
        case rounded
        /// Card-Look mit Akzent-Border und Schatten.
        case card
        /// Halbtransparent, dezenter — Kontrast-Variation zum Rest.
        case soft
    }

    init(id: UUID = UUID(), lane: WordRunnerLane, kind: Kind, style: Style = .rounded) {
        self.id = id
        self.lane = lane
        self.kind = kind
        self.style = style
    }

    /// Kollision → Game-Over? Zentral hier, damit View + Game-VM
    /// dieselbe Logik benutzen und niemand woanders eine
    /// Duplicate-Regel einbaut.
    var isFatalOnHit: Bool {
        switch kind {
        case .blocker:      return true
        case .construction: return true
        case .rock:         return true
        case .option(_, let isCorrect): return !isCorrect
        case .powerUp:      return false
        case .collectible:  return false
        }
    }

    /// Convenience — nur für `.rock`-Kollisionsprüfung des Jump-
    /// Skips. Lässt sich ohne associated-value-Match bequem lesen.
    var isRock: Bool {
        if case .rock = kind { return true }
        return false
    }

    /// Convenience — STOP-Blocker, ebenfalls über Jump überspringbar
    /// (User-Wunsch „springen über stopschild muss möglich sein").
    /// Phase 7.6: Baustelle verhält sich identisch zum STOP-Schild.
    var isBlocker: Bool {
        switch kind {
        case .blocker, .construction: return true
        default:                       return false
        }
    }

    /// Kann per Jump übersprungen werden? Aktuell: Felsen + STOP-
    /// Schilder + Baustellen. Option-Schilder, Power-Ups und
    /// Collectibles werden bewusst **nicht** umgangen — dort
    /// passiert die Entscheidungs- oder Einsammel-Mechanik.
    var isJumpable: Bool {
        return isRock || isBlocker
    }
}

/// **Sammelobjekt-Typen** (Phase 7.4).
///
/// Alle Collectibles spawnen nie gleichzeitig mit Lernaufgaben und
/// nie mehr als einer pro Welle (Spawn-Balance-Spec). Die
/// `scoreBonus`-Werte sind entkoppelt von XP — XP läuft über
/// `ProgressService`; der Runner führt einen eigenen lokalen Score
/// und einen Collectible-Counter für Summary-Analytics.
enum WordRunnerCollectible: Equatable {
    /// **Seestern** — klassischer Score-Boost, glänzend, rotiert leicht.
    case starfish
    /// **Würmchen** — kleiner Counter-Bonus, „gesammelt: X".
    case worm
    /// **Perle** — selten, großer Score-Boost. (Optional; vom Spawner
    /// bei Bedarf verwendet.)
    case pearl

    var scoreBonus: Int {
        switch self {
        case .starfish: return 25
        case .worm:     return 10
        case .pearl:    return 60
        }
    }

    /// Zählt das Item in der Collectibles-Statistik mit? Pearl +
    /// Starfish ja; Worm auch (alle Sammelobjekte werden gezählt).
    var isCountedCollectible: Bool {
        return true
    }

    /// Deutscher Display-Name für das Pickup-Pop-up.
    var displayName: String {
        switch self {
        case .starfish: return "Seestern"
        case .worm:     return "Würmchen"
        case .pearl:    return "Perle"
        }
    }

    /// SF-Symbol-Name fürs Pop-up-Icon. Bewusst generisch gewählt,
    /// damit kein Asset-Import nötig ist — nur der in-game
    /// `CollectibleView` baut die echten Shapes.
    var iconSystemName: String {
        switch self {
        case .starfish: return "star.fill"
        case .worm:     return "scribble"
        case .pearl:    return "circle.fill"
        }
    }
}

/// Power-Up-Typ. Aktuell nur Schild — weitere Effekte (Slow-Mo,
/// Multi-Combo, Bonus-Score) lassen sich hier später ergänzen,
/// ohne dass Spawner/View-Pipeline angefasst werden muss.
enum WordRunnerPowerUp: Equatable {
    /// Absorbiert genau **einen** nächsten fatalen Treffer (Blocker,
    /// Felsen oder falsche Option). Stapelbar — mehrere Schilde
    /// werden hintereinander aufgebraucht.
    case shield
    /// **Zeitlupe** — die Welt bewegt sich für eine begrenzte Dauer
    /// langsamer. Spieler-Input bleibt voll responsiv, der visuelle
    /// + Kollisions-Clock skaliert mit `slowMoFactor` (z. B. 0.55).
    /// Mehrfach-Pickup verlängert die laufende Phase.
    case slowMo
}

// MARK: - Wave

/// Eine Welle = gemeinsam spawnende Objekte + (optional) ein Prompt
/// oben am Screen.
///
/// Wave ist die **Task-Einheit** des Runners:
///   • Gap-Wave: `prompt == nil`, 2 Blocker + 1 freie Spur
///   • Task-Wave: `prompt != nil`, 3 Optionen auf allen 3 Spuren
///
/// Alle Objekte einer Wave teilen denselben `spawnTime` (Sekunden seit
/// Run-Start) — damit ist ihre `y`-Position mit **einer** Formel aus
/// Scroll-Speed × Delta-Time berechenbar, kein Per-Objekt-State.
struct WordRunnerWave: Identifiable, Equatable {
    let id: UUID
    let spawnTime: TimeInterval
    let prompt: String?
    /// Optionaler Kontext (z. B. „je ___ aller" bei Verb-Tasks).
    /// Klein gerendert unter dem Prompt.
    let contextLine: String?
    let obstacles: [WordRunnerObstacle]
    /// **Wave-Type** (Phase 7.4 — Spawn-Balance). Jede Welle hat genau
    /// **einen** Typ; der Spawner respektiert Prioritäten
    /// (Learning > Hazard > Collectible). Die View nutzt das Feld für
    /// Visual-Priorität (z. B. Prompt nur bei `.learning`), der VM
    /// für Balancing-Asserts.
    let type: WaveType
    /// **Farbwelt** (Phase 7.4) — nur für Task-Wellen relevant. Jede
    /// Lernaufgabe bekommt eine von vier Paletten (Türkis/Gold/Violett/
    /// Koralle), damit aufeinanderfolgende Tasks visuell
    /// unterschiedlich aussehen. Andere Welle-Typen setzen das auf
    /// `.turquoise` (wird dort ohnehin nicht gelesen).
    let colorTheme: WordRunnerColorTheme

    init(
        id: UUID = UUID(),
        spawnTime: TimeInterval,
        prompt: String? = nil,
        contextLine: String? = nil,
        obstacles: [WordRunnerObstacle],
        type: WaveType = .hazard,
        colorTheme: WordRunnerColorTheme = .turquoise
    ) {
        self.id = id
        self.spawnTime = spawnTime
        self.prompt = prompt
        self.contextLine = contextLine
        self.obstacles = obstacles
        self.type = type
        self.colorTheme = colorTheme
    }

    /// **Fairness-Invariante**: gibt es mindestens einen sicheren Weg?
    /// Wird in Spawner + ViewModel in Debug-Asserts geprüft.
    var hasFairPath: Bool {
        // Eine Spur ist „sicher", wenn sie entweder
        //   (a) gar nicht belegt ist, oder
        //   (b) mit einer korrekten Option belegt ist, oder
        //   (c) mit einem nicht-fatalen Pickup/Collectible belegt ist.
        let occupied = Set(obstacles.map { $0.lane })
        let free = WordRunnerLane.allCases.filter { !occupied.contains($0) }
        if !free.isEmpty { return true }
        return obstacles.contains { obs in
            switch obs.kind {
            case .option(_, let isCorrect): return isCorrect
            case .powerUp, .collectible:    return true
            case .blocker, .construction, .rock: return false
            }
        }
    }
}

/// **Wave-Type-Klassifikation** (Phase 7.4 — Spawn-Balance). Jede
/// erzeugte Welle trägt genau einen Typ; der Spawner darf Typen
/// nicht mischen.
enum WaveType: Equatable, CaseIterable {
    /// Lernaufgabe: 3 Option-Schilder, 1 fachlich korrekt. Keine
    /// Rocks/STOPs/Collectibles in der Welle.
    case learning
    /// Reine Dodge-Welle: 2 Hindernisse + 1 freier Pfad. Keine Tasks,
    /// keine Pickups, keine Collectibles.
    case hazard
    /// Sammelobjekt-Welle: 1 Collectible auf einer Spur, zwei leere
    /// Spuren. Optional, tritt seltener auf als Lern- oder Hindernis-
    /// Wellen.
    case collectible
    /// Power-Up-Welle: 1 Schild-/Slow-Mo-Pickup. Alle anderen Spuren
    /// frei (bestehende Phase-5-Mechanik).
    case powerUp
}

/// **Farbwelten für Lernaufgaben** (Phase 7.4). Jede Task-Welle
/// bekommt eine davon; View liest `primary` + `deep` für das
/// Schild-Gradient, die Prompt-Card und den Boden-Schatten.
///
/// Bewusst **keine Rot/Grün-Semantik** — die Farbe sagt nichts über
/// richtig/falsch, nur über die visuelle Abwechslung zwischen Aufgaben.
enum WordRunnerColorTheme: Equatable, CaseIterable {
    case turquoise
    case warmGold
    case violetBlue
    case coral

    /// RGB-Hex der Hauptfarbe (oberer Gradient-Stopp auf dem Schild).
    var primaryHex: String {
        switch self {
        case .turquoise:  return "#2FBCB0"   // Türkis/Petrol
        case .warmGold:   return "#E4B05C"   // warmes Gold
        case .violetBlue: return "#6B66C9"   // Violett/Blau
        case .coral:      return "#E87A5C"   // Koralle
        }
    }

    /// Dunkler Gradient-Stopp (Rahmen-Außen, Gradient-Unten).
    var deepHex: String {
        switch self {
        case .turquoise:  return "#1C7E78"
        case .warmGold:   return "#A47A2F"
        case .violetBlue: return "#443F8E"
        case .coral:      return "#A84B35"
        }
    }
}

// MARK: - RunnerTask (Phase 3)

/// Kategorie einer Lernaufgabe. Zusätzliche Kategorien werden später
/// hier angehängt (Konjugation erweitert, Adjektiv-Anpassung, …);
/// der Runner selbst kennt die Kategorie nur als Label und Farbe.
enum RunnerTaskCategory: String, Equatable, CaseIterable {
    case article
    case verbForm

    var displayLabel: String {
        switch self {
        case .article:  return "Artikel"
        case .verbForm: return "Verbform"
        }
    }
}

/// Saubere zentrale Aufgabenstruktur (Phase 3).
///
/// Die View baut **nie** UI direkt aus Rohdaten — sie erwartet eine
/// fertige `RunnerTask`. Das hält die Content-Erzeugung (was ist eine
/// gute Frage?) räumlich getrennt vom Rendering (wie wird sie
/// angezeigt?).
///
/// `options.count` muss `WordRunnerLane.allCases.count` (= 3) sein,
/// weil jede Spur genau eine Option trägt. `correctIndex` ist der
/// Index in `options` — nicht die Spur-Enum-Zahl, sondern die
/// Reihenfolge, in der die Optionen auf die Spuren left/center/right
/// gemappt werden (siehe `WordRunnerWave.init(task:spawnTime:)`).
struct RunnerTask: Equatable, Identifiable {
    var id = UUID()
    let category: RunnerTaskCategory
    let prompt: String
    let options: [String]
    let correctIndex: Int
    let contextLine: String?

    var correctOption: String { options[correctIndex] }

    init(
        id: UUID = UUID(),
        category: RunnerTaskCategory,
        prompt: String,
        options: [String],
        correctIndex: Int,
        contextLine: String? = nil
    ) {
        self.id = id
        self.category = category
        self.prompt = prompt
        self.options = options
        self.correctIndex = correctIndex
        self.contextLine = contextLine
    }

    /// Basic-Validierung: genau 3 Optionen, `correctIndex` in Range,
    /// keine leeren Strings. Der `TaskProvider` ruft das vor Ausgabe
    /// auf — damit keine kaputte Aufgabe den Runner erreicht.
    var isWellFormed: Bool {
        guard options.count == WordRunnerLane.allCases.count else { return false }
        guard options.indices.contains(correctIndex) else { return false }
        guard !prompt.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return options.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

extension WordRunnerWave {
    /// Konvertiert eine `RunnerTask` in eine Task-Wave. Options
    /// werden in Reihenfolge auf `left → center → right` gemappt.
    /// Innerhalb einer Task-Welle haben **alle 3 Options denselben
    /// Style** — sonst wäre der Spieler visuell abgelenkt (eine
    /// Card und zwei Blocks zu lesen ist unnötig kognitiv teuer).
    ///
    /// Erwartet eine well-formed Task (per `isWellFormed` geprüft) —
    /// in Debug-Builds wird das asserted, damit fehlerhafte
    /// Task-Generatoren früh auffallen.
    init(
        task: RunnerTask,
        spawnTime: TimeInterval,
        style: WordRunnerObstacle.Style = .card,
        colorTheme: WordRunnerColorTheme = .turquoise
    ) {
        #if DEBUG
        assert(task.isWellFormed, "RunnerTask nicht well-formed: \(task)")
        #endif
        let lanes = WordRunnerLane.allCases
        let obstacles = zip(lanes, task.options.indices).map { lane, idx in
            WordRunnerObstacle(
                lane: lane,
                kind: .option(
                    label: task.options[idx],
                    isCorrect: idx == task.correctIndex
                ),
                style: style
            )
        }
        self.init(
            spawnTime: spawnTime,
            prompt: task.prompt,
            contextLine: task.contextLine,
            obstacles: obstacles,
            type: .learning,
            colorTheme: colorTheme
        )
    }
}
