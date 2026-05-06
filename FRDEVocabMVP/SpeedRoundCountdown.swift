// SpeedRoundCountdown.swift
// **2026-05-06** — Shared Countdown-Komponente für alle Speed-Modus-
// Starts (Akzente, Training-allgemein, Verbformen). Vorher hatte jedes
// Modul einen eigenen 3-2-1-Countdown (drei Scheduler, drei Render-
// Stellen, leicht unterschiedliche Animationen). Mit dieser Datei:
//
//   • `SpeedCountdownPhase` — gemeinsamer Phase-Typ ersetzt die alten
//     `Int?`-States in AccentSessionEngine, TrainingView (general und
//     Verbformen).
//   • `SpeedRoundCountdownOverlay` — die View-Komponente, die je nach
//     Phase „Achtung…", „3", „2", „1" oder „Los geht's!" rendert
//     (Scale-In + Pop-Bounce, ID-getriebene Transitions zwischen
//     Phasen).
//   • `SpeedRoundCountdownSequencer` — der Pflasterer, der Audio,
//     Haptik und Phase-Transitionen zentral schedult. Module rufen
//     einmal `start(...)` auf und übergeben einen `apply`-Closure für
//     den lokalen State + einen `onComplete`-Closure für den Engine-
//     Start.
//
// Sequenz-Spec:
//   • „Achtung…"   1.0 s  — Scale-In + Hold (kein Pop), kein Sound
//   • „3"          0.7 s  — Scale-In + Pop, `playToggle` + light Haptik
//   • „2"          0.7 s  — Scale-In + Pop, `playToggle` + light Haptik
//   • „1"          0.7 s  — Scale-In + Pop, `playToggle` + light Haptik
//   • „Los geht's!"1.0 s  — Scale-In + Hold, `playLaunch` + medium Haptik
//   • Cross-Fade auf erste Frage (Caller blendet Overlay weg, indem
//     er Phase auf nil setzt; SwiftUI-Transition cross-faded automatisch)
//
// Total ~4.1 s — User-Spec akzeptabel als bewusste „Mach-dich-bereit"-
// Zone. Nicht skip-bar (Spec).

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Phase des Speed-Round-Intro-Countdowns. Ein gemeinsamer Typ für
/// alle Module, damit Render und Scheduler appweit identisch ticken.
///
/// `nil` (= Property optional) bedeutet „Countdown nicht aktiv";
/// `.warning ... .go` ist die fünf-stufige Sequenz vor dem Engine-
/// Start.
enum SpeedCountdownPhase: Hashable, CaseIterable {
    case warning   // „Achtung…"
    case three     // „3"
    case two       // „2"
    case one       // „1"
    case go        // „Los geht's!"

    /// Display-Text auf dem Overlay.
    var displayText: String {
        switch self {
        case .warning: return "Achtung…"
        case .three:   return "3"
        case .two:     return "2"
        case .one:     return "1"
        case .go:      return "Los geht's!"
        }
    }

    /// Wie lange diese Phase auf dem Screen steht, bevor die nächste
    /// kommt (oder, im Fall von `.go`, der Caller den Overlay weg-
    /// fadet).
    ///
    /// **2026-05-06 Tweak**: `.go` von 0.5 → 1.0 s — User-Spec
    /// „Los geht's halbe Sekunde länger lassen". Die finale Phase
    /// soll als bewusster „Atemholen"-Moment wirken, bevor die
    /// erste Frage erscheint.
    var duration: TimeInterval {
        switch self {
        case .warning: return 1.0
        case .three:   return 0.7
        case .two:     return 0.7
        case .one:     return 0.7
        case .go:      return 1.0
        }
    }

    /// Schriftgröße für den Display-Text. Zahlen sind groß und fett
    /// („3", „2", „1"), Wort-Phasen sind kleiner damit der Text auf
    /// kompakten Geräten nicht abgeschnitten wird.
    var fontSize: CGFloat {
        switch self {
        case .warning: return 48  // „Achtung…" passt in 48pt
        case .go:      return 44  // „Los geht's!" passt in 44pt
        case .three, .two, .one:
            return 96             // Zahlen dürfen prominent sein
        }
    }

    /// Pop-Bounce nach Scale-In? Zahlen ja, Wort-Phasen nein
    /// (würde unruhig wirken).
    var hasPopBounce: Bool {
        switch self {
        case .three, .two, .one: return true
        case .warning, .go:      return false
        }
    }
}

/// Vollbild-Overlay-View, die genau eine Phase rendert. Caller binden
/// den `phase` als optional an — bei nil erscheint nichts.
///
/// Animation: Scale 0.5 → 1.0 + Opacity 0 → 1, Phase-Transition über
/// `.id(phase)` damit SwiftUI bei jedem Wechsel eine frische
/// Insert/Remove-Transition spielt. Pop-Bounce für Zahlen über
/// Spring-Response.
///
/// Hintergrund: dezenter Akzent-Tint + Backdrop-Blur. Caller liefert
/// den `tint` (z. B. Modul-Akzent).
struct SpeedRoundCountdownOverlay: View {
    let phase: SpeedCountdownPhase
    let tint: Color

