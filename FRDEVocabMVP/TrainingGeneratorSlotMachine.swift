import SwiftUI

/// **Slot-Machine V4.2 — Snap-Fix (2026-04-23)**
///
/// V4.1 hatte ein hartnäckiges Einrast-Problem: die Walzen stoppten
/// „irgendwo", Icons saßen nicht sauber in der Mittelreihe. Root Cause
/// war der `.spring(response: 0.7, dampingFraction: 0.62)`-Stop —
/// der unterdämpfte Spring überschoss target_s um 1–2 Slots, was durch
/// den Wrap-Modulo im `visualOffset` als kurzzeitiges Flimmern eines
/// falschen Icons im Fenster sichtbar wurde, bevor er sich einschwang.
///
/// V4.2 ersetzt den Spring durch `.easeOut` (Overshoot = 0) und
/// erzwingt nach der Animation einen Hard-Snap auf den exakten
/// Ganzzahl-Zielwert. Damit rastet jedes Icon pixelgenau zentriert
/// in der Mittelreihe ein.
///
///   • Reel-Container haben feste Breite/Höhe + **expliziten** `.clipped()`
///   • Symbol-Stack kann nicht mehr über das Reel-Fenster hinaus zeichnen
///   • Keine `focusZoneHighlight`-Overlay-VStacks mehr
///   • Kein Idle-Glow-Pulse (kein `.repeatForever`-Background-Timer)
///   • Keine Reveal-Glow-Scale-Effekte (kein `scaleEffect`, keine `shadow`-
///     Animation abhängig von Phase)
///   • Keine auto-scheduled Glow-Deactivation nach Reveal
///   • Eine dezente Border um die Mittelreihe, sonst nichts
///   • **V4.2**: Stop-Phase strikt index-basiert (`target_s` ist IMMER
///     ein Integer-Vielfaches der Pool-Länge + desiredResidue),
///     `.easeOut` statt Spring, Hard-Snap-Correction in der Animation-
///     Completion.
///   • **V4.2**: Optionaler Debug-Overlay (`SlotReelView.showDebugGuides`)
///     mit sichtbaren Slot-Grenzen + hervorgehobener Mittelzone zur
///     Snap-Verifikation — im Produktivbetrieb auf `false`.
///
/// Der Flow endet in `.revealed` und **bleibt dort**, bis der Caller
/// explizit einen neuen Spin oder eine Navigation auslöst.
///
/// Debug-Logs an jedem State-Wechsel — temporär, für die Bereinigungs-
/// Phase, kann später gedeckelt werden.

// MARK: - Reel-Symbol-Model

/// Ein Reel-Eintrag. Entweder ein Trainingsmodul (Home-Icon) oder das
/// Elumi-Spezial-Symbol (Bonus).
///
/// **V4.8 (2026-04-25 Icon-Migration)**: Trainingsmodule nutzen jetzt
/// ausschließlich die Home-Screen-Icons via `HomeHeroModule`. Kein
/// SF-Symbol-Pfad mehr — `systemImage` wurde entfernt. Elumi bleibt
/// beim eigenen Asset `ElumiWasserfloh` (keine Krone!).
struct ReelSymbol: Identifiable, Equatable {
    enum Kind: Equatable {
        case module
        case elumi
    }

    let id = UUID()
    let kind: Kind
    /// Home-Screen-Modul, von dem das Icon und der Akzent übernommen
    /// werden. Für Trainingsmodul-Einträge IMMER gesetzt. `nil` nur
    /// für Elumi (nutzt stattdessen `assetImage`).
    let homeModule: HomeHeroModule?
    /// Asset-Catalog-Image (nur für Elumi: `"ElumiWasserfloh"`).
    /// `nil` für Modul-Einträge.
    let assetImage: String?
    let label: String
    let tint: Color

    init(
        kind: Kind,
        homeModule: HomeHeroModule? = nil,
        assetImage: String? = nil,
        label: String,
        tint: Color
    ) {
        self.kind = kind
        self.homeModule = homeModule
        self.assetImage = assetImage
        self.label = label
        self.tint = tint
    }

    var isElumi: Bool { kind == .elumi }

    /// Factory für ein Modul-Symbol aus einem Home-Icon. Einziger
    /// Entry-Point für Trainingsmodul-Einträge in der Slot Machine —
    /// stellt sicher, dass Icon, Title und Akzent aus der Single-
    /// Source-of-Truth `HomeHeroModule` kommen.
    static func module(_ module: HomeHeroModule) -> ReelSymbol {
        ReelSymbol(
            kind: .module,
            homeModule: module,
            label: module.title,
            tint: module.accent
        )
    }
}

extension ReelSymbol {

