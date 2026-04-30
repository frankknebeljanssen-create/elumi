import SwiftUI

enum ElumiArcadeDropKind: Equatable {
    case wuermchen
    case wasserfloh
    case algenkugel
    case bonusblase
    case saugglocke
    case slowMotionPotion
    case falseElumi
    /// Power-Up — schützt den Spieler kurzzeitig vor jedem Schaden-
    /// Kontakt. Spawnt im oberen Drittel mit Scale-In statt Fall-In.
    /// Eingeführt als Referenz für das einheitliche
    /// `ArcadePowerUpType`-System.
    case shieldBubble

    var snackKind: ElumiSnackKind? {
        switch self {
        case .wuermchen:
            return .wuermchen
        case .wasserfloh:
            return .wasserfloh
        case .algenkugel:
            return .algenkugel
        case .bonusblase, .saugglocke, .slowMotionPotion, .falseElumi, .shieldBubble:
            return nil
        }
    }

    var isSnack: Bool {
        snackKind != nil
    }
}

/// Central configuration for arcade round difficulty — single source of truth.
struct ArcadeRoundConfig {
    let round: Int

    // ── Spawn rates ──
    var bonusChance: Double {
        switch round {
        case 4: return 0.14          // Bonus-Regen
        case 5: return 0.055         // Elumi-Freunde
        default: return round >= 6 ? 0.10 : 0.055
        }
    }

    var suctionChance: Double {
        switch round {
        case 4: return 0.12
        case 5: return 0.07
        default: return round >= 6 ? 0.10 : 0.07
        }
    }

    var falseElumiChance: Double {
        switch round {
        case 4: return min(0.10, 0.04 + (Double(round - 1) * 0.02))
        case 5: return 0.20           // Elumi-Freunde: many
        default: return round >= 6 ? 0.16 : min(0.12, 0.04 + (Double(round - 1) * 0.02))
        }
    }

    var slowMotionPotionChance: Double { round >= 2 ? 0.04 : 0.0 }

    // ── Speed (smoothed curve) ──
    //
    // **User-Feedback R7-8 zu sprunghaft**: Vorher lineare Abnahme
    // (−0.13s/−0.4s pro Runde mit hartem Floor) — das erzeugte R1–R7
    // stetigen Speedup und dann abrupten Floor-Knick.
    //
    // Neu: **exponentielle Abnahme** `plateau + (start − plateau) *
    // exp(−k · (r − 1))` — frühe Runden spürbar leicht, mittlere
    // Runden fordern, späte Runden hoch aber nicht explosiv. Kein
    // harter Sprung, keine Kante.
    //
    // Beispiel `spawnDelay`:
    //   R1 = 1.00s (sehr locker)
    //   R3 = 0.80s
    //   R5 = 0.65s
    //   R7 = 0.55s
    //   R10 = 0.48s
    //   R15 = 0.43s (asymptotisch → 0.40s Plateau)
    var spawnDelay: Double {
        let plateau: Double = 0.40
        let start: Double = 1.00
        let k: Double = 0.22
        return plateau + (start - plateau) * exp(-k * Double(round - 1))
    }

    /// Fall-Dauer analog exponentiell — frühe Runden haben viel Zeit,
    /// späte Runden bleiben forderbar ohne die alten 1.45s-Bluffs.
    ///   R1 = 4.00s, R3 = 3.25s, R5 = 2.70s, R7 = 2.28s, R10 = 1.88s,
    ///   R15 = 1.62s (Plateau 1.50s).
    var fallDuration: Double {
        let plateau: Double = 1.50
        let start: Double = 4.00
        let k: Double = 0.18
        return plateau + (start - plateau) * exp(-k * Double(round - 1))
    }

