import Foundation
import SwiftUI
import CoreGraphics

/// **ViewModel des Word-Runners (Phase 2 + 3)**.
///
/// Trennt strikt:
///   • **Zustand + Transitions** (diese Klasse)
///   • **Rendering**             (`WordRunnerGameView`)
///   • **Content-Erzeugung**     (`RunnerTaskProvider` + `WordRunnerSpawner`)
///
/// Warum MainActor-ObservableObject statt `@State`-Sammlung in der
/// View? Weil wir hier vier Dinge gleichzeitig tun müssen:
///   1. Obstacle-Pool mutieren (Spawn + Cleanup)
///   2. Run-State-Übergänge bei Kollision
///   3. Async-Spawn-Loop parallel zum Rendering laufen lassen
///   4. Tick-basierte Kollisionserkennung aus der View konsumieren
///
/// All das in der View mit `@State` + Tasks landen zu lassen würde
/// Race-Conditions zwischen Body-Rebuilds und Spawns einladen. Die
/// ObservableObject-Grenze macht die Seiteneffekte an **einer** Stelle
/// konzentriert und damit testbar.
@MainActor
final class WordRunnerGame: ObservableObject {

    // MARK: - Published State (Single Source of Truth)

    @Published private(set) var runState: WordRunnerRunState = .idle
    @Published private(set) var currentLane: WordRunnerLane = .center
    @Published private(set) var waves: [WordRunnerWave] = []

    // MARK: - Feedback-Signale (Phase 3.5)
    //
    // Diese Felder sind **bewusst** Datums-basiert, nicht Counter:
    // die View kann mit `Date().timeIntervalSince(lastCorrectAt)` eine
    // Lebensdauer (z. B. 0.4 s Lane-Highlight) berechnen und
    // gleichzeitig via `@Published`-Änderung einen Render-Frame
    // triggern, ohne dass wir einen eigenen Timer brauchen.

    /// Zeitpunkt der letzten korrekten Entscheidung (Option in Spieler-
    /// Spur war `isCorrect: true`). View lässt darauf einen Lane-
    /// Highlight kurz aufleuchten.
    @Published private(set) var lastCorrectFeedbackAt: Date?
    @Published private(set) var lastCorrectLane: WordRunnerLane?

    /// Zeitpunkt des letzten Fehlers / Blocker-Treffers. View zeigt
    /// einen kurzen Screen-Flash + Sprite-Squash — *bevor* das
    /// Game-Over-Overlay erscheint (Delay über `showGameOverOverlay`).
    @Published private(set) var lastWrongFeedbackAt: Date?

    // MARK: - Session-Tracking (Phase 4)
    //
    // Zählen für die `LearningSession`, die wir am Run-Ende an den
    // zentralen `ProgressService` übergeben. **Keine** eigene XP-Logik
    // hier — die Werte sind reine Counter, XP/Credits/Streak werden
    // vom Service berechnet (gleiche Pipeline wie Quiz/Training).

    /// Korrekte Antworten (Option mit `isCorrect: true` unter Spieler
    /// passiert).
    @Published private(set) var correctAnswers: Int = 0

    /// Falsche Antworten (Option mit `isCorrect: false` + Blocker
    /// getroffen). Aktuell max. 1 pro Run, weil jede falsche Antwort
    /// zum Game-Over führt — Struktur ist trotzdem Counter, damit
    /// spätere „Lives"-Mechaniken ohne API-Bruch passen.
    @Published private(set) var wrongAnswers: Int = 0

    /// Längste Correct-Combo. Triggert den `comboXP`-Bonus im
    /// `SessionRewardOutcome` (alle 5 = +15 XP). Bei jedem Wrong-Hit
    /// zurück auf 0 — im Runner nur relevant, wenn später Combo-
    /// fortsetzende Hits eingebaut werden.
    @Published private(set) var longestCombo: Int = 0
    /// Aktuelle Combo (wird nach Wrong-Hit auf 0 gesetzt). Published,
    /// damit die View Mini-Ziele („3 in Folge!"-Badge) rendern kann.
    @Published private(set) var currentCombo: Int = 0

    /// Dauer des aktuellen Runs (nur informativ; ProgressService
    /// verarbeitet sie nicht, aber wir loggen sie in Debug + können
    /// sie später in Summary-Erweiterungen zeigen).
    var runDuration: TimeInterval {
        guard runState != .idle else { return 0 }
        return Date().timeIntervalSince(runStart)
    }

    /// **Phase-4-Ergebnis**: Wird im Moment des Game-Overs via
    /// `ProgressService.shared.record(session:)` erzeugt und hier
    /// abgelegt. Die View liest das Feld, sobald `runState == .summary`.
    /// `nil` zwischen Runs.
    @Published private(set) var pendingOutcome: SessionRewardOutcome?

    /// Wird auf `true` gesetzt **~0.6 s nach** `runState = .gameOver`,
    /// danach wechselt die Machine auf `.summary`. In den 0.6s davor
    /// sehen Spieler den eingefrorenen Crash-Moment + Wrong-Flash.
    @Published private(set) var showGameOverOverlay: Bool = false

    /// Wird beim ersten Spawn nach `start()` auf true gekippt. Solange
    /// false, zeigt die View ein kurzes „Bereit"-Gefühl (Figur +
    /// Stripes laufen schon, aber keine Hindernisse). Verhindert
    /// den Kaltstart-Effekt, in dem sofort ein Obstacle erscheint.
    @Published private(set) var hasSpawnedFirstWave: Bool = false

    /// Welche Obstacles haben wir schon als „korrekt passiert"
    /// getriggert? Verhindert mehrfach-Triggern im Hit-Window UND
    /// dient der View als Quelle für „Schild bleibt grün, nachdem
    /// Spieler durchgefahren ist" (Phase Green-Pass).
    @Published private(set) var consumedCorrectIDs: Set<UUID> = []

    /// Analog für bereits „getroffene" fatale Obstacles im Lives-
    /// Modus. Ohne das würde derselbe Blocker im Hit-Window alle
    /// 3 Leben auf einmal ziehen.
    private var consumedWrongIDs: Set<UUID> = []

    // MARK: - Lives + Score (Phase 5)
    //
    // Leben ersetzen das bisherige „ein Wrong = sofort Game Over"-
    // Modell. Der Runner fühlt sich dadurch vergebender an und gibt
    // dem Spieler Raum, zwischen Aufgaben zu lernen (statt nach dem
    // ersten Fehler neu zu starten).

    /// Start-Leben pro Run. Bei 0 → `enterGameOver(reason: .wrongChoice)`.
    ///
    /// **Quick-Fix 2026-04-30 (`v2-elumi-gameover-cta-home`)** — von
    /// 3 auf 4 erhöht, damit Word Runner mit der gleichen Lebens-
    /// Anzahl wie das Elumi-Spiel startet (`ElumiArcadeGameView.maxMisses
    /// == 4`). User-Spec: „word runner muss beim start auch 4 leben
    /// haben (nicht nur 3) elumi hats auch".
    static let startingLives = 4

    @Published private(set) var lives: Int = startingLives

    /// Kumulierter Score. +10 pro korrekter Antwort (Phase 5), keine
    /// XP-Bindung — XP fließen zentral über ProgressService.
    @Published private(set) var score: Int = 0

    /// Zeitstempel des letzten Leben-Verlusts. View rendert darauf
    /// ein „1 Leben verloren"-Badge (Phase-5-Spec „Life Loss Feedback").
    @Published private(set) var lastLifeLostAt: Date?

    /// **Phase 7.4 — Sammelobjekte**.
    ///
    /// - `collectiblesGathered` zählt ALLE eingesammelten Collectibles
    ///   (Seestern + Würmchen + Perle) und wird in der Summary als
    ///   „Gesammelt: X" angezeigt.
    /// - `lastCollectiblePickupAt` triggert ein kleines Glanz-Pulse-
    ///   Feedback auf dem Spieler.
    /// - `lastCollectiblePickupKind` enthält den **Typ** des zuletzt
    ///   eingesammelten Items — die View rendert darauf ein Pop-up
    ///   mit Icon + Score-Bonus („+25 Seestern"). Wird nicht
    ///   zurückgesetzt; die View entscheidet via Zeitabstand zu
    ///   `lastCollectiblePickupAt`, ob das Pop-up noch sichtbar ist.
    @Published private(set) var collectiblesGathered: Int = 0
    @Published private(set) var lastCollectiblePickupAt: Date?
    @Published private(set) var lastCollectiblePickupKind: WordRunnerCollectible?

