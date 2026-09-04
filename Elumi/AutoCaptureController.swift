import Foundation
import CoreMotion
import QuartzCore
import UIKit  // UIImpactFeedbackGenerator (AP12)

/// Gated Auto-Capture-Trigger für den Smart-Scanner.
///
/// Vorher entschied `RectangleTracker.Assessment.shouldAutoCapture`
/// allein, wann der Scanner auto-auslöst — sobald der Tracker 0.5 s
/// lang stabil gelockt hatte, feuerte `capturePhoto()`. Das führte zu
/// zwei Problemen:
///
/// 1. **Motion-Blur**: Wenn das Telefon gerade noch in Bewegung war
///    (Hand bewegt sich, Device wird gerade abgesenkt), konnte die
///    Tracker-Stabilität schon "genug" wirken, der Still-Shot kam
///    aber verwackelt.
/// 2. **Fokus/Belichtung in Transition**: AV passt Fokus und
///    Belichtung kontinuierlich an; feuern wir mitten im Umschalt-
///    Vorgang, bekommen wir ein unscharfes oder falsch belichtetes
///    Bild.
///
/// Dieser Controller sammelt die fehlenden Gates:
/// - **Motion-Gate** via `CMMotionManager` (User-Acceleration +
///   Rotation-Rate, Magnitude unter Schwelle).
/// - **Focus/Exposure-Gate** via `AVCaptureDevice.isAdjustingFocus` /
///   `isAdjustingExposure` — Werte werden vom Aufrufer reingereicht.
/// - **Frame-Streak-Gate** — `.locked` muss über mehrere aufeinander-
///   folgende Frames stabil gemeldet werden. Schützt gegen
///   1-Frame-False-Locks.
///
/// Thread-Modell: Controller lebt auf der session-queue (wo der
/// `RectangleTracker` auch lebt). `CMMotionManager` publiziert auf
/// einer eigenen `OperationQueue`, der Zugriff auf die letzte
/// Magnitude ist durch `NSLock` geschützt.
///
/// **Degradation**: Auf Simulator/Geräten ohne DeviceMotion
/// (`isDeviceMotionAvailable == false`) wird der Motion-Gate
/// `allow`-by-default — der Controller bleibt funktional, statt auf
/// Null zu fallen.
final class AutoCaptureController {

    // MARK: - State (AP12)

    /// Drei-Phasen-Zyklus fürs Auto-Capture-Verhalten:
    ///   • `.idle` — keine Gate-Bedingungen erfüllt
    ///   • `.ready` — alle Gates offen, **Pre-Fire-Warnphase** (≈300 ms);
    ///     UI kann in dieser Phase einen Puls-Effekt + haptic-Hint
    ///     zeigen, damit der Auto-Trigger nicht „plötzlich" wirkt
    ///   • `.firing` — Shutter wurde ausgelöst, wartet auf Delivery
    enum AutoCaptureState: Equatable {
        case idle
        case ready
        case firing
    }

    /// Read-only State für die UI. Der AutoCaptureController selbst
    /// steuert die Übergänge; die Session liest `shouldFireNow` für
    /// den eigentlichen Trigger-Moment.
    private(set) var autoCaptureState: AutoCaptureState = .idle

    /// Callback in die UI-Ebene, wenn der Controller in die `.ready`-
    /// Phase eintritt. Wird vom `SmartScannerController` gesetzt und
    /// triggert einen kurzen Puls auf dem Live-Overlay.
    var onEnterReady: (() -> Void)?

    /// Vorgeladener Haptic-Generator für die Ready-Phase. Nicht die
    /// volle `.medium`-Impact-Stärke (die ist für den finalen Shutter
    /// reserviert) — `.light` signalisiert „gleich passiert's".
    private let readyHaptic = UIImpactFeedbackGenerator(style: .light)

    // MARK: - Konfiguration

    struct Config {
        /// Wieviele aufeinanderfolgende `.locked`-Frames erforderlich
        /// sind, bevor gefeuert werden darf. Bei 10-Hz-Detection-
        /// Drossel (`SmartScannerSession.minFrameInterval = 0.1 s`)
        /// entsprechen 2 Frames ≈ 0.2 s zusätzliche Bestätigung.
        ///
        /// **User-Spec „schneller einlocken"**: 3 → **2** Frames.
        /// Addiert zur `RectangleTracker.Config.stabilityDuration`
        /// (jetzt 0.35 s) ergibt das eine Gesamt-Latenz von ca. 0.45 s
        /// bis der Shutter feuert — vorher waren es ~0.8 s. Für
        /// Kinderhände („wackeln mehr") spürbar responsiver.
        var requiredConsecutiveLockedFrames: Int = 2

        /// Maximale zulässige Magnitude der kombinierten Device-
        /// Motion (`|userAcceleration|² + |rotationRate|²`, ohne
        /// Sqrt zur Effizienz). 0.012 ist empirisch ein Wert, bei
        /// dem ein Handy in ruhiger Hand nicht mehr zappelt, aber
        /// normale mikrometrische Wackler durchgehen. Zu niedrig
        /// = Auto-Capture feuert nie.
        var maxAllowedMotionMagnitudeSquared: Double = 0.012