    // ── Querschläger (smoothed ramp) ──
    //
    // Vorher gab es einen **harten Sprung** zwischen R3 (20 % Chance,
    // sanftes Wobble) und R4 (30 % Chance, aggressive Amplitude/
    // Frequenz). Das ist einer der beiden Hauptgründe, warum sich R7-8
    // so sprunghaft anfühlt — zu dem Zeitpunkt ist der
    // Querschläger-Preset schon auf Max.
    //
    // Neu: graduelle Ramp mit Power-Kurve. R1-2 keine Querschläger,
    // R3+ langsam ansteigend bis R10 mit Maximum. Amplitude und
    // Frequenz skalieren linear über die gleiche Kurve.
    var querschlaegerChance: Double {
        guard round >= 3 else { return 0.0 }
        let progress = min(1.0, pow(Double(round - 2) / 8.0, 0.6))
        return 0.32 * progress
    }

    /// Smooth-interpolierte Wobble-Amplitude: R1 (0.05…0.10) →
    /// R10+ (0.15…0.30). Kein harter Step bei R4 mehr.
    var querschlaegerAmplitude: ClosedRange<CGFloat> {
        let f = querschlaegerRampProgress
        let lower = CGFloat(0.05 + f * 0.10)
        let upper = CGFloat(0.10 + f * 0.20)
        return lower...upper
    }

    /// Smooth-interpolierte Wobble-Frequenz: R1 (1.5…3.5 Hz) →
    /// R10+ (4.0…6.5 Hz).
    var querschlaegerFrequency: ClosedRange<Double> {
        let f = querschlaegerRampProgress
        let lower = 1.5 + f * 2.5
        let upper = 3.5 + f * 3.0
        return lower...upper
    }

    /// Gemeinsame 0…1-Progress-Variable für Amplitude/Frequenz —
    /// hält die beiden synchron und den Code DRY.
    private var querschlaegerRampProgress: Double {
        min(1.0, max(0.0, Double(round - 1) / 9.0))
    }

    // ── Snacks per round ──
    var snacksRequired: Int { 12 }

    // ── Bonus round ──
    var isBonusRoundTrigger: Bool { round % 3 == 0 }

    // ── Jellyfish (smoothed ramp) ──
    //
    // Vorher: R1-2 = 0, R3 = 0.008, R4+ = 0.012 (Step-Funktion).
    // Neu: graduell von R3 (0.005) zu R7+ (0.015) mit Power-Kurve,
    // damit die Quallen-Frequenz kein abrupter Sprung bei R4 mehr ist.
    var jellyfishChance: Double {
        guard round >= 3 else { return 0.0 }
        let progress = min(1.0, pow(Double(round - 2) / 5.0, 0.7))
        return 0.015 * progress
    }
}

struct JellyfishState: Identifiable, Equatable {
    let id = UUID()
    let spawnedAt: Date
    let fromLeft: Bool
    let normalizedY: CGFloat      // 0.15–0.40
    let speed: Double             // 7–10s crossing time
    let wobblePhase: Double
    var tentaclesDropped: Int = 0
    var lastTentacleDropAt: Date?
}

struct TentacleDropState: Identifiable, Equatable {
    let id = UUID()
    let spawnedAt: Date
    let startY: CGFloat           // Quallen-Y beim Abwurf (screen coords)
    let normalizedX: CGFloat      // X-Position beim Abwurf (0–1)
    let wobbleAmplitude: CGFloat  // 0.02–0.05
    let fallDuration: Double      // 2.8–3.5s
}

struct BonusFishState: Identifiable, Equatable {
    let id = UUID()
    let spawnedAt: Date
    let fromLeft: Bool
    let normalizedY: CGFloat
    let speed: Double
    let wobblePhase: Double
    let renderScale: CGFloat     // 1.0-3.0
    var isCaught: Bool = false
}