    // Per-Typ-Counter (Phase 7.6+): die HUD zeigt die drei Collectible-
    // Typen jetzt einzeln, damit der Spieler sieht, was genau er
    // gesammelt hat — nicht nur die Summe. `collectiblesGathered`
    // bleibt als Summe erhalten (wird von Summary + Legacy-Pfaden
    // konsumiert).
    @Published private(set) var collectedStarfish: Int = 0
    @Published private(set) var collectedWorm: Int = 0
    @Published private(set) var collectedPearl: Int = 0

    /// **Power-Up: Schild-Charges**. Jeder Charge absorbiert genau
    /// einen fatalen Treffer (Blocker, Felsen, falsche Option).
    /// View zeigt eine Schild-Aura um das Vehikel, solange `> 0`.
    @Published private(set) var shieldCharges: Int = 0

    /// **Power-Up: Slow-Mo State**.
    /// `slowMoEndsAt` = Wall-Clock-Zeitpunkt, an dem die aktuelle
    /// Slow-Mo-Phase endet (`nil` = aktuell keine).
    /// `accumulatedSlowMoLag` = Summe aller bereits abgelaufenen
    /// Slow-Mo-Verzögerungen (in Sekunden Welt-Zeit).
    /// `slowMoStartedAt` = Wall-Clock-Start der **aktuellen** Phase
    /// (`nil` falls keine aktiv) — Math nutzt das + endsAt, um den
    /// laufenden Lag-Beitrag zu rechnen.
    @Published private(set) var slowMoEndsAt: Date?
    private(set) var accumulatedSlowMoLag: TimeInterval = 0
    private var slowMoStartedAt: Date?

    /// Slow-Mo-Faktor: 0.55 = Welt zieht mit 55 % der normalen
    /// Geschwindigkeit. Spieler-Input bleibt 1:1.
    static let slowMoFactor: TimeInterval = 0.55
    /// Standard-Dauer pro Pickup.
    static let slowMoDuration: TimeInterval = 4.0

    // Vertikal-Drag-Speed-Control-Properties liegen weiter unten im
    // File (`userSpeedMultiplier`, `accumulatedUserTimeBias`,
    // `userSpeedMin/Max`) — Phase 7.6 Feature bereits implementiert.

    // MARK: - User Speed Control (Vertikal-Drag)
    //
    // User zieht in der View vertikal am Spielfeld:
    //   • Drag UP    → `userSpeedMultiplier` > 1  → Welt scrollt schneller
    //   • Drag DOWN  → `userSpeedMultiplier` < 1  → Welt scrollt langsamer
    //   • Drag End   → zurück auf 1.0 (animiert in der View)
    //
    // Technisch: die View setzt `userSpeedMultiplier` pro Frame (oder
    // animiert). `tick(now:)` integriert die Differenz (multiplier - 1)
    // über die Zeit in `accumulatedUserTimeBias`. Dieser Bias fließt in
    // `effectiveElapsed`, d. h. die Welt bewegt sich entsprechend
    // schneller oder langsamer — ohne dass die Wave-Geometrie reißt
    // (dieselbe Mechanik wie Slow-Mo-Lag, nur mit variablem Vorzeichen).
    @Published var userSpeedMultiplier: CGFloat = 1.0
    private(set) var accumulatedUserTimeBias: TimeInterval = 0
    private var lastUserBiasTickDate: Date?

    /// Max-Grenzen für den User-Speed — damit Kinder das Spiel nicht
    /// zum Stillstand bringen oder in Sekundenbruchteilen fliegen. Wird
    /// in der View beim Drag-Mapping geclampt.
    ///
    /// **Quick-Fix 2026-04-30 (`v2-elumi-gameover-cta-home`)** —
    /// `userSpeedMax` von 1.6 auf 3.2 verdoppelt. User-Report:
    /// „word runner; nach oben draggen erhöht ja die geschwindigkeit:
    /// speed max verdoppeln". Damit kann der User durch Drag-up das
    /// Spiel deutlich schneller machen — fühlt sich nach „Boost" an
    /// statt nur einer leichten Beschleunigung.
    static let userSpeedMin: CGFloat = 0.5
    static let userSpeedMax: CGFloat = 3.2

    /// **Fisch-Event** (visuelles Ambient-Event). Maximal eines pro
    /// Run; wird beim `start()` mit zufälligem Delay (25–40 s)
    /// scheduled. View rendert dann eine Fisch-Silhouette, die über
    /// den Bildschirm zieht.
    @Published private(set) var fishEventStartedAt: Date?

    /// **Jump-Mechanic** (Klassik-Runner-Feature).
    ///
    /// Wall-Clock-Zeitstempel des Sprung-Starts. `nil` = Spieler steht.
    /// Bewusst **wall-clock** und nicht `effectiveElapsed` — Spieler-
    /// Input soll sich unabhängig von Slow-Mo anfühlen, der Sprung
    /// dauert immer 0.45 s real.
    ///
    /// Abfrage über `isJumping(at:)` / `jumpHeight(at:)` — die View
    /// zeichnet damit Y-Offset + Schatten-Skalierung, der `tick()`
    /// nutzt `isJumping(at:)` zum Kollisions-Skip bei niedrigen
    /// Hindernissen (`.rock`).
    ///
    /// **Kein Air-Jump**: `jump()` ist no-op, solange der vorige
    /// Sprung noch nicht abgeschlossen ist.
    @Published private(set) var jumpStartedAt: Date?

    // MARK: - Clock

    /// Fixpunkt, gegen den alle Wave-Zeiten rechnen. Wird beim ersten
    /// `start()` gesetzt und bleibt über Restarts stabil — so ruckelt
    /// der Stripe-Scroll bei Restart nicht zurück auf 0.
    private(set) var runStart: Date = .init()

    /// Beim Game-Over eingefrorener Zeitpunkt. Die View liest das
    /// über `effectiveNow(context:)`, damit Stripes + Obstacles
    /// beim Crash stehen bleiben (sonst wäre der Crash-Moment nicht
    /// analysierbar).
    @Published private(set) var gameOverAt: Date?

    /// Zeitpunkt, an dem die App zuletzt in den Hintergrund ging —
    /// `nil` solange aktiv. Nur für `handleScenePhaseChange` relevant.
    private var backgroundEnteredAt: Date?