    /// Zentrales Bonus-Symbol — Match auf 3× gibt einen Game-Credit.
    /// Iterations-Historie:
    ///   • Initial: `ElumiWasserfloh` (Wasserfloh-Snack) — falsch zugeordnet
    ///   • 2026-04-25: `IconElumiSpiel` (Game-Console) — Identitäts-Korrektur
    ///   • 2026-04-30: `SplashCharacter` (Axolotl-Maskottchen) +
    ///     Label `Game`. Begründung: das Maskottchen ist das app-weit
    ///     etablierte Visual (Splash, Arcade-Hero, Word-Runner, Footer,
    ///     ~12 Refs); das Game-Console-Icon war ein generisches Symbol
    ///     ohne Bezug zur Elumi-Identität. Label-Rename `Elumi` → `Game`
    ///     macht klar, **wofür** der Match-Reward zählt (Game-Credit
    ///     für die Arcade), nicht **wer** ihn bringt.
    /// Match-Identität ist `kind: .elumi` (für `isElumi` / `elumiCount`-
    /// Zählung) — der enum-case-Name bleibt aus Backward-Compat zum
    /// existierenden Reward-Code (Z. 1147-1162 in `ElumiTabView.swift`)
    /// erhalten. Innerhalb der App ist das Symbol ab jetzt das
    /// „Game"-Symbol; die `.elumi`-Bezeichnung lebt rein als
    /// Code-internes Match-Token weiter.
    static let elumi = ReelSymbol(
        kind: .elumi,
        homeModule: nil,
        assetImage: "SplashCharacter",
        label: "Game",
        tint: Color(hex: "#FFD166")
    )

    /// Drei Reel-Pools, befüllt **ausschließlich** aus `HomeHeroModule`.
    /// Die 8 Home-Module werden über die Reels verteilt (mit leichter
    /// Überschneidung pro Reel für mehr Spin-Vielfalt). Elumi wird
    /// NICHT hier gepflanzt — pro Spin durch den Caller via
    /// `spinTargets` injiziert.
    static var standardReelPools: [[ReelSymbol]] {
        [
            // Reel 1 — Grundlagen + Vokabeln
            [
                .module(.karteikarten),
                .module(.vokabeln),
                .module(.nomen),
                .module(.artikel)
            ],
            // Reel 2 — Verben + Produktion
            [
                .module(.verben),
                .module(.verbformen),
                .module(.quiz),
                .module(.akzente)
            ],
            // Reel 3 — Mix aus beiden
            [
                .module(.karteikarten),
                .module(.quiz),
                .module(.vokabeln),
                .module(.akzente)
            ]
        ]
    }
}

// MARK: - Spin-Ergebnis

struct SlotSpinResult: Equatable {
    let centerSymbols: [ReelSymbol]
    var elumiCount: Int { centerSymbols.filter(\.isElumi).count }
}

// MARK: - Slot-Phase

enum SlotPhase: Equatable {
    case idle
    case spinning
    case stopping
    case landed
    case revealed
}

// MARK: - SlotMachineView

struct SlotMachineView: View {

    // MARK: Caller-API

    let reelPools: [[ReelSymbol]]
    let accent: Color

    @Binding var spinTargets: [ReelSymbol?]
    @Binding var spinStartToken: Bool
    @Binding var phase: SlotPhase

    let onLanded: (SlotSpinResult) -> Void
    var onReelSettled: ((_ reelIndex: Int) -> Void)?
    var onSpinStart: (() -> Void)?

    // MARK: Interne State

    @State private var reelSpinning: [Bool] = [false, false, false]
    @State private var reelSettled: [Bool] = [false, false, false]
    @State private var centerSymbols: [ReelSymbol?] = [nil, nil, nil]

    // MARK: Konstanten

    static let slotHeight: CGFloat = 72
    // **2026-04-25 (User „slot machine etwas breiter")**: reelWidth
    // 86 → 96 (+11 %), machineWidth 306 → 336. Icons und Labels haben
    // damit mehr Luft, bleiben aber mittig ausgerichtet.
    static let reelWidth: CGFloat = 96
    static let visibleRows: Int = 3
    /// Feste Maschine-Größe — kein dynamisches Frame, kein Layout-Überraschungs-Potenzial.
    static let machineWidth: CGFloat = 336
    static let machineHeight: CGFloat = 256

