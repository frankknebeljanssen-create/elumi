import Foundation
import SwiftUI
import Combine
import UIKit

/// **Trainings-Session-Auto-Verkettung — Chain-Store**
/// (Stufe 1, 2026-04-30, Branch `feature/training-session-flow`).
///
/// In-Memory-Store für die aktuell laufende Trainings-Chain. Wird im
/// `ElumiTabView`-Scope als `@StateObject` gehalten und beim Slot-Spin
/// neu befüllt. **Persistiert NICHT** — Chain überlebt App-Restart
/// bewusst nicht (User-Spec: nach Restart frisch beim Setup-Modal).
///
/// Verantwortlichkeiten:
///   • `currentChain`: aktueller Chain-Context (nil = keine aktive Chain)
///   • `stepOutcomes`: aggregierte Reward-Outcomes pro Modul-Step (für
///     End-Summary in Stufe 4 — Stufe 1 sammelt nur, nutzt sie noch nicht)
///   • `start(_:)`: setzt Context, clear-t Resume-Stores aller drei
///     Module-Stores (Training/Quiz/Akzente) — User-Spec R5: keine
///     Resume-Konflikte mit Chain-Lauf.
///   • `advance()`: rotiert auf den nächsten Step (Stufe 2 nutzt das
///     aus den Modul-CTAs)
///   • `recordOutcome(_:)`: pusht ein abgeschlossenes Step-Result in
///     `stepOutcomes` (Stufe 4 zeigt das im End-Summary aggregiert)
///   • `clear()`: Setzt alles zurück — am Chain-Ende oder bei Abbruch.
@MainActor
final class TrainingChainStore: ObservableObject {
    /// **Stufe 2 (2026-04-30)** — Singleton. Pattern analog zu
    /// `ProgressStore.shared`, `AccountStore.shared`,
    /// `ElumiCreditsStore.shared`. Begründung: ab Stufe 2 wird der
    /// Store von mindestens **zwei Stellen** referenziert
    /// (`ElumiTabView` für Slot-Spin → Chain-Init, plus
    /// `TrainingChainOverviewView` für Back-Chevron-Clear). Singleton
    /// vermeidet Pass-Through über AppRuntimeContainer und matcht
    /// existierendes Codebase-Pattern für In-Memory-only Stores.
    static let shared = TrainingChainStore()

    @Published private(set) var currentChain: TrainingChainContext?
    @Published private(set) var stepOutcomes: [SessionRewardOutcome] = []

    // MARK: - Stufe 4a: Step-Countdown-Timer (2026-05-01)

    /// **Stufe 4a (2026-05-01, Branch `feature/training-session-flow`)** —
    /// Verbleibende Sekunden im aktuellen Chain-Step. 0 = Zeit ist um
    /// (Soft-Cutoff, siehe `timerExpired`). Wird vom UI-Layer
    /// (`ChainStepTimerBar` via `ChainTimerOverlayModifier`) live
    /// observiert.
    @Published private(set) var stepRemainingSeconds: Int = 0

    /// Gesamtdauer des aktuellen Chain-Steps in Sekunden (immer
    /// `chain.perStepDurationMin * 60`, außer im Smoke-Test-Override).
    /// Wird für die Progress-Bar-Normierung in der Timer-Bar gebraucht.
    @Published private(set) var stepTotalSeconds: Int = 0

    /// Soft-Cutoff-Flag: `true` heißt „Zeit ist um, Banner darf
    /// erscheinen". In Stufe 4a rein deskriptiv — der User kann
    /// trotzdem weitermachen, kein Force-Done. In Stufe 4b koppeln
    /// wir den nächsten Submit-Tap im Modul an dieses Flag, um
    /// Auto-Advance zu triggern.
    @Published private(set) var timerExpired: Bool = false