    /// **Codeaudit 2026-09-03, Stufe 1** — `tick(now:)` und `effectiveElapsed`
    /// rechnen direkt gegen `now.timeIntervalSince(runStart)`. Anders als
    /// beim Arcade-Spiel (das über Frame-Deltas läuft und einfach
    /// `lastFrameDate = nil` setzen kann) gibt es hier keinen Delta-
    /// Akkumulator zum Zurücksetzen — `runStart` ist ein fester Anker.
    /// Bleibt die App im Hintergrund, wächst `realElapsed` beim ersten
    /// Tick nach der Rückkehr um die volle Hintergrundzeit auf einen
    /// Schlag: Hindernisse springen an Positionen, die ihrer inzwischen
    /// verstrichenen Weltzeit entsprechen, und die Kollisionsprüfung
    /// wertet das als verpasste Aufgaben statt als faires Ausweichen.
    ///
    /// Der Fix schiebt `runStart` beim Zurückkehren um exakt die
    /// Hintergrunddauer nach vorne — die Weltzeit „merkt" sich die Pause
    /// nicht, genau wie beim Arcade-Reset. Von der View aus per
    /// `.onChange(of: scenePhase)` aufgerufen.
    func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase == .active {
            guard let enteredAt = backgroundEnteredAt else { return }
            let pausedDuration = Date().timeIntervalSince(enteredAt)
            runStart = runStart.addingTimeInterval(pausedDuration)
            backgroundEnteredAt = nil
        } else if backgroundEnteredAt == nil {
            backgroundEnteredAt = Date()
        }
    }

    // MARK: - Dependencies

    private let spawner: WordRunnerSpawner
    private let taskProvider: RunnerTaskProvider?

    // MARK: - Tuning (View + VM teilen sich diese)

    struct Tuning {
        // MARK: - Scroll-Speed + Speed-Ramp (Phase 6b — Difficulty Curve)
        //
        // **Linear ansteigende Scroll-Geschwindigkeit**, damit der Run
        // weich startet und sanft an Tempo gewinnt („leicht starten,
        // fließend schwerer werden"-Spec). Gleichzeitig muss die
        // Geometrie der Welle **deterministisch** bleiben — sonst
        // springen Wellen, wenn wir Speed ändern.
        //
        // Lösung: kumulativer Travel. Anstatt `waveY = t × v` (das
        // bricht bei variablem v), berechnen wir `waveY = F(t) -
        // F(spawnTime)`, wobei F das Zeit-Integral der Speed-Funktion
        // ist. Die Speed-Funktion ist linear bis `speedRampDuration`,
        // danach konstant, also lässt sich F in geschlossener Form
        // ausdrücken → keine Integration pro Frame, kein Drift.
        //
        //   v(t) = v0 + (v∞ - v0) · min(t/T, 1)
        //
        //   F(t) = v0·t + (v∞ - v0) · min(t, T)² / (2T)
        //        + (v∞)(max(t - T, 0))       -- falls t > T
        //
        //   F(t) ist `cumulativeTravel(at:)` unten.

        /// Startgeschwindigkeit. Visual-Tuning History:
        ///   • 105 → 88 (Phase X)
        ///   • 88 → 97 (Phase 7.6, +10 %)
        ///   • **97 → 112 (Stufe 1, +15 % / 2026-04-28)** — der
        ///     Spielstart soll spürbar flotter wirken.
        static let startScrollSpeed: CGFloat = 112
        /// Peak nach Ramp. Tuning-History: 180 → 150 → **173** (+15 %
        /// in Stufe 1, 2026-04-28). Ramp-Duration unverändert
        /// (`speedRampDuration = 35 s`).
        static let peakScrollSpeed: CGFloat = 173
        /// Wie lange die Ramp von Start → Peak dauert (Sekunden).
        /// 35 s = „Run 1 fühlt sich ruhig an, Run 2 spürbar schneller".
        static let speedRampDuration: TimeInterval = 35.0

        // MARK: - Speed-Bursts (Spec 4 — Speed Variation)
        //
        // **Kurze Beschleunigungs-Bursts**, die regelmäßig den Run
        // anheizen — danach wieder normales Tempo. Mathematisch sauber
        // integriert (siehe `cumulativeTravel(at:)`), damit die
        // Wave-Geometrie nicht reißt.

        /// Erster Burst-Start (Sekunden seit `start()`). Sitzt bewusst
        /// kurz NACH der Ramp, damit der erste Burst spürbar ist
        /// (Speed während Ramp ist eh schon im Wachsen).
        static let speedBurstFirstAt: TimeInterval = 22.0
        /// Abstand zwischen Bursts (Sekunden).
        static let speedBurstInterval: TimeInterval = 25.0
        /// Dauer jedes Bursts (Sekunden).
        static let speedBurstDuration: TimeInterval = 2.5
        /// Multiplikator während des Bursts (1.5 = +50 %).
        static let speedBurstMultiplier: CGFloat = 1.5
        /// **Visual Tuning** — Horizont noch höher (0.18 → 0.12).
        /// „Mehr Blick nach vorne, weniger Top-Down" — der Horizont
        /// sitzt jetzt klar oben, die Strecke wird optisch länger.
        static let horizonYFraction: CGFloat = 0.12
        /// Y-Offset (pt) des Spawn-Punkts **gegenüber** dem Horizont.
        /// 0 = Wellen erscheinen exakt auf dem Horizont und „wachsen
        /// heraus", positiv = etwas unterhalb (taucht sichtbar auf).
        /// In der flachen Phase 3.5 war das ein anderer Bezugspunkt
        /// (Screen-Oberkante) — hier explizit auf Horizon-relativ,
        /// weil Obstacles jetzt nicht von oben reinscrollen, sondern
        /// aus der Tiefe kommen.
        static let spawnYOffset: CGFloat = 0
        /// **Phase 6.5** — Min-Scale weiter hoch (0.65 → 0.72). Schilder
        /// sind zwar insgesamt kleiner (Phase 6.5 shrinkt sie um ~22 %),
        /// dafür schon ab Spawn noch deutlicher lesbar. 0.72 ist das
        /// Minimum, ab dem Text in 32 pt-Font bei 110×70-Schild
        /// durchgängig lesbar bleibt.
        static let obstacleMinDepthScale: CGFloat = 0.72
        static let obstacleMaxDepthScale: CGFloat = 1.0
        /// **Phase 6.3** — lineareres Auffächern der Spuren.
        /// Ease 2.0 führte zu einer späten Öffnung, in Horizont-
        /// Nähe standen alle 3 Spuren fast am Fluchtpunkt
        /// übereinander. 1.3 = sanfter, Spuren lesen sich bereits
        /// am Horizont als 3 getrennte Bahnen.
        static let perspectiveEase: CGFloat = 1.3
        /// Phase 6.6: 0.35 → **0.45**. Spuren bleiben am Horizont
        /// noch deutlicher als 3 Bahnen erkennbar — der Spieler
        /// sieht ab Spawn klar „links / mitte / rechts", nicht drei
        /// nahe Punkte.
        static let horizonLaneSpread: CGFloat = 0.45
        /// Halbe Kollisions-Höhe (pt) für **Schilder + Power-Ups +
        /// Collectibles**. Diese Objekte sind höher (sign-panel + Pfosten
        /// = ~90 pt) — das 46-pt-Hitfenster ist entsprechend großzügig.
        static let hitHalfHeight: CGFloat = 46
        /// **Felsen-Hitbox** (Phase 7.4 — Jump-Fix). Deutlich kleiner
        /// als das Sign-Hitfenster, weil Rocks nur ~52 pt hoch sind
        /// und der Jump mathematisch durch das **ganze** Rock-Fenster
        /// fliegen muss, bevor der Spieler landet. 32 pt → 64 pt
        /// Fenster → bei Start-Speed (88 pt/s) 0.73 s Crossing-Zeit,
        /// vergleichen mit 1.1 s Jump-Duration → komfortabler Puffer.
        static let hitHalfHeightRock: CGFloat = 32
        /// Y-Anteil der Screen-Höhe, auf dem der Spieler steht.
        /// Visual Tuning: 0.85 → **0.80** (unteren 20–25 %), damit
        /// die Perspektive weniger top-down wirkt — wir sehen mehr
        /// Strecke nach vorne statt unter den Spieler.
        static let playerYFraction: CGFloat = 0.80
        /// Wann eine Welle als „durch" gilt und weggeräumt wird.
        /// Safety-Margin unter Screen-Unterkante.
        static let despawnMargin: CGFloat = 140
        /// Startdelay vor dem ersten Spawn nach `start()`. Gibt dem
        /// Spieler einen „Bereit"-Moment (Stripes+Musik schon an,
        /// aber noch keine Hindernisse). Phase 3.5 UX-Polish.
        static let startSpawnDelay: TimeInterval = 0.4
        /// Wie lange nach Game-Over das Summary-Overlay zurückgehalten
        /// wird. Phase 7.5 (Start/Ende-Unification): kein separates
        /// „GAME OVER"-Zwischen-Overlay mehr — der Spieler sieht 0.6 s
        /// den eingefrorenen Crash-Moment (Wrong-Flash, Life-Lost),
        /// danach fadet direkt das geteilte `GameSummaryView` ein.
        /// Das matched das Elumi-Verhalten — beide Spiele enden
        /// strukturell identisch.
        static let gameOverOverlayDelay: TimeInterval = 0.6
        /// Wie lange das Correct-Feedback (Lane-Highlight) leuchtet.
        static let correctFeedbackDuration: TimeInterval = 0.4
        /// Wie lange das Wrong-Feedback (Screen-Flash/Shake) läuft.
        static let wrongFeedbackDuration: TimeInterval = 0.35
        /// Wie lange das „1 Leben verloren"-Badge sichtbar ist.
        static let lifeLostBadgeDuration: TimeInterval = 1.1
        /// Punkte pro korrekt gewählter Option (Phase 5 Score-System).
        /// Score ist entkoppelt von XP — XP läuft über ProgressService.
        static let scorePerCorrect: Int = 10

        // MARK: - Jump (Klassik-Runner)
        //
        // Feste Sprungkurve, feste Höhe, keine variable Steuerung.
        // Bewusst **kein** Physik-System — Sin-Wave-Curve gibt
        // natürliches Ease-Out-Ease-In ohne Drift/Overshoot.
        //
        // **Phase 7.4 Nachsatz-Tuning** (User-Feedback „viel zu
        // niedrig, man kommt über nichts drüber"): Dauer + Höhe
        // deutlich angehoben, damit Rock-Hitboxen zuverlässig
        // gecleart werden. Die Rock-Hitbox ist ±46 pt um die Welle
        // herum, d. h. das Obstacle braucht ~0.85 s bei Peak-Speed,
        // um die Hitbox komplett zu passieren — der Sprung muss
        // mindestens so lang in der Luft bleiben, sonst landet der
        // Spieler mitten im Rock.
        //
        // Spec-Korridor (400–500 ms) bleibt dokumentiert — aber
        // übersteuert vom praktischen Clearance-Bedarf.

        /// Gesamtdauer eines Sprungs in Sekunden (Wall-Clock, nicht
        /// Welt-Zeit — Spieler-Input soll sich konsistent anfühlen,
        /// auch während Slow-Mo).
        ///
        /// **1.25 s** — lange genug für komfortables Drüber-Fliegen
        /// auch bei Start-Speed (88 pt/s), selbst bei nicht-perfektem
        /// Timing. Jetzt cleart auch **STOP-Schilder** (jumpable ab
        /// diesem Patch).
        static let jumpDuration: TimeInterval = 1.25
        /// Sprung-Apex in pt. Tuning-History: 205 → **246**
        /// (Stufe 1, 2026-04-28, User-Spec „vertikale Bewegungsfreiheit
        /// um ~20 % erweitern"). Spieler kann sichtbar höher steigen,
        /// das Spielgefühl wird offener. Untere Y-Grenze (`playerY` =
        /// 80 % Screen-Höhe) bleibt unverändert — der Player-Y selbst
        /// ist fix, nur der Apex der Sin-Wave-Kurve wächst.
        static let jumpMaxHeight: CGFloat = 246
        /// Dauer der Landing-Squash-Animation **nach** Jump-Ende.
        /// 0.18 s, passt zum noch höheren Sprung.
        static let jumpLandingDuration: TimeInterval = 0.18
        /// Schwellenwert (pt), ab dem ein Drag als **Lane-Wechsel**
        /// gilt (nicht als Tap/Jump). Wird von der View im
        /// Gesture-Handler gelesen — liegt hier, damit die Bewegungs-
        /// Semantik mit allen anderen Tuning-Konstanten an einer
        /// Stelle steht.
        static let jumpVsDragThreshold: CGFloat = 12

        // MARK: - Height-Based Speed-Scaling (Stufe 1, 2026-04-28)
        //
        // **User-Spec**: „mit zunehmender Höhe spürbar steigern".
        // Niedrige Höhe = Basis-Speed, hohe Position = deutlich
        // schneller. Kurve **leicht progressiv** (pow 1.4) statt
        // linear, damit der Spieler beim Apex ein klares Durchrauschen-
        // Gefühl bekommt.
        //
        // Formel:
        //   heightFactor = jumpHeight(at:) / jumpMaxHeight  // 0…1
        //   curve         = pow(heightFactor, heightSpeedCurveExponent)
        //   multiplier    = 1.0 + curve * heightSpeedMaxBonus
        //
        // Der Multiplier wird über die existierende User-Speed-Bias-
        // Integration in `tick()` ins `accumulatedUserTimeBias`
        // eingespeist — gleicher Mechanismus wie der vertikale Drag.
        // Damit bleibt die Wave-Geometrie (`cumulativeTravel`)
        // mathematisch konsistent.

        /// Maximaler Bonus-Multiplikator am Sprung-Apex.
        /// 0.40 = +40 % Welt-Geschwindigkeit ganz oben.
        static let heightSpeedMaxBonus: CGFloat = 0.40
        /// Kurven-Exponent (>1 = progressiv, <1 = degressiv).
        /// 1.4 = leicht progressiv: bei halber Höhe gibt's nur ~38 %
        /// vom Bonus, bei 80 % Höhe schon ~73 %. Spürbares
        /// „Durchrauschen" zum Apex hin.
        static let heightSpeedCurveExponent: Double = 1.4

        // MARK: - Phase-6 Perspektiv-Helper
        //
        // **Eine** Quelle für alle Perspektiv-Rechnungen. Ohne diesen
        // gemeinsamen Rechenort würde die View anders projizieren als
        // die Kollisions-Detection — Obstacle visuell neben dem
        // Spieler, aber Hitbox trifft. Jeder Hit-Test läuft also
        // gegen dieselbe world-y-Koordinate wie die View rendert.

        /// Welt-Y einer Welle im aktuellen Frame. Startet **am
        /// Horizont** (Phase-6) und nutzt kumulativen Travel, damit die
        /// Speed-Ramp (Phase 6b) die Geometrie nicht zerlegt.
        static func waveY(elapsed: TimeInterval, wave: WordRunnerWave, screenHeight: CGFloat) -> CGFloat {
            let horizon = horizonY(screenHeight: screenHeight)
            let travel = cumulativeTravel(at: elapsed) - cumulativeTravel(at: wave.spawnTime)
            return horizon + spawnYOffset + travel
        }

        /// Momentangeschwindigkeit an Zeitpunkt `t` (Sekunden seit
        /// Run-Start). Linear ansteigend, dann konstant.
        static func instantSpeed(at t: TimeInterval) -> CGFloat {
            let T = speedRampDuration
            let clamped = max(0, min(T, t))
            let rampFraction = CGFloat(clamped / T)
            return startScrollSpeed + (peakScrollSpeed - startScrollSpeed) * rampFraction
        }

        /// Kumulativer Travel (pt) von Zeitpunkt 0 bis `t`.
        ///
        /// Geschlossene Form in zwei Stücken:
        ///   • `t ≤ T`: Fläche unter linearer Ramp →
        ///       v₀·t + (v∞ - v₀) · t² / (2T)
        ///   • `t > T`: Fläche der Ramp (Dreieck + Rechteck-Teil) +
        ///       konstanter Teil mit v∞ danach.
        static func cumulativeTravel(at t: TimeInterval) -> CGFloat {
            return baseCumulativeTravel(at: t) + burstExtraTravel(at: t)
        }

        /// **Base-Travel** ohne Speed-Bursts — die ursprüngliche
        /// Ramp+Plateau-Integration.
        private static func baseCumulativeTravel(at t: TimeInterval) -> CGFloat {
            let T = speedRampDuration
            let v0 = startScrollSpeed
            let vInf = peakScrollSpeed
            if t <= 0 { return 0 }
            if t <= T {
                let dv = vInf - v0
                return v0 * CGFloat(t) + dv * CGFloat(t * t) / (2 * CGFloat(T))
            }
            let rampTravel = v0 * CGFloat(T) + (vInf - v0) * CGFloat(T) / 2
            let plateauTravel = vInf * CGFloat(t - T)
            return rampTravel + plateauTravel
        }

        /// **Burst-Extra**: Summe der zusätzlichen Wege durch Speed-
        /// Bursts in [0, t]. Pro Burst-Fenster:
        ///   `extra = (m − 1) × (baseTravel(end) − baseTravel(start))`
        /// Iterativ über alle bisher aktiven Bursts. Günstig, weil
        /// pro 25 s-Run-Zeit nur eine Iteration anfällt.
        private static func burstExtraTravel(at t: TimeInterval) -> CGFloat {
            guard t > speedBurstFirstAt else { return 0 }
            let interval = speedBurstInterval
            let duration = speedBurstDuration
            let m = speedBurstMultiplier
            var extra: CGFloat = 0
            var burstStart = speedBurstFirstAt
            while burstStart < t {
                let burstEnd = burstStart + duration
                let observedEnd = min(burstEnd, t)
                if observedEnd > burstStart {
                    let baseInWindow =
                        baseCumulativeTravel(at: observedEnd) -
                        baseCumulativeTravel(at: burstStart)
                    extra += (m - 1) * baseInWindow
                }
                burstStart += interval
            }
            return extra
        }

        /// Liegt die aktuelle Zeit `t` innerhalb eines Speed-Bursts?
        /// View nutzt das, um einen kurzen „Boost"-Indikator zu zeigen.
        static func isInSpeedBurst(at t: TimeInterval) -> Bool {
            guard t >= speedBurstFirstAt else { return false }
            let elapsedSinceFirst = t - speedBurstFirstAt
            let cyclePos = elapsedSinceFirst.truncatingRemainder(dividingBy: speedBurstInterval)
            return cyclePos < speedBurstDuration
        }

        // MARK: - Spur-Variation (Spec 8)
        //
        // **Dynamische Lane-X**: statt der statischen `xFraction`-
        // Werte 0.18 / 0.50 / 0.82 atmen die Spuren leicht. Center
        // bleibt fix bei 0.50 (Spieler-Zentrum stabil), die äußeren
        // Spuren oszillieren um ±4 % synchron — mal etwas enger, mal
        // etwas weiter. Periode 12 s, Sin-Wave.
        //
        // **Wichtig**: alle Systeme (Floor-Lines, Stripes, Obstacle-
        // Projection, Player-Position, Hit-Test) lesen die Lane-X
        // aus diesem **einen** Helper. Damit bleibt die Math
        // konsistent — wäre tödlich, wenn Floor und Hit-Test
        // unterschiedliche Lane-Positionen rechnen.

        /// Periode der Lane-Atmung (Sekunden). Lang genug, dass
        /// die Variation nicht hektisch wirkt, kurz genug für
        /// spürbare Abwechslung.
        static let laneVariationPeriod: TimeInterval = 12.0
        /// Maximale Auslenkung pro Spur (Anteil der Screen-Breite).
        /// 0.04 = ±4 % der Screen-Breite — genug für „die Bahn pulst",
        /// nicht zu viel, damit die Lesbarkeit / Reaktionszeit nicht
        /// kippt. Center bleibt unangetastet.
        static let laneVariationAmplitude: CGFloat = 0.04

        /// Liefert die **aktuelle** xFraction einer Spur zur Zeit `t`.
        /// Statt `lane.xFraction` direkt zu nutzen, fragen alle
        /// Math-Helper hier nach.
        static func laneXFraction(_ lane: WordRunnerLane, at t: TimeInterval) -> CGFloat {
            let baseFraction = lane.xFraction
            // Center pulst nicht.
            guard lane != .center else { return baseFraction }
            // Wave-Phase 0...2π in `laneVariationPeriod` Sekunden.
            let phase = (t / laneVariationPeriod) * 2 * .pi
            let wave = CGFloat(sin(phase))   // -1 ... +1
            // Außenspuren symmetrisch: links rückt nach innen,
            // wenn die Welle positiv ist; rechts dann auch nach
            // innen. Beide bewegen sich also nach außen / nach
            // innen synchron.
            let direction: CGFloat = (lane == .left) ? +1 : -1
            return baseFraction + direction * wave * laneVariationAmplitude
        }

        /// Absolute Y-Position des Horizonts in pt.
        static func horizonY(screenHeight: CGFloat) -> CGFloat {
            screenHeight * horizonYFraction
        }

        /// Absolute Y-Position des Spielers in pt.
        static func playerY(screenHeight: CGFloat) -> CGFloat {
            screenHeight * playerYFraction
        }

        /// Normalisierte Tiefe einer Welt-Y: 0 = am Horizont, 1 = in
        /// Spielerzone, > 1 = hinter dem Spieler. Nicht geclampt —
        /// Skalen-Helper clampen bei Bedarf selbst.
        static func depth(forWaveY y: CGFloat, screenHeight: CGFloat) -> CGFloat {
            let horizon = horizonY(screenHeight: screenHeight)
            let player = playerY(screenHeight: screenHeight)
            let range = player - horizon
            guard range > 0 else { return 1 }
            return (y - horizon) / range
        }

        /// Skalierung eines Obstacles anhand seiner Tiefe. Linear
        /// zwischen min/max. z<0 (oberhalb Horizont) gibt `min`,
        /// z>1 (hinter Spieler) gibt `max` — wir skalieren nicht
        /// weiter hoch, sonst verdeckt ein Obstacle den halben Screen.
        static func depthScale(_ z: CGFloat) -> CGFloat {
            let clamped = max(0, min(1, z))
            return obstacleMinDepthScale + (obstacleMaxDepthScale - obstacleMinDepthScale) * clamped
        }

        /// Perspektivische X-Position einer Spur bei gegebener Tiefe.
        ///
        /// **Spec 8 update**: liest jetzt `laneXFraction(at:)` statt
        /// dem statischen `lane.xFraction`. Damit folgt die
        /// Perspektiv-Projektion der Lane-Atmung automatisch — Spur-
        /// Linien, Stripes, Obstacles und Hitbox bleiben synchron.
        static func perspectiveX(
            lane: WordRunnerLane,
            depth z: CGFloat,
            width: CGFloat,
            elapsed: TimeInterval
        ) -> CGFloat {
            let clamped = max(0, min(1, z))
            let eased = pow(clamped, perspectiveEase)
            let spread = horizonLaneSpread + (1 - horizonLaneSpread) * eased
            let center = width * 0.5
            let currentFraction = laneXFraction(lane, at: elapsed)
            let laneOffsetAtPlayer = (currentFraction - 0.5) * width
            return center + laneOffsetAtPlayer * spread
        }
    }

    // MARK: - Async Spawn Loop

    private var spawnTask: Task<Void, Never>?
    private var waveCount: Int = 0

    // MARK: - Init

    init(
        spawner: WordRunnerSpawner? = nil,
        taskProvider: RunnerTaskProvider? = nil
    ) {
        // Default-Verdrahtung: Seed-Provider an den Spawner dran.
        // Wer den Runner ohne Lerninhalte testen will, übergibt
        // beide Parameter explizit (z. B. `NullRunnerTaskProvider`).
        let provider = taskProvider ?? SeedRunnerTaskProvider()
        self.taskProvider = provider
        self.spawner = spawner ?? WordRunnerSpawner(taskProvider: provider)
    }

    deinit {
        spawnTask?.cancel()
    }

    // MARK: - State Transitions

    /// Aus `idle`, `gameOver` oder `summary` → `running`.
    func start() {
        stopSpawnLoop()
        runStart = Date()
        waves = []
        waveCount = 0
        currentLane = .center
        gameOverAt = nil
        showGameOverOverlay = false
        hasSpawnedFirstWave = false
        lastCorrectFeedbackAt = nil
        lastCorrectLane = nil
        lastWrongFeedbackAt = nil
        lastLifeLostAt = nil
        consumedCorrectIDs = []
        consumedWrongIDs = []
        // Phase-4-Counter und Phase-5-Lives/Score resetten
        correctAnswers = 0
        wrongAnswers = 0
        longestCombo = 0
        currentCombo = 0
        lives = Self.startingLives
        score = 0
        collectiblesGathered = 0
        collectedStarfish = 0
        collectedWorm = 0
        collectedPearl = 0
        lastCollectiblePickupAt = nil
        lastCollectiblePickupKind = nil
        shieldCharges = 0
        slowMoEndsAt = nil
        slowMoStartedAt = nil
        accumulatedSlowMoLag = 0
        userSpeedMultiplier = 1.0
        accumulatedUserTimeBias = 0
        lastUserBiasTickDate = nil
        fishEventStartedAt = nil
        jumpStartedAt = nil
        pendingOutcome = nil
        runState = .running
        // Start-Delay vor dem ersten Wave-Spawn — Spieler sieht kurz
        // leere Bahn + hört Musik anlaufen. Feels wie „bereit... los!"
        startSpawnLoop(afterDelay: Tuning.startSpawnDelay)
        scheduleFishEvent()
        // **SFX-Preload + Mute zurücksetzen**: alle SFX
        // dekodieren, damit der erste Lane-Wechsel nicht
        // durch First-Play-Latenz hörbar wird. Mute aus, damit
        // die SFX nach Restart wieder spielen.
        WordRunnerSFXPlayer.shared.preloadAll()
        WordRunnerSFXPlayer.shared.setMuted(false)
    }

    /// Fisch-Event einmalig pro Run scheduln. Zufälliges Delay
    /// zwischen 25 und 40 s. Wenn der Run vorher endet (Game Over,
    /// stop()), passiert nichts mehr — die Task self-cancelt sich
    /// am Ende.
    private func scheduleFishEvent() {
        Task { @MainActor [weak self] in
            let delay = Double.random(in: 25...40)
            try? await Task.sleep(for: .seconds(delay))
            guard let self, self.runState.isRunning else { return }
            self.fishEventStartedAt = Date()
            // Auto-Cleanup: nach 9 s den Marker zurücksetzen.
            // `self` ist hier schon unwrapped (oben guard'd), weak-
            // ref in zweitem await wäre redundant — Task läuft
            // weiter, ist `@MainActor`-isoliert wie self.
            try? await Task.sleep(for: .seconds(9))
            self.fishEventStartedAt = nil
        }
    }

    /// Phase-2-Restart nach Game-Over. Aktuell schlicht ein `start()`.
    /// Phase 3+ kann hier Session-Summary freezen, XP submitten etc.
    func restart() {
        start()
    }

    /// Bricht den aktuellen Run ab und setzt zurück auf `idle`. Nicht
    /// für Game-Over — das geht über `enterGameOver(reason:)`.
    /// Hilfreich z. B. beim Schließen der View.
    func stop() {
        stopSpawnLoop()
        runState = .idle
        waves = []
        gameOverAt = nil
    }

    private func enterGameOver(reason: WordRunnerRunState.GameOverReason) {
        guard runState.isRunning else { return }
        gameOverAt = Date()
        stopSpawnLoop()
        runState = .gameOver(reason: reason)
        // **SFX-Spec**: Game Over stoppt weitere SFX. LifeLoss ist
        // schon gespielt (im tick), spätere stille Frames bleiben
        // ruhig.
        WordRunnerSFXPlayer.shared.setMuted(true)

        // **Phase 4 — ProgressService-Integration**:
        // Session **synchron** beim Game-Over recorden. Die gleiche
        // Pipeline wie Quiz/Training/Flashcards — keine parallele
        // XP-Logik, keine modul-eigenen Counter.
        let learningSession = LearningSession(
            origin: .wordRunner,
            correctCount: correctAnswers,
            wrongCount: wrongAnswers,
            longestCombo: longestCombo,
            masteredCardCount: 0
        )
        let outcome = ProgressService.shared.record(session: learningSession)
        pendingOutcome = outcome
        #if DEBUG
        appDebugLog("🏁 [WordRunner] session recorded — correct=\(correctAnswers) wrong=\(wrongAnswers) " +
              "combo=\(longestCombo) totalXP=\(outcome.totalXP) credits=\(outcome.totalCredits) " +
              "leveledUp=\(outcome.leveledUp) duration=\(String(format: "%.1f", runDuration))s")
        #endif

        // Crash-Moment 0.6 s stehen lassen (Spieler sieht eingefrorenes
        // Obstacle + Wrong-Flash), dann in den `summary`-State wechseln.
        // Die View liest `pendingOutcome` und rendert SessionSummaryView.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Tuning.gameOverOverlayDelay))
            guard let self else { return }
            // Nur übergehen, wenn wir noch im Game-Over-Zustand sind
            // (schneller Restart kann inzwischen zurück auf .running
            // geswitcht haben).
            if case .gameOver = self.runState {
                self.showGameOverOverlay = true
                self.runState = .summary
            }
        }
    }

    // MARK: - Input

    /// **List-Swap-Hook** (Phase 7.4+): wenn der User auf dem Start-
    /// Screen eine andere Vokabelliste wählt, müssen die bereits
    /// gebauten Aufgaben-Pools verworfen werden. Diese Methode
    /// delegiert das an den LiveListRunnerTaskProvider; für andere
    /// Provider (z. B. Seed) ist sie no-op, weil ihre Pools von der
    /// Listen-Auswahl unabhängig sind.
    func refreshLiveContent() {
        // Direkter Live-Provider (ohne Fallback-Wrapper).
        (taskProvider as? LiveListRunnerTaskProvider)?.refreshPool()
        // Wenn der Provider in einen Fallback-Wrapper eingepackt ist
        // (Stufe 1 / 2026-04-28), durch den Wrapper hindurch
        // refreshen.
        (taskProvider as? FallbackRunnerTaskProvider)?.refreshPool()
    }

    /// Bewegt die aktuelle Spur um `delta`. Clamped an den Rändern
    /// (kein Wrap). No-op, wenn das Spiel nicht läuft.
    func moveLane(by delta: Int) {
        guard runState.isRunning else { return }
        let target = currentLane.rawValue + delta
        guard let next = WordRunnerLane(rawValue: target) else { return }
        guard next != currentLane else { return }
        currentLane = next
    }

    /// **Phase 3.5**: Absoluter Lane-Setter. Vom Arcade-Stil-Drag +
    /// Tap-auf-Spur genutzt — dort wird die Ziel-Spur direkt aus der
    /// Finger-X-Position berechnet, kein ±1-Delta. Keine Animation
    /// hier — die View steuert das Visual via `withAnimation`.
    func setLane(_ lane: WordRunnerLane) {
        guard runState.isRunning else { return }
        guard lane != currentLane else { return }
        currentLane = lane
        WordRunnerSFXPlayer.shared.play(.lane)
    }

    /// **Jump triggern** — vom Tap aus der Gesten-Schicht aufgerufen.
    /// Bedingungen:
    ///   • Run muss `.running` sein (kein Jump in Idle/GameOver/Summary)
    ///   • Spieler darf **nicht** bereits in der Luft sein (kein Air-
    ///     Jump / kein Double-Jump)
    ///
    /// Setzt `jumpStartedAt = Date()`. Die View liest daraus
    /// Sprung-Höhe + Schatten, der `tick()` nutzt `isJumping(at:)`
    /// zum Skippen niedriger Hindernisse (`.rock`).
    func jump() {
        guard runState.isRunning else { return }
        let now = Date()
        if let started = jumpStartedAt,
           now.timeIntervalSince(started) < Tuning.jumpDuration {
            return  // Already in the air → no air-jump.
        }
        jumpStartedAt = now
    }

    /// Ist der Spieler aktuell in der Luft?
    ///
    /// - Parameter now: **Wall-Clock-Zeitpunkt** des aufrufenden
    ///   Frames. Intern wird mit derselben Referenz gegen
    ///   `jumpStartedAt` verglichen — Slow-Mo greift hier bewusst
    ///   nicht (feste Sprungdauer unabhängig von Welt-Zeit).
    func isJumping(at now: Date) -> Bool {
        guard let start = jumpStartedAt else { return false }
        let age = now.timeIntervalSince(start)
        return age >= 0 && age < Tuning.jumpDuration
    }

    /// Sprung-Höhe (pt über Baseline) zum Zeitpunkt `now`. 0 außerhalb
    /// des Sprungfensters.
    ///
    /// Kurve: `height = maxHeight · sin(π · t)` mit `t ∈ [0, 1]` als
    /// normalisierter Sprung-Fortschritt. Sin über π erzeugt natürliches
    /// Ease-Out-Start + Ease-In-Ende (Ableitung = π·cos(π·t) läuft glatt
    /// durch ±π), ohne Physik-Simulation und ohne Drift.
    func jumpHeight(at now: Date) -> CGFloat {
        guard let start = jumpStartedAt else { return 0 }
        let age = now.timeIntervalSince(start)
        guard age >= 0 && age < Tuning.jumpDuration else { return 0 }
        let t = age / Tuning.jumpDuration
        return Tuning.jumpMaxHeight * CGFloat(sin(t * .pi))
    }

    /// **Height-based Speed-Multiplikator (Stufe 1, 2026-04-28)**.
    ///
    /// Liefert einen Multiplikator >= 1.0, abhängig von der aktuellen
    /// Sprung-Höhe. Während der Spieler am Boden ist (jumpHeight == 0),
    /// gibt diese Funktion 1.0 zurück → kein Effekt. Während des Sprungs
    /// wächst der Multiplikator über eine progressive Kurve auf maximal
    /// `1.0 + Tuning.heightSpeedMaxBonus` am Apex.
    ///
    /// Wird in `tick()` zusammen mit `userSpeedMultiplier` in den
    /// `accumulatedUserTimeBias` integriert — die Welt-Geschwindigkeit
    /// (`cumulativeTravel`) reagiert dadurch sanft, ohne dass das
    /// Wave-Geometrie-Modell bricht.
    func heightSpeedMultiplier(at now: Date) -> CGFloat {
        let height = jumpHeight(at: now)
        guard height > 0, Tuning.jumpMaxHeight > 0 else { return 1.0 }
        let normalized = max(0, min(1, height / Tuning.jumpMaxHeight))
        let curve = CGFloat(pow(Double(normalized), Tuning.heightSpeedCurveExponent))
        return 1.0 + curve * Tuning.heightSpeedMaxBonus
    }

    /// Landing-Squash-Skalierung (Y-Achse) nach Abschluss eines
    /// Sprungs. In den ersten `jumpLandingDuration` Sekunden nach
    /// Jump-Ende läuft der Player von 0.88 → 1.0 (leicht gequetscht,
    /// federt zurück). Außerhalb des Fensters: 1.0.
    ///
    /// Spec: „kleine Landung Animation, kein übertriebenes Feedback" —
    /// 12 % Squash über 120 ms ist subtil, aber spürbar.
    func landingSquashScaleY(at now: Date) -> CGFloat {
        guard let start = jumpStartedAt else { return 1.0 }
        let age = now.timeIntervalSince(start)
        let jumpEnd = Tuning.jumpDuration
        let landingEnd = jumpEnd + Tuning.jumpLandingDuration
        guard age > jumpEnd && age < landingEnd else { return 1.0 }
        let t = (age - jumpEnd) / Tuning.jumpLandingDuration
        // Ease-out: 0.88 → 1.0 mit `1 - (1-t)^2`-Kurve.
        let eased = 1 - pow(1 - CGFloat(t), 2)
        return 0.88 + 0.12 * eased
    }

    // MARK: - Tick (Kollision + Cleanup)

    /// Vom View bei jedem TimelineView-Frame aufgerufen (via
    /// `.onChange(of: context.date)`, nicht im Body — State-Mutation
    /// darf nicht im Body passieren).
    ///
    /// Drei Aufgaben pro Tick:
    ///   1. Für die Welle **in der aktuellen Spur**, die am nächsten
    ///      an `playerY` ist, Kollision prüfen.
    ///   2. Ist die Kollision fatal → `enterGameOver(reason:)`.
    ///   3. Weggeflogene Wellen aus dem Array entfernen.
    func tick(now: Date, screenHeight: CGFloat) {
        guard runState.isRunning else { return }

        // **User-Speed-Bias-Integration** (Vertikal-Drag).
        // Pro Frame: dt = now − lastTickDate. Bias wächst (oder
        // schrumpft) proportional zu `(userSpeedMultiplier − 1)`.
        // Wenn Multiplier = 1 (Ruhezustand), ist dt-Beitrag 0 und der
        // Bias bleibt konstant — der User spürt keinen Unterschied zu
        // früher. Zieht der User nach oben (>1), läuft die Welt
        // schneller; nach unten (<1), langsamer. Cap auf `-realElapsed`
        // damit effectiveElapsed nie negativ wird.
        if let last = lastUserBiasTickDate {
            let dt = now.timeIntervalSince(last)
            if dt > 0 {
                // **User-Drag-Bias** (vertikales Ziehen für manuelle
                // Speed-Anpassung).
                let userDelta = dt * TimeInterval(userSpeedMultiplier - 1)
                // **Height-based Speed-Bias (Stufe 1, 2026-04-28)** —
                // beim Sprung wächst der Multiplikator über eine
                // progressive Kurve auf bis zu 1.4 am Apex. Der
                // resultierende Zeitbias addiert sich zur User-Drag-
                // Bias, sodass beide Quellen gemeinsam in
                // `effectiveElapsed` einfließen.
                let heightDelta = dt * TimeInterval(heightSpeedMultiplier(at: now) - 1)
                accumulatedUserTimeBias += userDelta + heightDelta
                // Safety-Clamp: Welt-Zeit darf nicht rückwärts laufen.
                let realElapsed = now.timeIntervalSince(runStart)
                let minBias = -(realElapsed - accumulatedSlowMoLag)
                if accumulatedUserTimeBias < minBias {
                    accumulatedUserTimeBias = minBias
                }
            }
        }
        lastUserBiasTickDate = now

        // **Welt-Zeit** statt Wall-Clock — Slow-Mo verzögert Wave-Y
        // entsprechend, Hit-Box bleibt synchron zur Render-Position.
        let elapsed = effectiveElapsed(context: now)
        let playerY = screenHeight * Tuning.playerYFraction

        // Kollision: erste Obstacle in currentLane, dessen y im
        // Spieler-Fenster liegt. Wir brechen bei Fund ab — pro Tick
        // nur eine Kollision verarbeiten, sonst könnten zwei Obstacles
        // gleichzeitig gemeldet werden und der Reason-Code wäre
        // nicht-deterministisch.
        for wave in waves {
            // **Phase 6**: Welt-Y kommt aus dem gemeinsamen Helper —
            // dieselbe Formel wie in der View. Ohne den Share würde
            // die Hit-Box visuell „neben" dem Obstacle liegen, sobald
            // die Perspektive greift.
            let waveY = Tuning.waveY(elapsed: elapsed, wave: wave, screenHeight: screenHeight)
            // Obstacle der aktuellen Spur in dieser Welle?
            guard let obs = wave.obstacles.first(where: { $0.lane == currentLane }) else {
                // Welle hat unsere Spur frei gelassen (Gap-Wave) —
                // der Spieler schlüpft sicher durch.
                continue
            }
            // **Obstacle-spezifisches Hitfenster**: jumpable Obstacles
            // (Rocks + STOP-Blocker) haben ein schmaleres Fenster
            // (32 pt statt 46 pt Halbhöhe), damit die 1.25 s Sprung-
            // dauer auch bei Start-Speed (88 pt/s) mit Puffer reicht.
            // Option-Schilder, Power-Ups und Collectibles nutzen das
            // normale Fenster — dort ist der Kollisions-Moment die
            // Spiel-Mechanik.
            let halfHeight: CGFloat = obs.isJumpable
                ? Tuning.hitHalfHeightRock
                : Tuning.hitHalfHeight
            guard abs(waveY - playerY) <= halfHeight else { continue }

            // **Jump-Skip**: jumpable Obstacles (Rocks + STOP-Schilder)
            // werden übersprungen, solange der Spieler in der Luft ist.
            // Option-Schilder, Power-Ups, Collectibles erreichen den
            // Sprung-Apex **nicht** — dort ist der Kollisions-Moment
            // die Spiel-Mechanik (Entscheidung, Einsammeln, Pickup).
            if obs.isJumpable, isJumping(at: now) {
                continue
            }

            // **Collectible-Pickup** (Phase 7.4): nicht tödlich, gibt
            // Score-Bonus + zählt hoch. Gleicher Guard wie PowerUps,
            // damit der Pickup nur einmal pro Hit-Fenster zählt.
            if case .collectible(let kind) = obs.kind {
                guard !consumedCorrectIDs.contains(obs.id) else { continue }
                consumedCorrectIDs.insert(obs.id)
                score += kind.scoreBonus
                if kind.isCountedCollectible {
                    collectiblesGathered += 1
                }
                // Per-Typ-Counter hochziehen (Phase 7.6+).
                switch kind {
                case .starfish: collectedStarfish += 1
                case .worm:     collectedWorm += 1
                case .pearl:    collectedPearl += 1
                }
                lastCollectiblePickupAt = Date()
                lastCollectiblePickupKind = kind
                // Sound: sanftes Pickup (kein Boost-Sound — Collectible
                // ist kein Effekt-Trigger, nur Score).
                WordRunnerSFXPlayer.shared.play(.pickup)
                continue
            }

            // **Power-Up Pickup**: nicht tödlich, aktiviert Effekt.
            if case .powerUp(let kind) = obs.kind {
                guard !consumedCorrectIDs.contains(obs.id) else { continue }
                consumedCorrectIDs.insert(obs.id)
                switch kind {
                case .shield:
                    shieldCharges += 1
                    WordRunnerSFXPlayer.shared.play(.pickup)
                case .slowMo:
                    activateSlowMo()
                    // Slow-Mo zählt als „Boost-aktivierender" Effekt
                    // (Spec: pickup vs boost). Wir spielen beide:
                    // Pickup-Sound für „eingesammelt", dann Boost-
                    // Sound für „Effekt gestartet".
                    WordRunnerSFXPlayer.shared.play(.pickup)
                    WordRunnerSFXPlayer.shared.play(.boost)
                }
                lastCorrectFeedbackAt = Date()
                lastCorrectLane = currentLane
                continue
            }

            if obs.isFatalOnHit {
                guard !consumedWrongIDs.contains(obs.id) else { continue }
                consumedWrongIDs.insert(obs.id)

                if shieldCharges > 0 {
                    shieldCharges -= 1
                    lastCorrectFeedbackAt = Date()
                    // Schild-Absorption als positives Feedback —
                    // pickup-ähnliches „klink", nicht .wrong.
                    WordRunnerSFXPlayer.shared.play(.boost)
                    continue
                }

                wrongAnswers += 1
                currentCombo = 0
                lastWrongFeedbackAt = Date()
                lastLifeLostAt = Date()
                lives = max(0, lives - 1)
                // **Priority** (SFX-Spec): Life-Loss überlagert
                // Wrong — wir spielen NUR Life-Loss, niemals beide.
                WordRunnerSFXPlayer.shared.play(.lifeLoss)
                // **Quick-Fix 2026-04-30 (`v2-elumi-gameover-cta-home`)** —
                // Haptik-Pattern an Elumi-Spiel angeglichen. User-
                // Report: „haptik bei lebensverlust bei word runner
                // auch so machen wie bei elumi". Elumi nutzt
                // `notificationOccurred(.error)` (siehe
                // `triggerLifeLossVisual()` in
                // ElumiArcadeGameView+Gameplay.swift).
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                if lives == 0 {
                    enterGameOver(reason: reasonFor(obstacle: obs))
                    return
                }
                continue
            }

            // Korrekte Option → Feedback-Signal (Phase 3.5) + Score
            // und Combo (Phase 4/5). Jedes Obstacle nur **einmal**
            // triggern — das Hit-Fenster ist mehrere Frames breit.
            if !consumedCorrectIDs.contains(obs.id) {
                consumedCorrectIDs.insert(obs.id)
                lastCorrectFeedbackAt = Date()
                lastCorrectLane = currentLane
                correctAnswers += 1
                score += Tuning.scorePerCorrect
                currentCombo += 1
                if currentCombo > longestCombo {
                    longestCombo = currentCombo
                }
                WordRunnerSFXPlayer.shared.play(.correct)
            }
        }

        // Cleanup: Wellen, die weit unter dem Screen sind.
        let despawnY = screenHeight + Tuning.despawnMargin
        waves.removeAll { wave in
            let waveY = Tuning.waveY(elapsed: elapsed, wave: wave, screenHeight: screenHeight)
            return waveY > despawnY
        }

        // **Slow-Mo Auto-Expire**: wenn die Phase abgelaufen ist, den
        // laufenden Lag-Beitrag in `accumulatedSlowMoLag` finalisieren
        // und State zurücksetzen. So wächst die Welt-Zeit ab `endsAt`
        // wieder normal (ohne Sprung — der Lag ist dauerhaft mit
        // eingerechnet).
        if let endsAt = slowMoEndsAt, Date() >= endsAt {
            if let started = slowMoStartedAt {
                let activeWindow = max(0, endsAt.timeIntervalSince(started))
                accumulatedSlowMoLag += activeWindow * (1 - Self.slowMoFactor)
            }
            slowMoStartedAt = nil
            slowMoEndsAt = nil
        }
    }

    /// Aktiviert Slow-Mo. Wenn bereits eine Phase läuft, wird sie
    /// **verlängert** (additive Restzeit), sodass mehrere Pickups
    /// in Folge sich akkumulieren.
    private func activateSlowMo() {
        let now = Date()
        if let endsAt = slowMoEndsAt, endsAt > now {
            // Verlängern: neue Endzeit relativ zur aktuellen Endzeit.
            slowMoEndsAt = endsAt.addingTimeInterval(Self.slowMoDuration)
        } else {
            // Neue Phase starten.
            slowMoStartedAt = now
            slowMoEndsAt = now.addingTimeInterval(Self.slowMoDuration)
        }
    }

    private func reasonFor(obstacle: WordRunnerObstacle) -> WordRunnerRunState.GameOverReason {
        switch obstacle.kind {
        case .blocker:        return .hitBlocker
        case .construction:   return .hitBlocker
        case .rock:           return .hitBlocker
        case .option:         return .wrongChoice
        // PowerUps + Collectibles sind nie fatal — der Pfad sollte
        // nicht erreichbar sein. Defensiver Fallback auf .hitBlocker.
        case .powerUp:        return .hitBlocker
        case .collectible:    return .hitBlocker
        }
    }

    // MARK: - Rendering-Helper

    /// Eingefrorene Zeit bei Game-Over, sonst live. Die View sollte
    /// alle Zeit-Berechnungen gegen diesen Rückgabewert durchführen,
    /// damit der Crash-Moment nicht weg-scrollt.
    func effectiveNow(context contextDate: Date) -> Date {
        if runState.isGameOver, let frozen = gameOverAt { return frozen }
        return contextDate
    }

    /// **Effektive Spielzeit** seit Run-Start, in Sekunden. Beachtet:
    ///   • Game-Over-Freeze (über `effectiveNow`)
    ///   • Slow-Mo-Lag (akkumuliert + laufender Beitrag)
    ///
    /// Der zurückgegebene Wert ist **die "Welt-Uhr"**: Wave-Y,
    /// Speed-Bursts, Lane-Atmung, Fisch-Events — alles soll diese
    /// Funktion lesen, damit Slow-Mo konsistent durchgreift.
    func effectiveElapsed(context contextDate: Date) -> TimeInterval {
        let now = effectiveNow(context: contextDate)
        let realElapsed = now.timeIntervalSince(runStart)
        var lag = accumulatedSlowMoLag
        if let started = slowMoStartedAt, let endsAt = slowMoEndsAt {
            // Wie lange ist die aktuelle Slow-Mo-Phase **bisher** aktiv?
            // Cap auf endsAt, damit Lag nicht weiter wächst, sobald die
            // Phase abgelaufen ist (auch wenn `tick()` noch nicht das
            // accumulatedSlowMoLag finalisiert hat).
            let cap = min(now, endsAt)
            let activeSoFar = max(0, cap.timeIntervalSince(started))
            lag += activeSoFar * (1 - Self.slowMoFactor)
        }
        // User-Bias (durch Vertikal-Drag) wird zur Welt-Zeit addiert:
        // positiv → Welt „reist" mehr, scrollt schneller; negativ →
        // Welt „reist" weniger, scrollt langsamer.
        return realElapsed - lag + accumulatedUserTimeBias
    }

    // MARK: - Spawn Loop

    private func startSpawnLoop(afterDelay delay: TimeInterval = 0) {
        spawnTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
                if Task.isCancelled { return }
            }
            await self?.spawnNext()
            var spawnCount = 1
            while !Task.isCancelled {
                // **Adaptive Difficulty**: Basis-Intervall sinkt mit
                // elapsed-Time von 2.7 s auf 1.9 s über 60 s.
                let elapsed = await self?.runStart.distance(to: Date()) ?? 0
                let baseInterval = WordRunnerSpawner.waveInterval(at: elapsed)
                // **Double-Decision**: jede 5. Welle spawnt die
                // nächste schneller hinterher.
                let isDoubleTrigger = (spawnCount % 5 == 0) && spawnCount > 0
                let interval: TimeInterval = isDoubleTrigger
                    ? max(1.0, baseInterval * 0.55)
                    : baseInterval
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { break }
                await self?.spawnNext()
                spawnCount += 1
            }
        }
    }

    private func stopSpawnLoop() {
        spawnTask?.cancel()
        spawnTask = nil
    }

    private func spawnNext() async {
        guard runState.isRunning else { return }
        // Welt-Zeit (mit Slow-Mo-Lag) → Wave-Y wird konsistent mit
        // den schon laufenden Wellen gerechnet.
        let elapsed = effectiveElapsed(context: Date())
        let wave = spawner.makeWave(index: waveCount, spawnTime: elapsed)
        waves.append(wave)
        waveCount += 1
        if !hasSpawnedFirstWave {
            hasSpawnedFirstWave = true
        }
    }
}