/// **Ambient-Sea-Creature** — rein visuelles Event: einzelner Hai oder
/// Schwarm-Fisch, der im Hintergrund durchs Spielfeld zieht. Pro
/// Runde maximal einmal, rein dekorativ (keine Kollision, kein
/// Gameplay-Effekt).
///
/// Ziel: dem Arcade-Stage mehr Leben geben, den User an ein atmendes
/// Unterwasser-Ökosystem erinnern, ohne die Spielmechanik zu belasten.
struct AmbientSeaCreatureState: Identifiable, Equatable {
    enum Kind {
        /// Kleiner Fisch-Schwarm — mehrere Silhouetten nah beieinander.
        case fishSchool
        /// Größerer Hai — einzelne Silhouette, bewegt sich langsamer.
        case shark
    }

    let id = UUID()
    let kind: Kind
    let spawnedAt: Date
    let fromLeft: Bool
    /// Normalisierte Y-Position (0…1), in welchem Bereich des
    /// Screens die Kreatur zieht. Obere zwei Drittel (0.2–0.65),
    /// damit sie nicht mit Elumi kollidiert.
    let normalizedY: CGFloat
    /// Crossing-Dauer in Sekunden — Fisch schneller (4–6 s), Hai
    /// langsamer (7–10 s).
    let speed: Double
    /// Sinus-Phase für sanfte vertikale Wellenbewegung.
    let wobblePhase: Double
}

struct ElumiArcadeSnackState: Identifiable, Equatable {
    let id = UUID()
    let kind: ElumiArcadeDropKind
    let spawnedAt: Date
    let laneX: CGFloat
    let wobbleAmplitude: CGFloat
    let wobbleFrequency: Double
    let fallDuration: Double
    let rotationDrift: Double
    let renderScale: CGFloat
    let motionPhase: Double
    let points: Int
}