    /// **Stufe 4a-Fix (2026-05-01)** — One-shot-Flag pro Step für den
    /// `ChainCutoffToast`. Wenn der Timer abläuft, blendet der
    /// `ChainTimerOverlayModifier` einen mittigen Toast einmalig ein
    /// und setzt anschließend dieses Flag auf `true`. Re-Renders der
    /// Modul-View triggern damit keinen Re-Show des Toasts. Wird beim
    /// nächsten `startStepTimer()` (Step-Wechsel) und in
    /// `clearStepTimer()` zurück auf `false` gesetzt.
    @Published private(set) var hasShownExpirationToast: Bool = false

    /// Aktiver Sekunden-Counter. Tickt in `scheduleStepTick()`. Wird
    /// bei Background pausiert (`pauseStepTimer()`), bei Foreground
    /// weitergeführt (`resumeStepTimer()`), und bei `clear()` /
    /// `start()` / `advance()` (zum nächsten Step) aufgeräumt.
    private var stepTimer: Timer?

    /// Bei Background-Pause: hier landet der zum Pause-Zeitpunkt
    /// gültige `stepRemainingSeconds`-Wert, damit `resumeStepTimer()`
    /// von dort weiterzählt — ohne Drift, weil wir Sekunden-Counter
    /// verwenden statt Wall-Clock-Diffs (für 4-min-Steps reicht das,
    /// siehe Audit-Antwort 6).
    private var pausedRemainingSeconds: Int? = nil

    /// **Stufe 4a (2026-05-01)** — `private init` damit das
    /// Singleton-Pattern stabil bleibt (Default war implicit-public);
    /// dasselbe `init` registriert die App-Lifecycle-Notifications
    /// für Timer-Pause/Resume.
    private init() {
        registerLifecycleObservers()
    }