    /// State-Var für die initiale Scale-In-Animation pro Phase. Wird
    /// in `.onAppear` von 0.5 auf 1.0 animiert (Spring für Pop-Phasen,
    /// EaseOut für Wort-Phasen).
    @State private var scale: CGFloat = 0.5

    var body: some View {
        ZStack {
            // Vollflächiger Dim — beim Countdown soll der Session-
            // Content vollständig verschwinden, damit der User nur
            // auf den Countdown fokussiert ist. **2026-05-06 Smoke-
            // Fix**: 0.92 → 0.99 Opacity (User-Feedback „mehr dimmen,
            // man sieht sonst zuviel vom Hintergrund"). Praktisch
            // opak, lässt aber theoretisch noch eine leichte Akzent-
            // Schimmer zu, falls darunter ein farbiger Background
            // liegt.
            Color.black.opacity(0.99)
                .ignoresSafeArea()

            // Akzent-Glow im Hintergrund (radialer Verlauf), sehr
            // weich. Holt den Modul-Charakter (Akzente-Pink, Training-
            // Blau usw.) ins Overlay, ohne den Text zu überlagern.
            // **2026-05-06**: Inner-Stop reduziert (0.35 → 0.22),
            // damit der Glow nur noch eine sanfte Akzent-Wolke um
            // den Text bildet, statt den Center sichtbar aufzuhellen.
            RadialGradient(
                colors: [tint.opacity(0.22), tint.opacity(0.04), .clear],
                center: .center,
                startRadius: 60,
                endRadius: 320
            )
            .ignoresSafeArea()

            Text(phase.displayText)
                .font(.system(size: phase.fontSize, weight: .black, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)
                .multilineTextAlignment(.center)
                .shadow(color: tint.opacity(0.55), radius: 18, x: 0, y: 0)
                .scaleEffect(scale)
                .id(phase)
        }
        .transition(.opacity)
        .onAppear {
            // Reset auf 0.5 (View ist neu — `.id(phase)` re-mountet
            // den Text bei jeder Phase, deshalb läuft `.onAppear`
            // pro Phase).
            scale = 0.5
            if phase.hasPopBounce {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
                    scale = 1.05
                }
                // Sanftes Setzen nach dem Pop, damit die nächste
                // Phase nicht mit einem >1.0-Wert übergeht.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    withAnimation(.easeOut(duration: 0.12)) {
                        scale = 1.0
                    }
                }
            } else {
                withAnimation(.easeOut(duration: 0.28)) {
                    scale = 1.0
                }
            }
        }
    }
}

/// Cancel-Handle für eine laufende Countdown-Sequenz. Caller (Module)
/// halten die Instanz und rufen `cancel()` beim Cleanup (View
/// disappears, Session-Reset, Home-Tap), damit pending DispatchWork-
/// Items nicht mehr feuern und keine Audio-Ticks oder Engine-Starts
/// mehr im Hintergrund passieren.
///
/// **2026-05-06** — Eingeführt nach User-Bug-Report „läuft im
/// Hintergrund weiter" (Home-Tap während aktiver Speed Round). Das
/// alte sequenz-API ohne Cancel-Möglichkeit hatte zwei Klassen von
/// Leaks:
///   1. Tick-Sounds (`playToggle`) feuerten weiter, weil
///      `feedbackPlayer` strong-captured war.
///   2. `onComplete()` startete die Engine-Speed-Round-Timer auch dann,
///      wenn die View-Hierarchie schon weg war — der Timer tickte
///      dann ewig, mit Audio-Output, ohne dass irgendein Cleanup-
///      Pfad ihn fing.
final class SpeedRoundCountdownTask {
    private var workItems: [DispatchWorkItem] = []
    private var isCancelled = false

    fileprivate init() {}

    /// Item registrieren. Wenn der Task schon gecancelt ist (Race-
    /// Bedingung beim sehr-frühen Cancel), cancelt das Item sofort.
    fileprivate func add(_ item: DispatchWorkItem) {
        guard !isCancelled else {
            item.cancel()
            return
        }
        workItems.append(item)
    }

    /// Cancelt alle pending Items. Idempotent — mehrfacher Aufruf ist
    /// safe (zweiter Call ist No-Op).
    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        workItems.forEach { $0.cancel() }
        workItems.removeAll()
    }
}