struct ElumiArcadeGameView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.appSetImmersiveArcadeAction) var setImmersiveArcade
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    @AppStorage(appElumiArcadeHighScoreKey) var highScore = 0
    @AppStorage(appArcadeCreditsKey) var arcadeCredits = 0
    /// **Play-Credits** (2026-04-24 Test-System) — persistent durch
    /// Slot-Spins verdient, im Spiel für Rescue (Tot-abwenden) und
    /// Skip (Runde überspringen) verbraucht. Bewusst getrennt vom
    /// globalen `arcadeCredits` („1 Credit = 1 Spielstart").
    @ObservedObject var playCredits = ElumiCreditsStore.shared
    /// Wenn `true`, ist bereits eine Rescue-Entscheidung für das
    /// aktuelle Game-Over gefallen (Accept oder Skip). Verhindert
    /// Doppel-Taps und das wiederholte Anzeigen des Prompts.
    @State var rescueConsumedForCurrentGameOver: Bool = false
    /// Wenn `true`, wird das Start-Overlay übersprungen und das Spiel beginnt
    /// direkt — Credit-Abzug und „Spiel starten"-CTA sind dann Aufgabe der
    /// aufrufenden View (z. B. `GameHubView`). Default `false` bewahrt das
    /// bisherige Verhalten für den Footer-Elumi-Quick-Launch.
    var autoStart: Bool = false

    /// **Quick-Fix 2026-04-30 (`v2-elumi-gameover-cta-home`)** —
    /// Optionaler Home-Navigations-Closure, vom AppDestinationHost
    /// durchgereicht. Wird von der „Lernen starten"-CTA (im
    /// `gameOverOverlay` und im `startOverlay`) genutzt, um den User
    /// bei 0 Credits zur Startseite zurückzubringen statt nur eine
    /// Nav-Stack-Ebene zu poppen (was vorher fälschlich zum Spiele-
    /// Screen führte). Pattern analog zu `WordRunnerGameView.onClose`.
    /// Optional, damit bestehende Call-Sites (Tests etc.) nicht
    /// brechen — die regulären App-Pfade reichen den Closure jetzt
    /// durch.
    var goHome: (() -> Void)? = nil

    @State var gameSeed = UUID()
    @State var gameSize: CGSize = .zero
    @State var gameClock = Date()
    @State var lastFrameDate: Date?
    @State var elumiX: CGFloat = 0.5
    @State var activeSnacks: [ElumiArcadeSnackState] = []
    @State var score = 0
    @State var misses = 0
    @State var isPlaying = false
    @State var isGameOver = false
    // Hinweis: Initialwert des Overlays wird in der konsumierenden View
    // `ElumiArcadeGameView+Layout.swift` via `.onAppear` je nach `autoStart`
    // angepasst. Wir starten default mit dem Overlay, damit alte Call-Sites
    // (Footer-Elumi) unverändert funktionieren.
    @State var showingStartOverlay = true
    @State var mouthOpen = false
    @State var characterScale: CGFloat = 1
    @State var characterRotation: Double = 0
    @State var sparkleBurst = false
    @State var comboCount = 0
    @State var bestCombo = 0
    @State var totalCaught = 0
    @State var lastCatchDate: Date?
    @State var comboBannerText: String?
    @State var didBeatHighScore = false
    @State var suctionEndsAt: Date?
    @State var suctionDockScale: CGFloat = 1.0
    @State var bonusPointsEndsAt: Date?
    @State var slowMotionEndsAt: Date?
    /// **Schutz-Bubble-Aktivzustand** — Timestamp-basiert, parallel
    /// zur formalen `powerUpRuntime`-State-Machine. Beide werden
    /// synchron geschrieben; Reader dürfen wahlweise `shieldBubbleEndsAt`
    /// (Legacy, direkt) oder `powerUpRuntime.hasActiveShield(at:)`
    /// (formal, state-checked) konsultieren. Künftige Slices migrieren
    /// Reader schrittweise zur Runtime-Version.
    @State var shieldBubbleEndsAt: Date?
    /// Scale-Impuls beim Einsammeln der Bubble — kurzer Puls vom
    /// Bubble-Asset zum Spieler, damit das Power-Up visuell „andockt".
    @State var shieldBubbleDockScale: CGFloat = 1.0
    /// Zeitpunkt des letzten Kollisions-Events (Schild wurde getroffen).
    /// Die Overlay-Renderfunktion berechnet daraus einen expandierenden
    /// Ripple-Kreis (0…1 Progress über 300 ms). Nil = kein Ripple
    /// aktiv.
    @State var shieldBubbleRippleAt: Date?
    /// Zentrale Sound-Hook-Instanz. Game-Code ruft ausschließlich hier
    /// — nicht mehr direkt auf dem `FeedbackPlayer`. Siehe `ArcadeSFX`
    /// für die fünf Event-Typen (spawn/pickup/activate/collision/end)
    /// + Debouncing-Verhalten.
    @State var arcadeSFX: ArcadeSFX?
    /// **Zentrale Power-Up-Runtime** — Single Source of Truth für
    /// Lifecycle-States, Cooldowns, Ambient-Event-Lock. Siehe
    /// `ArcadePowerUpRuntime` für State-Machine-Details.
    @StateObject var powerUpRuntime = ArcadePowerUpRuntime()
    /// Zentrale Dichte-Kontrolle: verhindert, dass mehrere Power-Ups
    /// zu kurz nacheinander spawnen oder mehrere gleichzeitig auf dem
    /// Screen liegen. Wird von `spawnSnack()` vor jedem Roll konsultiert.
    @State var powerUpSpawnGate = ArcadePowerUpSpawnGate()
    @State var screenShakeOffset: CGFloat = 0

    /// **Quick-Fix 2026-04-30 (`v2-elumi-gameover-cta-home`)** — Zeitstempel
    /// des letzten Lebens-Verlusts. Wird in `triggerLifeLossVisual()`
    /// gesetzt; das Layout-Overlay rendert basierend auf dieser Zeit
    /// einen kurzen roten Flash über dem Charakter (~0.5s) plus einen
    /// Scale-Zucker. Sichtbares Feedback bei jedem `misses += 1`-
    /// Event, damit der User merkt: er hat gerade ein Leben verloren.
    /// User-Report: „wenn elumi ein leben verliert muss man das an
    /// ihm sehen — vorschlag? Blitz? zucken, zumindest was, was
    /// sichtbar ist".
    @State var lifeLostFlashAt: Date?
    @State var gameOverTitle = "Game Over"
    @State var gameOverSubtitle = ""
    @State var round = 1
    @State var roundCatchCount = 0
    @State var roundSuctionSpawned = false
    @State var showingRoundBanner = false
    @State var roundBannerPhase = 0  // 0=geschafft, 1=ready blink, 2=done
    @State var readyBlinkVisible = true
    @State var elumiVisible = false

    // Bonus fish round
    @State var isBonusRound = false
    @State var bonusFishCaught = 0
    @State var bonusFishSpawned = 0
    @State var activeFish: [BonusFishState] = []
    @State var elumiY: CGFloat = 0.5
    @State var bonusRoundStartedAt: Date?
    @State var bonusRoundResultText: String?
    @State var bonusRoundWaitingForTap = false
    let bonusFishTotal = 15
    let bonusRoundDuration: TimeInterval = 12.0

    // Jellyfish
    @State var activeJellyfish: JellyfishState?
    @State var activeTentacles: [TentacleDropState] = []
    @State var jellyfishStingCount = 0

    // Ambient Sea-Creature (Fish/Shark Event) — per-round one-shot
    @State var ambientSeaCreature: AmbientSeaCreatureState?
    /// Merker: wurde das Event in dieser Runde bereits gespawnt?
    /// Wird bei Rundenwechsel zurückgesetzt.
    @State var ambientEventFiredThisRound: Bool = false

    // Phase 4 – Start-Overlay: Spielregeln sind per Default eingeklappt,
    // damit der CTA und der Credit-Status die primäre Aufmerksamkeit
    // bekommen. Der User kann die Regeln bei Bedarf ausklappen.
    @State var isShowingArcadeRules = false

    /// **Start-Leben** pro Runde. `static` damit der Start-Screen-
    /// Card (Phase 7.5) den Wert lesen kann, ohne eine Instanz zu
    /// brauchen — der Credit-Hero-Card zeigt vor dem Start schon
    /// „4 Leben" + 4 Mini-Elumis.
    static let maxMisses = 4
    var maxMisses: Int { Self.maxMisses }
    let suctionDuration: TimeInterval = 4.6
    let bonusPointsDuration: TimeInterval = 5.0
    let slowMotionDuration: TimeInterval = 0.55
    let slowMotionPotionDuration: TimeInterval = 5.0
    let suctionBeamHalfWidth: CGFloat = 92
    /// Dauer der aktiven Schutz-Bubble.
    ///
    /// **Phase 2** (User-Wunsch „Bubble-Nutzen erhöhen"): von 4.6 s
    /// auf **6.6 s** angehoben. Der Schild fühlt sich dadurch
    /// wertvoller an und gibt dem User echten Raum, entspannt Snacks
    /// zu sammeln (siehe Policy-Reversal: Snacks sammeln während
    /// Shield ist jetzt erlaubt, nur Damage-Kontakte werden geblockt).
    let shieldBubbleDuration: TimeInterval = 6.6

    var headerTitle: String {
        if isGameOver { return "Spiel vorbei" }
        if showingStartOverlay { return "Elumi Spiel" }
        return "Runde \(round)"
    }

    func snacksForRound(_ r: Int) -> Int {
        ArcadeRoundConfig(round: r).snacksRequired
    }

    var roundSubtitle: String {
        switch round {
        case 1: return "Los geht's!"
        case 2: return "🧪 Zeitlupe-Trank!"
        case 3: return "Querschläger!"
        case 4: return "Bonus-Regen!"
        case 5: return "Elumi-Freunde!"
        default: return "Chaos!"
        }
    }

}