        /// Update-Rate für `CMDeviceMotion`. Höher als Tracker-Rate,
        /// damit wir auch kurze Bewegungen zwischen Tracker-Frames
        /// sehen.
        var motionSamplingHz: Double = 30.0

        /// **AP12** — Vorwarnzeit zwischen „alle Gates offen" und
        /// tatsächlichem Shutter-Auslöser. Gibt dem User einen
        /// kurzen visuellen/haptischen Hinweis, dass die Auto-
        /// Capture gleich feuert. 0.3 s ist der Sweet-Spot: schnell
        /// genug, um nicht nervig zu wirken, lang genug, dass der
        /// User die Änderung wahrnimmt.
        var readyHoldDuration: TimeInterval = 0.3

        static let `default` = Config()
    }

    // MARK: - State

    private let config: Config
    private let motionManager = CMMotionManager()
    private let motionQueue: OperationQueue

    /// Streak aufeinanderfolgender `.locked`-Frames. Wird auf 0
    /// zurückgesetzt, sobald `lockState != .locked`.
    private var consecutiveLockedFrames: Int = 0

    /// Letzte gemessene Motion-Magnitude² (ohne Sqrt). Zugriff
    /// zwischen Motion-Queue und Session-Queue durch `motionLock`
    /// serialisiert.
    private var latestMotionMagnitudeSquared: Double = 0
    private let motionLock = NSLock()

    /// Zeitpunkt des letzten Motion-Samples. Dient zur Diagnose
    /// („Motion-Updates kamen rein?") und als Fallback, falls die
    /// CMMotion-Queue stehen bleibt.
    private var lastMotionSampleTimestamp: CFTimeInterval = 0

    // MARK: - Init / Lifecycle

    init(config: Config = .default) {
        self.config = config
        self.motionQueue = OperationQueue()
        motionQueue.name = "com.frdevocab.autocapture.motion"
        motionQueue.qualityOfService = .utility
        motionQueue.maxConcurrentOperationCount = 1
    }

    /// Startet CoreMotion-Updates. Degradiert stumm, wenn
    /// DeviceMotion auf dem Gerät nicht verfügbar ist (Simulator,
    /// ältere iPods ohne Motion-Chips).
    func start() {
        guard motionManager.isDeviceMotionAvailable else {
            #if DEBUG
            appDebugLog("📷 [AutoCapture] DeviceMotion nicht verfügbar — Motion-Gate deaktiviert.")
            #endif
            return
        }
        motionManager.deviceMotionUpdateInterval = 1.0 / config.motionSamplingHz
        motionManager.startDeviceMotionUpdates(to: motionQueue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let a = motion.userAcceleration
            let r = motion.rotationRate
            // Kombinierte Bewegungsmetrik (Beschleunigung + Rotation).
            // Quadriert — spart einen `sqrt` pro Sample und die
            // Schwellwertverarbeitung funktioniert 1-zu-1, wenn wir
            // auch die Config quadriert halten.
            let m2 = a.x * a.x + a.y * a.y + a.z * a.z
                   + r.x * r.x + r.y * r.y + r.z * r.z
            self.motionLock.lock()
            self.latestMotionMagnitudeSquared = m2
            self.lastMotionSampleTimestamp = CACurrentMediaTime()
            self.motionLock.unlock()
        }
    }

    /// Stoppt Motion-Updates und setzt den Frame-Streak zurück.
    /// Muss aufgerufen werden, wenn die Session stoppt, sonst läuft
    /// der Motion-Manager im Hintergrund weiter.
    func stop() {
        if motionManager.isDeviceMotionActive {
            motionManager.stopDeviceMotionUpdates()
        }
        consecutiveLockedFrames = 0
    }

    // MARK: - Public Gate