/// Pflasterer für die ganze Sequenz. Nutzt DispatchWorkItems +
/// `DispatchQueue.main.asyncAfter` zum Schedulen der Phase-
/// Transitionen + Audio-/Haptik-Calls.
///
/// **Usage** (gleicher Pattern in allen 3 Modulen):
/// ```
/// self.countdownTask = SpeedRoundCountdownSequencer.start(
///     feedbackPlayer: feedbackPlayer,
///     apply: { phase in self.speedCountdownPhase = phase },
///     onComplete: { startSpeedRoundTimer() }
/// )
/// ```
/// Beim Cleanup (View-Disappear, Reset, Home-Tap):
/// ```
/// countdownTask?.cancel()
/// countdownTask = nil
/// ```
///
/// **Active-Guard im Caller**: zusätzlich zum Task-Cancel sollten
/// `apply` und `onComplete` einen Module-State-Check (`isActive`,
/// `[weak self]`) machen — defensiv gegen Race-Bedingungen, in denen
/// das Cancel-Signal die Item-Execution knapp verpasst.
enum SpeedRoundCountdownSequencer {
    /// Startet die fünf-Phasen-Sequenz. Liefert ein `SpeedRound-
    /// CountdownTask` zurück, das der Caller halten und beim Cleanup
    /// cancellen muss.
    @discardableResult
    static func start(
        feedbackPlayer: FeedbackPlayer,
        apply: @escaping (SpeedCountdownPhase?) -> Void,
        onComplete: @escaping () -> Void
    ) -> SpeedRoundCountdownTask {
        let task = SpeedRoundCountdownTask()

        // Phase 1 — „Achtung…" (synchron, sofort).
        // **Audio-Strategie**: für die Wort-Phasen (Achtung / Los
        // geht's!) nutzen wir keinen Tick-Sound — der Tick „passt"
        // zur Zahl, nicht zum Wort. „Los geht's!" bekommt am Ende
        // `playLaunch` (siehe Phase 5).
        apply(.warning)
        triggerHaptic(style: .light)

        // **DispatchWorkItem + MainActor**: WorkItem-Closures sind
        // standardmäßig nicht @MainActor-isoliert; FeedbackPlayer's
        // `playToggle/playLaunch` sind aber @MainActor-Methoden.
        // Wir holen das via `MainActor.assumeIsolated` rein —
        // safe weil wir die Items via `DispatchQueue.main.asyncAfter`
        // schedulen, also läuft die Execution garantiert auf
        // dem Main-Thread.

        // Phase 2 — „3", nach 1.0 s.
        let item3 = DispatchWorkItem {
            MainActor.assumeIsolated {
                apply(.three)
                feedbackPlayer.playToggle()
                triggerHaptic(style: .light)
            }
        }
        task.add(item3)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: item3)

        // Phase 3 — „2", nach 1.0 + 0.7 = 1.7 s.
        let item2 = DispatchWorkItem {
            MainActor.assumeIsolated {
                apply(.two)
                feedbackPlayer.playToggle()
                triggerHaptic(style: .light)
            }
        }
        task.add(item2)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.7, execute: item2)

        // Phase 4 — „1", nach 2.4 s.
        let item1 = DispatchWorkItem {
            MainActor.assumeIsolated {
                apply(.one)
                feedbackPlayer.playToggle()
                triggerHaptic(style: .light)
            }
        }
        task.add(item1)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.4, execute: item1)

        // Phase 5 — „Los geht's!", nach 3.1 s. Stärkerer Sound +
        // medium Haptik, weil das den Übergang zur Übung markiert.
        let itemGo = DispatchWorkItem {
            MainActor.assumeIsolated {
                apply(.go)
                feedbackPlayer.playLaunch()
                triggerHaptic(style: .medium)
            }
        }
        task.add(itemGo)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.1, execute: itemGo)

        // Cleanup — nach 3.1 + 1.0 = 4.1 s. Phase auf nil → Overlay
        // wird ausgeblendet (SwiftUI cross-faded via .transition(.opacity)
        // im Caller-Wrapper). Engine-Start direkt im selben Schritt.
        // **2026-05-06 Tweak**: war 3.6 s, jetzt 4.1 s — `.go`-Phase
        // hält 0.5 s länger (siehe Doc-Kommentar in
        // `SpeedCountdownPhase.duration`).
        let itemCleanup = DispatchWorkItem {
            MainActor.assumeIsolated {
                apply(nil)
                onComplete()
            }
        }
        task.add(itemCleanup)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.1, execute: itemCleanup)

        return task
    }

    /// Haptic-Helper. Inline-Generator-Pattern, kein zentraler
    /// HapticController nötig (siehe AccentsEntryView etc., die das
    /// gleiche Pattern nutzen).
    ///
    /// **Concurrency-Hinweis**: kein @MainActor-Annotation, weil
    /// alle Aufrufer aus DispatchQueue.main-Kontexten kommen
    /// (asyncAfter auf .main, plus der initiale sync-Call läuft im
    /// View-Body-Pfad). UIImpactFeedbackGenerator selbst muss auf
    /// dem Main-Thread laufen — die Aufrufer sichern das schon.
    private static func triggerHaptic(style: UIImpactFeedbackGenerator.FeedbackStyle) {
        #if canImport(UIKit)
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
        #endif
    }
}