    // **V4.7 Extended-Tension-Pass** (2026-04-25 User-Spec
    // „Gesamtdauer +2-3 s, Stops 0.35-0.5 s auseinander, mechanisches
    // Gefühl").
    //
    // Timings gegenüber V4.6 gezielt erweitert:
    //   • spinDuration: länger für spürbaren Ramp-Up + Laufphase.
    //   • stopStagger: 0.5 s zwischen Reel-Start-to-Stop-Triggern.
    //     Da alle Reels dieselbe `settleDuration` nutzen, landen ihre
    //     Click-Events exakt 0.5 s auseinander — genau im User-Fenster
    //     „0.35-0.5 s Pause".
    //   • settleDuration: deutlich länger, sichtbares Ausrollen.
    //   • landedHoldDuration: etwas länger, sauberer Übergang ins
    //     Ergebnis-Highlight.
    //
    // Gesamt-Runtime ≈ 3.2 + 1.0 + 2.8 + 0.65 ≈ 7.65 s.
    // Vorher ~6.0 s. Click-Abstand 0.5 s — spürbar, nicht gehetzt.
    /// **Slot-Slowdown-Refactor (`feature/slot-machine-sounds`,
    /// 2026-04-30)**: vorher 3.20s konstanter Spin + 1.65s SwiftUI-
    /// Snap-Animation (`.easeOut`). Während des Snaps feuerten **keine
    /// Clicks**, weil der Timer in `performStop` invalidiert wurde —
    /// Click-Hook lebt im Timer-Body. User wollte aber „Casino-Feeling":
    /// hörbar verlangsamender Click-Stream während des Auslaufens.
    /// Lösung: Timer bleibt während Slowdown aktiv (siehe
    /// `slowdownDuration` + Slowdown-Branch im Timer-Body), Snap-
    /// Animation entfällt. `spinDuration` daher auf 2.20s reduziert,
    /// damit Total-Runtime pro Reel (linker Reel = 2.20 + 1.0 = 3.20s,
    /// wie vorher) erhalten bleibt.
    private let spinDuration: Double = 2.20
    // **V4.7.1 (2026-04-25)** — User-Feedback „2. Reel mehr Abstand
    // zur 1.". Gap Reel-0 → Reel-1 auf 0.85s erhöht (war 0.50),
    // Reel-1 → Reel-2 bleibt 0.50s. Click-Timing am finalen Stop ist
    // damit: t0 / +0.85 / +0.50 = deutlich spürbarer Beat.
    private let stopStagger: [Double] = [0.0, 0.85, 1.35]
    // **V4.7.3 (2026-04-25)** — User-Korrektur „nicht slow-mo am Ende,
    // realistisch: von super-schnell zu etwas langsamer reduzieren".
    // Vorher hatte `.easeOut(duration: 4.2)` einen langen horizontalen
    // Tail (Geschwindigkeit crawlt gegen 0) → gefühlt wie Slow-Motion.
    //
    // Jetzt: settleDuration 1.65s + custom `.timingCurve` mit deutlich
    // WENIGER Tail-Flatness. Der Bezier (0.40, 0.00, 0.65, 1.0) entspricht
    // einer „realistischen" Verzögerung — Reduktion des Speeds spürbar,
    // aber ohne den slow-mo-Crawl am Ende. Die Animation-Konstante
    // selbst wird in `performStop()` verwendet, hier definieren wir
    // nur die Dauer.
    /// **Vorher (V4.7.3)**: 1.65s — die SwiftUI `.easeOut`-Snap-Animation
    /// nach dem Timer-Invalidate. Mit dem Slowdown-Refactor 2026-04-30
    /// jetzt nur noch ein **Hard-Snap-Padding** für Edge-Cases (Race-
    /// Conditions zwischen Timer-Stop und onSettle). 0.05s — kürzer
    /// als der Timer-Tick-Abstand, also de-facto sofortig.
    private let settleDuration: Double = 0.05
    /// Zeit zwischen "alle Reels stehen" und `.revealed` — kurzer,
    /// inszenierter Stillstand bevor das Ergebnis gehighlightet wird.
    private let landedHoldDuration: Double = 0.65

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            reelsRow
        }
        .frame(width: Self.machineWidth, height: Self.machineHeight)
        .background(machineBackground)
        .overlay(machineFrameStroke)
        .overlay(centerRowBorder)
        .onAppear {
            print("🎰 [SlotMachineView] onAppear — phase=\(phase)")
        }
        .onChange(of: spinStartToken) { _, newValue in
            guard newValue else { return }
            guard phase == .idle || phase == .revealed else {
                print("🎰 [SlotMachineView] spinStartToken=true ignoriert (phase=\(phase))")
                return
            }
            runSpinSequence()
        }
    }

    // MARK: - Reels-Row (einfach, keine Gloss/Focus-Overlays)

    private var reelsRow: some View {
        HStack(spacing: 10) {
            ForEach(0..<3, id: \.self) { reelIndex in
                SlotReelView(
                    symbols: reelPools[reelIndex],
                    target: spinTargets[safe: reelIndex].flatMap { $0 },
                    accent: accent,
                    isSpinning: reelSpinning[reelIndex],
                    slotHeight: Self.slotHeight,
                    visibleRows: Self.visibleRows,
                    settleDuration: settleDuration,
                    onSettle: { resolvedSymbol in
                        handleReelSettled(reelIndex, resolvedSymbol: resolvedSymbol)
                    }
                )
                // Fixe Breite pro Reel — Höhe kommt aus SlotReelView selbst.
                .frame(width: Self.reelWidth)
                // Belt-and-Suspenders: nochmal am Reel-Rand clippen.
                .clipped()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Machine-Background (einfarbiger dunkler Rahmen)

    private var machineBackground: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .fill(Color(hex: "#0E1C30"))
    }

    private var machineFrameStroke: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous)
            .stroke(accent.opacity(0.35), lineWidth: 1.2)
    }

    /// Dezenter Rahmen um die Mittelreihe — kein Glow, keine Skalierung.
    /// Visualisiert die Ergebnis-Zone ohne Layer-Overhead.
    private var centerRowBorder: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(accent.opacity(0.55), lineWidth: 1.2)
            .frame(height: Self.slotHeight + 2)
            .padding(.horizontal, 14)
            .allowsHitTesting(false)
    }

    // MARK: - State-Maschine

    private func runSpinSequence() {
        guard phase == .idle || phase == .revealed else {
            print("🎰 [runSpinSequence] ignoriert (phase=\(phase))")
            return
        }
        print("🎰 [runSpinSequence] START — targets=\(spinTargets.map { $0?.label ?? "nil" })")
        phase = .spinning
        reelSettled = [false, false, false]
        centerSymbols = [nil, nil, nil]
        onSpinStart?()
        reelSpinning = [true, true, true]

        // Phase 2: gestaffelte Stops.
        DispatchQueue.main.asyncAfter(deadline: .now() + spinDuration) {
            guard phase == .spinning else {
                print("🎰 [stop-scheduler] abort, phase=\(phase)")
                return
            }
            phase = .stopping
            print("🎰 [runSpinSequence] Phase → .stopping")
            for (i, delay) in stopStagger.enumerated() {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    reelSpinning[i] = false
                }
            }
        }
    }

    private func handleReelSettled(_ reelIndex: Int, resolvedSymbol: ReelSymbol?) {
        guard !reelSettled[reelIndex] else { return }
        reelSettled[reelIndex] = true
        centerSymbols[reelIndex] = resolvedSymbol
        onReelSettled?(reelIndex)
        print("🎰 [reelSettled] reel=\(reelIndex) symbol=\(resolvedSymbol?.label ?? "nil")")

        guard reelSettled.allSatisfy({ $0 }) else { return }
        // Alle drei stehen
        phase = .landed
        print("🎰 [runSpinSequence] Phase → .landed")
        // **Slot-Audio (2026-04-30)** — Settle-Sound bei Stillstand
        // aller Reels. System-Sound 1057 (Tink) als Platzhalter, wird
        // später durch echtes Settle-Sample ersetzt.
        SlotAudioPlayer.shared.playSettle()

        DispatchQueue.main.asyncAfter(deadline: .now() + landedHoldDuration) {
            guard phase == .landed else {
                print("🎰 [reveal-scheduler] abort, phase=\(phase)")
                return
            }
            phase = .revealed
            spinStartToken = false
            print("🎰 [runSpinSequence] Phase → .revealed — ENDE (User entscheidet)")
            let result = SlotSpinResult(
                centerSymbols: centerSymbols.compactMap { $0 }
            )
            onLanded(result)
            // **Slot-Audio (2026-04-30)** — Win/Jackpot-Branching
            // basierend auf elumiCount (Game-Symbol-Anzahl im Result):
            //   • 3 → Jackpot-Sound (System-Sound 1306, Stufe-6 ersetzt
            //     durch echten Feuerwerk-Sound)
            //   • ≥ 2 → Win-Sound (System-Sound 1025)
            //   • < 2 → kein zusätzlicher Sound, der Settle oben reicht.
            if result.elumiCount == 3 {
                SlotAudioPlayer.shared.playJackpot()
            } else if result.elumiCount >= 2 {
                SlotAudioPlayer.shared.playWin()
            }
            // KEIN weiterer Timer, KEIN Glow-Reset, KEINE Auto-Navigation.
        }
    }
}