    /// Liefert `true`, wenn **alle** Gates offen sind UND die Ready-
    /// Warnphase verstrichen ist. Call-Site bleibt frei, Auto-Capture
    /// trotzdem zu unterdrücken (User-Toggle, Profile-Gate, isCapturing).
    ///
    /// Drei-Phasen-Logik (AP12):
    ///   1. `.idle` → sobald alle Gates offen sind und der Streak
    ///      erreicht ist: Übergang in `.ready`. `onEnterReady`-Callback
    ///      feuert (UI pulsed, haptic hint), `readyEnteredAt` wird
    ///      gesetzt.
    ///   2. `.ready` → solange die Gates offen bleiben: nach
    ///      `readyHoldDuration` (0.3 s) return `true` → Session feuert
    ///      den Shutter, wir wechseln in `.firing`.
    ///   3. `.firing` → blockiert weitere Firings bis `resetStreak()`
    ///      nach dem Delivery aufruft (dann zurück auf `.idle`).
    ///
    /// Wenn die Gates in `.ready` wieder zufallen (Motion/Focus/etc.),
    /// fällt der State auf `.idle` zurück — die Pre-Fire-Warnung wird
    /// abgebrochen. Das verhindert „versehentliches Feuern nach
    /// ready-Signal"-Szenarien.
    ///
    /// **Rufe diese Methode bei jedem Tracker-Update auf**, auch wenn
    /// Auto-Capture gerade deaktiviert ist — sonst zählt der
    /// Frame-Streak nicht mit hoch, und der erste Trigger-Moment
    /// nach Re-Enable fällt aus.
    func shouldFireAutoCapture(
        lockState: RectangleTracker.LockState,
        isAdjustingFocus: Bool,
        isAdjustingExposure: Bool
    ) -> Bool {
        let gatesOpen = evaluateGates(
            lockState: lockState,
            isAdjustingFocus: isAdjustingFocus,
            isAdjustingExposure: isAdjustingExposure
        )

        // Gates zu → zurück auf idle, Ready-Timer verwerfen.
        guard gatesOpen else {
            if autoCaptureState != .idle {
                #if DEBUG
                appDebugLog("📷 [AutoCapture] Ready-Phase abgebrochen — Gate-Bedingungen nicht mehr erfüllt.")
                #endif
                autoCaptureState = .idle
                readyEnteredAt = nil
            }
            return false
        }

        // In-Flight → blocken.
        if autoCaptureState == .firing { return false }

        let now = CACurrentMediaTime()

        switch autoCaptureState {
        case .idle:
            // Gates jetzt gerade offen → Ready-Phase einleiten.
            autoCaptureState = .ready
            readyEnteredAt = now
            // **Codeaudit 2026-09-03, Stufe 2** — `UIImpactFeedbackGenerator`
            // ist UIKit und muss auf dem Main-Thread benutzt werden. Diese
            // Methode läuft aber auf der `sessionQueue` des Scanners
            // (`com.frdevocab.smartscanner.session`); der `onEnterReady`-
            // Callback direkt darunter wurde bereits korrekt gehoppt, die
            // Haptik nicht. Beide gehören in denselben Block.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.readyHaptic.prepare()
                self.readyHaptic.impactOccurred()
                self.onEnterReady?()
            }
            #if DEBUG
            appDebugLog("📷 [AutoCapture] ➡️ READY (pre-fire warn \(config.readyHoldDuration)s)")
            #endif
            return false

        case .ready:
            guard let since = readyEnteredAt else {
                // Defensive — sollte nicht passieren; reset.
                autoCaptureState = .idle
                return false
            }
            let elapsed = now - since
            if elapsed >= config.readyHoldDuration {
                autoCaptureState = .firing
                #if DEBUG
                appDebugLog("📷 [AutoCapture] 🔥 FIRING (elapsed \(String(format: "%.2f", elapsed))s)")
                #endif
                return true
            }
            return false

        case .firing:
            return false  // already dispatched
        }
    }

    // MARK: - Gate-Evaluation

    /// Atomare Prüfung aller drei Gates. Keine Side-Effects außer
    /// Streak-Counter-Update — der Ready/Firing-State wird im
    /// `shouldFireAutoCapture`-Flow separat verwaltet.
    private func evaluateGates(
        lockState: RectangleTracker.LockState,
        isAdjustingFocus: Bool,
        isAdjustingExposure: Bool
    ) -> Bool {
        guard lockState == .locked else {
            if consecutiveLockedFrames > 0 {
                #if DEBUG
                appDebugLog("📷 [AutoCapture] Streak abgebrochen (lockState=\(lockState))")
                #endif
            }
            consecutiveLockedFrames = 0
            return false
        }
        consecutiveLockedFrames += 1

        guard consecutiveLockedFrames >= config.requiredConsecutiveLockedFrames else {
            return false
        }

        if isAdjustingFocus || isAdjustingExposure {
            #if DEBUG
            appDebugLog("📷 [AutoCapture] Gate: Focus/Exposure passt noch an — warte.")
            #endif
            return false
        }

        motionLock.lock()
        let m2 = latestMotionMagnitudeSquared
        motionLock.unlock()
        if m2 > config.maxAllowedMotionMagnitudeSquared {
            #if DEBUG
            appDebugLog(String(format: "📷 [AutoCapture] Gate: Device-Motion zu hoch (m²=%.4f > %.4f) — warte.",
                         m2, config.maxAllowedMotionMagnitudeSquared))
            #endif
            return false
        }

        return true
    }

    /// Reset ohne Motion-Stop. Nützlich, wenn Auto-Capture gerade
    /// gefeuert hat und die nächste Session-Runde den Streak von
    /// vorn zählen soll.
    func resetStreak() {
        consecutiveLockedFrames = 0
        autoCaptureState = .idle
        readyEnteredAt = nil
    }

    /// Zeitpunkt des Übergangs in `.ready` — Basis für die
    /// `readyHoldDuration`-Schwelle vor dem Fire-Call.
    private var readyEnteredAt: CFTimeInterval?
}