    private func registerLifecycleObservers() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.pauseStepTimer() }
        }
        NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.resumeStepTimer() }
        }
    }

    /// Initialisiert eine neue Chain. Clear-t **vorab** alle drei
    /// expliziten Resume-Stores (Pattern aus
    /// `GameStateResetService.swift` Z. 57-59), damit Chain-Steps nicht
    /// auf alten Resume-States stolpern (z.B. Quiz, das mitten in einer
    /// alt-abgebrochenen Session weiterläuft statt frisch zu starten).
    func start(_ chain: TrainingChainContext) {
        // **R5 Resume-Konflikt-Auflösung** (Audit-Spec): Chain-Lauf darf
        // nicht zufällig auf einen alten Resume-State eines Moduls
        // treffen. Vor dem Chain-Lauf alle drei Stores leeren.
        TrainingSessionResumeStore.clear()
        AccentSessionResumeStore.clear()
        QuizSessionResumeStore.clear()

        currentChain = chain
        stepOutcomes = []

        #if DEBUG
        let path = chain.plannedSteps.map(\.rawValue).joined(separator: " → ")
        print("🔗 [TrainingChainStore] start — id=\(chain.id.shortID), steps=[\(path)], perStep=\(chain.perStepDurationMin)min")
        #endif

        // **Stufe 4a (2026-05-01)** — Step-Timer für ersten Step
        // starten. Nur wenn die Chain einen `currentStep` hat (kein
        // Jackpot-Pfad mit leeren plannedSteps).
        if chain.currentStep != nil {
            startStepTimer()
        } else {
            clearStepTimer()
        }
    }

    /// Rotiert den Index +1. Wird in Stufe 2 von den Modul-CTAs
    /// aufgerufen, wenn der User „Weiter zur nächsten Übung" tappt.
    func advance() {
        guard let chain = currentChain else { return }
        currentChain = chain.advancedToNextStep()

        #if DEBUG
        let idx = currentChain?.currentIndex ?? -1
        let total = currentChain?.totalStepCount ?? 0
        print("🔗 [TrainingChainStore] advance — index=\(idx)/\(total)")
        #endif

        // **Stufe 4a (2026-05-01)** — Timer für den nächsten Step
        // neu starten. Wenn die Chain durch ist (kein currentStep
        // mehr), Timer komplett aufräumen — `trainingChainComplete`-
        // Platzhalter zeigt keine Zeit-Anzeige.
        if currentChain?.currentStep != nil {
            startStepTimer()
        } else {
            clearStepTimer()
        }
    }

    /// Sammelt das Outcome eines abgeschlossenen Steps für die spätere
    /// Aggregation im End-Summary (Stufe 4). Stufe 1 ruft das noch nicht
    /// auf — bleibt für Stufe-2-Hook bereit.
    func recordOutcome(_ outcome: SessionRewardOutcome) {
        stepOutcomes.append(outcome)
    }

    /// **Stufe 3 (2026-05-01, Branch `feature/training-session-flow`)** —
    /// Combo-Helper für die Modul-Done-CTAs: optional ein Outcome
    /// einsammeln, dann `advance()` aufrufen, anschließend den
    /// `AppScreen` zurückgeben, der als nächstes gepusht/replaced
    /// werden soll:
    ///
    ///   • Wenn nach dem Advance noch ein `currentStep` da ist →
    ///     `step.chainScreen(chainContext: currentChain!)` (nächstes
    ///     Modul im Chain-Modus, mit aktualisiertem `chainContext`-
    ///     Index für die korrekte „Weiter zu …"-Anzeige im Folge-CTA).
    ///   • Wenn nicht (Chain durch) → `.trainingChainComplete`
    ///     (Stufe-5-Platzhalter; End-Summary kommt dort).
    ///
    /// Returnt `nil` nur, wenn keine aktive Chain existiert — Caller
    /// fällt dann silent zurück (sollte im Chain-Mode-CTA-Pfad nicht
    /// vorkommen, defensive Absicherung).
    @discardableResult
    func advanceChain(recordedOutcome: SessionRewardOutcome? = nil) -> AppScreen? {
        if let outcome = recordedOutcome {
            recordOutcome(outcome)
        }
        advance()
        guard let chain = currentChain else { return nil }
        if let nextStep = chain.currentStep {
            return nextStep.chainScreen(chainContext: chain)
        }
        return .trainingChainComplete
    }

    /// Räumt den Store komplett ab. Wird am Chain-Ende (nach
    /// End-Summary-CTA) oder beim manuellen Abbruch aufgerufen.
    ///
    /// **Hot-Fix 2026-05-02 — Resume-Store-Symmetrie zu `start()`.**
    /// Bisher räumte `start()` die drei Modul-Resume-Stores (R5: keine
    /// Resume-Konflikte mit frisch-startender Chain), `clear()` aber
    /// nicht. Folge: ein abgebrochener Chain-Step (z.B. Quiz nach
    /// Initial-Batch von 1 Frage) hinterließ einen Resume-Snapshot,
    /// den der nächste Home-Tile-Aufruf des Moduls fälschlich
    /// restaurierte → Quiz mit „1 von 1"-Counter, nach 1 Antwort
    /// Result-Screen. Jetzt symmetrisch: jeder Chain-End-Pfad räumt
    /// auch die Resume-Stores. Idempotent (`*.clear()` ist no-op,
    /// wenn nichts da ist) — kein Risiko für reguläre Non-Chain-
    /// Sessions, weil deren Snapshots **vor** dem `clear()`-Call
    /// im Modul-eigenen Done-CTA-Pfad bereits geräumt sind.
    func clear() {
        currentChain = nil
        stepOutcomes = []

        // **Stufe 4a (2026-05-01)** — Timer mit räumen, sonst
        // tickt er weiter wenn die Chain abgebrochen wird (z.B. via
        // Pre-Screen-Back-Chevron oder ChainComplete-„Zur Startseite").
        clearStepTimer()

        TrainingSessionResumeStore.clear()
        AccentSessionResumeStore.clear()
        QuizSessionResumeStore.clear()

        #if DEBUG
        print("🔗 [TrainingChainStore] clear")
        #endif
    }

    // MARK: - Stufe 4a: Step-Timer-Mechanik

    /// Startet den Countdown für den aktuellen `currentStep`. Setzt
    /// Total + Remaining auf `chain.perStepDurationMin * 60`,
    /// resettet `timerExpired`, killed einen ggf. laufenden Timer und
    /// scheduled den 1-Sekunden-Tick.
    func startStepTimer() {
        guard let chain = currentChain, chain.currentStep != nil else {
            clearStepTimer()
            return
        }
        let totalSeconds = max(1, chain.perStepDurationMin * 60)

        stepTimer?.invalidate()
        stepTimer = nil
        stepTotalSeconds = totalSeconds
        stepRemainingSeconds = totalSeconds
        timerExpired = false
        // **Stufe 4a-Fix**: Toast pro Step nur einmal — Reset bei
        // jedem Step-Start (frischer Step erlaubt frischen Toast).
        hasShownExpirationToast = false
        pausedRemainingSeconds = nil
        scheduleStepTick()

        #if DEBUG
        print("⏱️ [TrainingChainStore] step timer started — \(totalSeconds)s for step \(chain.currentStep?.rawValue ?? "?")")
        #endif
    }

    /// Ein 1-Sekunden-Repeating-Timer. Dekrementiert
    /// `stepRemainingSeconds`. Bei 0 → `stepTimer.invalidate()` +
    /// `timerExpired = true`. Kein automatischer Force-Done in 4a —
    /// das ist 4b.
    private func scheduleStepTick() {
        stepTimer?.invalidate()
        stepTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                guard self.stepRemainingSeconds > 0 else {
                    self.stepTimer?.invalidate()
                    self.stepTimer = nil
                    self.timerExpired = true
                    return
                }
                self.stepRemainingSeconds -= 1
                if self.stepRemainingSeconds == 0 {
                    self.stepTimer?.invalidate()
                    self.stepTimer = nil
                    self.timerExpired = true
                    #if DEBUG
                    print("⏱️ [TrainingChainStore] step timer EXPIRED — soft-cutoff banner shown")
                    #endif
                }
            }
        }
    }

    /// App geht in den Hintergrund: aktuellen Remaining-Wert
    /// einfrieren, Timer killen. Notification-Trigger:
    /// `UIApplication.willResignActiveNotification`.
    private func pauseStepTimer() {
        guard stepTimer != nil else { return }
        pausedRemainingSeconds = stepRemainingSeconds
        stepTimer?.invalidate()
        stepTimer = nil
        #if DEBUG
        print("⏱️ [TrainingChainStore] step timer paused @ \(stepRemainingSeconds)s")
        #endif
    }

    /// App kommt nach vorne: Remaining-Wert wiederherstellen, Timer
    /// neu scheduled, sofern noch Zeit übrig ist. Bei `paused == 0`
    /// (Timer war beim Background schon abgelaufen) wird kein neuer
    /// Tick gescheduled, aber `timerExpired` bleibt korrekt true.
    /// Notification-Trigger: `UIApplication.didBecomeActiveNotification`.
    private func resumeStepTimer() {
        guard let paused = pausedRemainingSeconds, currentChain != nil else { return }
        stepRemainingSeconds = paused
        pausedRemainingSeconds = nil
        if paused > 0 {
            scheduleStepTick()
            #if DEBUG
            print("⏱️ [TrainingChainStore] step timer resumed @ \(paused)s")
            #endif
        } else {
            timerExpired = true
            #if DEBUG
            print("⏱️ [TrainingChainStore] step timer resume: was 0, banner stays")
            #endif
        }
    }

    /// Räumt Timer + State komplett ab. Wird in `clear()` und in
    /// `start()` / `advance()` (vor dem Neu-Start) gerufen.
    private func clearStepTimer() {
        stepTimer?.invalidate()
        stepTimer = nil
        stepRemainingSeconds = 0
        stepTotalSeconds = 0
        timerExpired = false
        hasShownExpirationToast = false
        pausedRemainingSeconds = nil
    }

    /// **Stufe 4a-Fix (2026-05-01)** — wird vom
    /// `ChainTimerOverlayModifier` aufgerufen, sobald der mittige
    /// `ChainCutoffToast` einmalig animiert eingeblendet wurde. Setzt
    /// das One-shot-Flag, damit Re-Renders der Modul-View keinen
    /// Re-Show triggern. Reset im nächsten `startStepTimer()`.
    func markExpirationToastShown() {
        hasShownExpirationToast = true
    }
}