// MARK: - SlotReelView

/// Einzelne Walze. **Strenges Clipping** — der Container hat eine feste
/// Größe und `.clipped()`, damit der Symbol-Stack nicht über das Reel-
/// Fenster hinaus zeichnen kann.
struct SlotReelView: View {
    let symbols: [ReelSymbol]
    let target: ReelSymbol?
    let accent: Color
    let isSpinning: Bool
    let slotHeight: CGFloat
    let visibleRows: Int
    let settleDuration: Double
    let onSettle: (ReelSymbol?) -> Void

    /// **Debug-Overlay für Snap-Verifikation (V4.3)** — User-Report
    /// „Icons stoppen 1.5 Zellen zu tief" → temporär AN, damit visuell
    /// verifizierbar ist, wo das Snap tatsächlich landet. Nach
    /// Verifizierung wieder auf `false` setzen.
    /// Der Overlay hat `.allowsHitTesting(false)` und ändert keine
    /// Geometrie.
    static let showDebugGuides: Bool = true

    @State private var offsetSlots: Double = 0
    @State private var spinTimer: Timer?
    @State private var isStopping: Bool = false
    /// Zeitpunkt des aktuellen Spin-Starts — Referenz für die Ramp-Up-
    /// Geschwindigkeitskurve in `startSpin`.
    @State private var spinStartTime: Date = Date()
    /// **Slot-Audio (Branch `feature/slot-machine-sounds`, 2026-04-30)** —
    /// Letzter ganzzahliger `offsetSlots`-Wert. In jedem Tick prüfen wir,
    /// ob `Int(offsetSlots)` gegenüber diesem Wert gestiegen ist. Wenn
    /// ja → ein neuer Reel-Symbol-Slot ist durch die Mittelreihe
    /// gefahren → `SlotAudioPlayer.shared.playClick()` (mit internem
    /// 60ms-Throttle).
    @State private var lastWholeOffsetSlots: Int = 0

    // MARK: - Slowdown-Phase State (`feature/slot-machine-sounds`, 2026-04-30)

    /// Zeitpunkt, an dem die **Slowdown-Phase** gestartet wurde. nil =
    /// kein Slowdown aktiv (regulärer konstanter Spin oder Idle). Wird
    /// in `performStop` gesetzt; der Timer-Body branched darauf und
    /// rendert die Position-Kurve. Click-Hook bleibt aktiv, Frequenz
    /// folgt automatisch der abnehmenden Speed.
    @State private var slowdownStartAt: Date?
    /// `offsetSlots`-Wert beim Slowdown-Start (Anker für die
    /// Position-Interpolation).
    @State private var slowdownStartOffset: Double = 0
    /// Ziel-`offsetSlots`-Wert am Ende der Slowdown-Phase. Errechnet
    /// in `performStop` analog zur alten Logik (3 extra Revolutions
    /// + Snap-Residue).
    @State private var slowdownTargetOffset: Double = 0
    /// Ziel-Symbol für `onSettle`-Callback. Wird in `performStop`
    /// gesetzt und bei Slowdown-Ende durchgereicht.
    @State private var slowdownTargetSymbol: ReelSymbol?

    // MARK: - Animation-Tuning (V4.4 Mechanical-Feel)

    /// Ramp-Up-Dauer vom Stillstand auf Maximalgeschwindigkeit.
    /// Smoothstep-Kurve (3t²−2t³) — startet bei 0, beschleunigt weich
    /// und erreicht am Ende der Ramp genau die Max-Speed.
    private static let rampUpDuration: Double = 0.35
    /// Maximale Walzengeschwindigkeit in Slots pro Frame (60fps).
    /// 0.50 slots/frame = 30 slots/sec — nach Ramp-Up wird das bis
    /// zum Stop-Befehl gehalten.
    private static let maxSlotsPerFrame: Double = 0.50

    /// **Slowdown-Phase** (`feature/slot-machine-sounds`, 2026-04-30) —
    /// Dauer der hörbaren Verlangsamung am Ende jedes Reel-Spins.
    /// Position-Curve `1-(1-t)²` (quadratic ease-out). Click-Frequenz
    /// folgt automatisch der abnehmenden Speed (Click-Hook im Timer-
    /// Body feuert bei jedem `Int(offsetSlots)`-Increment, das mit
    /// der reduzierten Speed seltener wird).
    ///
    /// **Iteration 2 (User-Spec „slowdown zu kurz, verdoppeln")**:
    /// 1.0s → 2.0s. Längere Verlangsamung gibt dem Click-Ramp-Down
    /// mehr Raum, casino-mäßiger Ausklang. Total-Runtime pro Reel
    /// damit ~2.20s konstant + 2.00s slowdown = 4.20s (vorher 3.20s).
    /// Stagger bleibt unverändert.
    private static let slowdownDuration: Double = 2.0

    private func resolvedPool() -> [ReelSymbol] {
        var pool = symbols
        if let t = target, !pool.contains(where: { $0.label == t.label && $0.isElumi == t.isElumi }) {
            pool.append(t)
        }
        return pool
    }

    /// Genug Pool-Repeats, damit auch bei sehr langen Spin-Phasen und
    /// Wrap-Edge-Cases immer genug Symbole zum Rendern da sind.
    /// 12 Wiederholungen × ~4 Pool-Items = 48 Cells — reicht für 2+
    /// Sekunden Spin selbst ohne Wrap. **Mit** Wrap sogar für beliebig
    /// lange Spins.
    private var extendedSymbols: [ReelSymbol] {
        let pool = resolvedPool()
        guard !pool.isEmpty else { return [] }
        return Array(repeating: pool, count: 12).flatMap { $0 }
    }

    /// **Bug-Fix 2026-04-22 (Abend II)**: vorher lief `visualOffset`
    /// unbeschränkt negativ — nach ~1.3 s Spin war der gesamte Symbol-
    /// Stack aus dem sichtbaren Fenster raus, Reels wirkten leer.
    ///
    /// Fix: Modulo-Wrap auf Pool-Länge. `offsetSlots` darf als State
    /// beliebig groß werden (für das Spring-Settle-Target), der Render-
    /// Offset bleibt aber immer im Bereich `[-N*h, 0]`. Da der erweiterte
    /// Stack die Pool-Symbole zyklisch wiederholt, ist die
    /// Wrap-Grenze **content-stetig** — kein visueller Sprung.
    ///
    /// Bei offsetSlots = s mit wrap zu s' ∈ [0, N) zeigt die Mittelreihe
    /// extendedSymbols[s'+1]; das nutzt `performStop` für das Snapping.
    private var visualOffset: CGFloat {
        let pool = resolvedPool()
        guard !pool.isEmpty else { return 0 }
        let cycle = Double(pool.count)
        let raw = offsetSlots.truncatingRemainder(dividingBy: cycle)
        // `truncatingRemainder` kann negative Werte liefern, wenn offsetSlots < 0.
        // Wir wollen immer [0, cycle).
        let wrapped = raw < 0 ? raw + cycle : raw
        return -CGFloat(wrapped) * slotHeight
    }

    var body: some View {
        // **V4.3 Absolute-Positioning-Rewrite** (2026-04-24 abend).
        //
        // Vorher: VStack + offset. Das funktionierte mathematisch, aber
        // der User berichtete, dass Icons visuell ~1,5 Zellenhöhen zu
        // tief landen. Root Cause: Die Kombination aus
        // `ZStack(alignment: .top)` + VStack mit natürlicher Höhe von
        // 3456pt gegenüber einem 216pt-Frame erzeugt in SwiftUI
        // intermittent Layout-Diskrepanzen — besonders nach State-
        // Updates in der Parent-View.
        //
        // Die bulletproof Alternative: Jede Zelle bekommt ihre
        // EXAKTE y-Koordinate via `.offset(y: i*slotHeight + visualOffset)`.
        // Kein VStack, keine Alignment-Interpretation, kein natürliches
        // Sizing — nur absolute Positionen. Die Rechnung wird 1:1 zur
        // Pixel-Position.
        //
        // Am Rand (y = 0 und y = 216 des Reel-Fensters) sorgt `.clipped()`
        // dafür, dass Cells außerhalb nicht sichtbar sind. Da wir 48
        // Cells (12 × pool) haben, gibt es immer genug gerenderte Cells
        // für jede Offset-Position.
        ZStack(alignment: .topLeading) {
            // Reel-Fenster-Hintergrund
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.45))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(accent.opacity(0.18), lineWidth: 1)
                )

            // Absolute-positioned cells.
            ForEach(0..<extendedSymbols.count, id: \.self) { i in
                symbolCell(extendedSymbols[i])
                    .frame(maxWidth: .infinity)
                    .frame(height: slotHeight)
                    .offset(y: CGFloat(i) * slotHeight + visualOffset)
            }
        }
        // Dieser Frame DEFINIERT das sichtbare Reel-Fenster exakt.
        .frame(height: slotHeight * CGFloat(visibleRows))
        // Root-Clip: alles außerhalb des Fensters wird ABSOLUT gecuttet.
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        // Debug-Overlay (V4.2) — nur wenn `showDebugGuides=true`.
        // Liegt NACH dem Clip, damit die Linien niemals aus dem Fenster
        // ragen. `allowsHitTesting(false)` hält die Walze klickbar.
        .overlay(debugGuides, alignment: .top)
        .onAppear {
            print("🎰 [SlotReelView.onAppear] symbols.count=\(symbols.count), extendedCount=\(extendedSymbols.count), slotHeight=\(slotHeight)")
        }
        .onChange(of: isSpinning) { _, newValue in
            if newValue {
                startSpin()
            } else if !isStopping {
                performStop()
            }
        }
    }

    // MARK: - Symbol-Cell (mit expliziter vertikaler Zentrierung)

    /// Eine Zelle zeigt das Modul-Icon. V4.3: explizite Spacer oben/unten,
    /// damit der Content garantiert in der Cell-Mitte sitzt — unabhängig
    /// von SwiftUI-VStack-Layout-Quirks. Vorher war `.frame(maxHeight:
    /// .infinity)` ohne Spacer, was in einigen Build-Konfigs zu Top-
    /// Packing führte (Icon oben im Cell-Rect statt zentriert).
    private func symbolCell(_ symbol: ReelSymbol) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            // **V4.8 Icon-Migration (2026-04-25)**: Pur Home-Icons.
            //   • `homeModule` → `HomeModuleIconView` mit der exakt
            //     gleichen Asset-Pipeline wie die Home-Cards.
            //   • `assetImage` → nur Elumi (`ElumiWasserfloh`).
            //   • **Kein SF-Symbol-Fallback** (User-Spec „keine
            //     generischen Symbole"). Wenn weder homeModule noch
            //     assetImage gesetzt — Cell bleibt leer, signalisiert
            //     Mapping-Lücke, die gefixt werden muss.
            //
            // Icon-Größen-Iterations-Historie:
            //   • 36pt (Initial)
            //   • 44pt (2026-04-25, +22%)
            //   • 58pt (2026-04-30, +32%) — Text-Label entfernt, Icon
            //     übernimmt die volle Cell-Höhe-Mitte. Cell-Höhe
            //     `slotHeight` (~72pt) bleibt unverändert; Spacer oben/
            //     unten halten das Icon zentriert.
            if let module = symbol.homeModule {
                HomeModuleIconView(icon: module.icon, size: 58)
            } else if let assetName = symbol.assetImage {
                Image(assetName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 54, height: 54)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Debug-Guides (V4.2 Snap-Verifikation)

    /// Sichtbare Rasterlinien + Highlight der Gewinnzone. Rendert **nur**
    /// wenn `Self.showDebugGuides == true`. Im Produktivbetrieb off.
    @ViewBuilder
    private var debugGuides: some View {
        if Self.showDebugGuides {
            ZStack(alignment: .top) {
                // Slot-Grenzlinien — jede 72pt-Grenze sichtbar.
                ForEach(0..<(visibleRows + 1), id: \.self) { row in
                    Rectangle()
                        .fill(Color.yellow.opacity(0.55))
                        .frame(height: 1)
                        .offset(y: CGFloat(row) * slotHeight)
                }
                // Mittelzone (Gewinnzeile) — grüne Umrandung bei
                // y = slotHeight (zweite Zeile von oben, also Zeile #2
                // von 3 sichtbaren).
                Rectangle()
                    .stroke(Color.green.opacity(0.9), lineWidth: 2)
                    .frame(height: slotHeight)
                    .offset(y: slotHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .allowsHitTesting(false)
        }
    }

    // MARK: - Spin/Stop

    /// **V4.4 Ramp-Up-Spin**: Die Walze startet aus dem Stillstand und
    /// beschleunigt per Smoothstep-Kurve (3t² − 2t³) über
    /// `rampUpDuration` auf `maxSlotsPerFrame`. Nach der Ramp-Phase
    /// läuft sie mit voller Geschwindigkeit, bis `performStop()`
    /// übernimmt. Kein abrupter Volltempo-Sprung mehr.
    ///
    /// Der Timer tickt bei 60fps. Pro Tick:
    ///   1. `elapsed = now − spinStartTime`
    ///   2. `rampProgress = min(1, elapsed / rampUpDuration)` (0…1)
    ///   3. `eased = rampProgress² × (3 − 2×rampProgress)` (smoothstep)
    ///   4. `offsetSlots += maxSlotsPerFrame × eased`
    ///
    /// Am Ende der Ramp ist `eased = 1`, also läuft die Walze mit
    /// exakt `maxSlotsPerFrame` pro Tick weiter.
    private func startSpin() {
        spinTimer?.invalidate()
        isStopping = false
        spinStartTime = Date()
        // **Slot-Audio (2026-04-30)** — Tracking-Variable resetten,
        // damit der erste Tick im neuen Spin keinen falschen „Click"
        // beim Initial-State auslöst.
        lastWholeOffsetSlots = Int(offsetSlots)
        // **Slowdown-State resetten** (Slowdown-Refactor 2026-04-30) —
        // bei einem frischen Spin ist der vorherige Slowdown-State
        // obsolet.
        slowdownStartAt = nil
        let rampDur = Self.rampUpDuration
        let maxSpeed = Self.maxSlotsPerFrame
        let slowdownDur = Self.slowdownDuration
        spinTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { _ in
            DispatchQueue.main.async {
                // **Branch 1 — Slowdown-Phase aktiv** (Refactor 2026-04-30).
                // `performStop` hat `slowdownStartAt` gesetzt; statt den
                // Timer zu invalidieren und eine SwiftUI-Animation zu
                // starten, treiben wir `offsetSlots` jetzt manuell mit
                // einer Position-Kurve. Vorteil: Click-Hook unten feuert
                // weiter, Frequenz folgt der abnehmenden Speed
                // (Casino-Feeling).
                if let stopAt = slowdownStartAt {
                    let elapsed = Date().timeIntervalSince(stopAt)
                    let t = min(1.0, elapsed / slowdownDur)
                    // Position-Curve `1 - (1-t)²` (quadratic ease-out).
                    // Bei t=0 → progress 0 (Anfang der Slowdown), bei
                    // t=1 → progress 1 (Ende = `slowdownTargetOffset`).
                    // Speed = Ableitung = 2*(1-t) → von voll auf 0.
                    let progress = 1.0 - (1.0 - t) * (1.0 - t)
                    offsetSlots = slowdownStartOffset
                        + (slowdownTargetOffset - slowdownStartOffset) * progress

                    // Click-Hook (gleicher Code wie unten, dupliziert weil
                    // beide Branches Int-Increment-Detection brauchen).
                    let currentWhole = Int(offsetSlots)
                    if currentWhole > lastWholeOffsetSlots {
                        lastWholeOffsetSlots = currentWhole
                        SlotAudioPlayer.shared.playClick()
                    }

                    // **Slowdown-Ende**: Hard-Snap auf Target,
                    // Timer invalidieren, onSettle rufen.
                    if t >= 1.0 {
                        offsetSlots = slowdownTargetOffset
                        spinTimer?.invalidate()
                        spinTimer = nil
                        let symbol = slowdownTargetSymbol
                        slowdownStartAt = nil
                        #if DEBUG
                        print("🎰 [slowdown-done] offsetSlots=\(offsetSlots) target=\(symbol?.label ?? "nil")")
                        #endif
                        onSettle(symbol)
                    }
                    return
                }

                // **Branch 2 — Reguläre Spin-Phase** (Ramp-Up + konstanter
                // Speed). Unverändert gegenüber V4.4.
                let elapsed = Date().timeIntervalSince(spinStartTime)
                let rampProgress = min(1.0, elapsed / rampDur)
                // Smoothstep: weiche Ease-In-Out-Kurve. Bei t=0 ist
                // die Ableitung 0 (sanfter Start), bei t=1 ebenfalls 0
                // (sauberer Übergang in die konstante Laufphase).
                let eased = rampProgress * rampProgress * (3.0 - 2.0 * rampProgress)
                offsetSlots += maxSpeed * eased
                // **Click-Audio-Hook (2026-04-30)** — Wenn der
                // ganzzahlige Offset gewachsen ist, ist mindestens ein
                // neues Symbol durch die Mittelreihe gefahren →
                // Click-Sound. Throttle (60ms) liegt im Player; bei
                // voller Ramp-Up-Geschwindigkeit (~30 Symbole/Sek.)
                // landen wir bei ~16 hörbaren Clicks/Sek. — passt zur
                // Slot-Machine-Klangcharakteristik.
                let currentWhole = Int(offsetSlots)
                if currentWhole > lastWholeOffsetSlots {
                    lastWholeOffsetSlots = currentWhole
                    SlotAudioPlayer.shared.playClick()
                }
            }
        }
    }

    private func performStop() {
        guard !isStopping else { return }
        isStopping = true
        // **Slowdown-Refactor (2026-04-30)**: Timer NICHT mehr hier
        // invalidieren — der Timer-Body übernimmt die Slowdown-Phase
        // (siehe `Branch 1` in `startSpin`). Invalidate-Zeitpunkt
        // wandert ans Ende der Slowdown-Phase, im Timer-Body bei
        // `t >= 1.0`. Dadurch feuert der Click-Hook weiter während
        // die Speed sinkt — User-Spec „Casino-Feeling".

        let pool = resolvedPool()
        let n = pool.count
        guard n > 0 else {
            spinTimer?.invalidate()
            spinTimer = nil
            onSettle(nil)
            return
        }

        // Ziel-Symbol-Index im Pool bestimmen.
        let targetIndex: Int
        if let t = target,
           let idx = pool.firstIndex(where: { $0.label == t.label && $0.isElumi == t.isElumi }) {
            targetIndex = idx
        } else {
            targetIndex = Int.random(in: 0..<n)
        }

        // **Deterministisches Snapping (V4.2 Index-basiert)**.
        //
        // Middle-Row zeigt extendedSymbols[s+1] bei offsetSlots=s (mit
        // Wrap-Modulo). Damit im Fenster Pool[targetIndex] zentriert
        // erscheint, muss gelten:
        //    (s mod n) == (targetIndex - 1 + n) % n  =  desiredResidue
        //
        // `target_s` wird hier als **Ganzzahl** konstruiert — dadurch
        // ist `target_s mod n` garantiert ein ganzzahliger Slot-Index,
        // der `visualOffset` auf ein exaktes Vielfaches von `slotHeight`
        // abbildet. Kein halbes Icon, keine Pixel-Drift.
        let current = offsetSlots
        let extraRevolutions = 3
        let floorCurrent = floor(current)
        var target_s = floorCurrent + Double(n * extraRevolutions)
        let desiredResidue = (targetIndex - 1 + n) % n
        let currentResidue = Int(target_s.truncatingRemainder(dividingBy: Double(n)))
        let delta = (desiredResidue - currentResidue + n) % n
        target_s += Double(delta)

        #if DEBUG
        let finalOffsetPixels = -CGFloat(desiredResidue) * slotHeight
        print("🎰 [performStop] target=\(pool[targetIndex].label) targetIndex=\(targetIndex) desiredResidue=\(desiredResidue) target_s=\(target_s) finalOffset=\(finalOffsetPixels)pt (from offsetSlots=\(current)) — handing to slowdown branch")
        #endif

        // **Slowdown-Refactor (2026-04-30)**: statt `withAnimation(
        // .easeOut)` setzen wir hier nur die Slowdown-State-Vars.
        // Timer-Body (Branch 1 in `startSpin`) interpoliert
        // `offsetSlots` von `slowdownStartOffset` zu
        // `slowdownTargetOffset` über `slowdownDuration` mit
        // Position-Curve `1 - (1-t)²`. Bei t≥1 invalidiert der Timer
        // sich selbst und ruft `onSettle(slowdownTargetSymbol)`.
        //
        // Vorteil ggü. SwiftUI-Animation: Click-Hook im Timer-Body
        // bleibt aktiv, Frequenz fällt natürlich mit der Speed.
        slowdownStartOffset = current
        slowdownTargetOffset = target_s
        slowdownTargetSymbol = pool[targetIndex]
        slowdownStartAt = Date()
    }
}

// MARK: - Array-Safe-Index

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
