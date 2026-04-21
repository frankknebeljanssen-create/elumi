import Foundation
import UIKit

/// Explizite State Machine für den Smart-Scanner-Flow.
///
/// Vorher verteilt: `SmartScannerSession.isPhotoDeliveryInFlight`,
/// `SmartScannerView.stage`, `RectangleTracker.LockState`,
/// `SmartScannerController.autoCaptureEnabled` — vier Stellen, die
/// jeweils einen Ausschnitt hielten. Kein einziger Typ gab die
/// Frage „in welchem Gesamtzustand ist der Scanner gerade?" zu
/// beantworten, und es gab **keinen** `captureFailed`-Zustand in der
/// UI — Fehler kamen nur als `print()` durch.
///
/// Dieser Typ ist die **Single Source of Truth** für den
/// Scan-Gesamtzustand. Er ersetzt die verteilten Flags **nicht** sofort
/// (Slice 2 ist additiv, kein Rewrite); er läuft parallel und wird von
/// `SmartScannerController` an den Stellen gefüttert, an denen heute
/// die Flags gesetzt werden. Künftige Slices konsolidieren die Flags
/// auf die Machine.
///
/// Lebenszyklus (legale Transitionen):
///
///   idle ──start()──▶ searching
///   searching ⇄ candidate ⇄ locked               (Tracker-Updates)
///   {searching|candidate|locked} ──shutter──▶ capturing
///   capturing ──photo received──▶ refining(raw)
///   refining ──processor done──▶ reviewReady(corrected, report)
///   refining ──processor failed──▶ captureFailed(error)
///   capturing ──delegate failure──▶ captureFailed(error)
///   reviewReady ──„Neu aufnehmen"──▶ searching
///   captureFailed ──„Nochmal versuchen"──▶ searching
///   jeder Zustand ──stop()──▶ idle
///
/// Illegale Transitionen werden im Debug geloggt aber nicht hart
/// erzwungen — das vermeidet Crashes bei seltenen Race-Conditions
/// (z. B. Tracker-Update trifft ein während Capturing) und gibt
/// trotzdem Sichtbarkeit.
enum ScanCaptureState: Equatable {
    /// Vor `start()` — Preview läuft noch nicht.
    case idle

    /// Preview läuft, aber kein Rechteck im Bild.
    case searching

    /// Rechteck erkannt, aber noch nicht stabil genug für Lock.
    case candidate

    /// Rechteck stabil gelockt — Auto-Capture darf feuern.
    case locked

    /// Shutter ausgelöst (manuell oder auto), Photo-Delivery läuft.
    case capturing

    /// Photo-Delivery fertig, Post-Capture-Pipeline (Dokument-
    /// Segmentation, Perspektivkorrektur, Enhancement) läuft.
    case refining(raw: UIImage)

    /// Pipeline fertig, finales Bild + Quality-Report liegt vor.
    case reviewReady(corrected: UIImage, report: ImageQualityAnalyzer.Report)

    /// Irgendwo zwischen Shutter und Review ist's gekracht. User
    /// bekommt eine retry-Karte statt eines stillen Logs.
    case captureFailed(SmartScannerError)

    // MARK: - Equatable

    /// Custom `==` weil `UIImage` und `SmartScannerError` nicht
    /// Equatable sind. Wir vergleichen **nur den Case** — das reicht
    /// für Observer-Entprellung (z. B. SwiftUI `animation(value:)`).
    static func == (lhs: ScanCaptureState, rhs: ScanCaptureState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.searching, .searching),
             (.candidate, .candidate),
             (.locked, .locked),
             (.capturing, .capturing),
             (.refining, .refining),
             (.reviewReady, .reviewReady),
             (.captureFailed, .captureFailed):
            return true
        default:
            return false
        }
    }

    // MARK: - Kategorien (für View-Gating)

    /// True wenn der User gerade eine Tracker-/Camera-Live-Stage sieht.
    var isLiveStage: Bool {
        switch self {
        case .searching, .candidate, .locked: return true
        default: return false
        }
    }

    /// True wenn gerade eine Aufnahme/Verarbeitung läuft — keine
    /// Nutzerinteraktion mit Live-Controls erwünscht.
    var isProcessingStage: Bool {
        switch self {
        case .capturing, .refining: return true
        default: return false
        }
    }

    /// Menschenlesbarer Bezeichner für Logs/Telemetry. Ohne Payload,
    /// damit das Log keine UIImage-/Error-Details leakt.
    var debugLabel: String {
        switch self {
        case .idle:           return "idle"
        case .searching:      return "searching"
        case .candidate:      return "candidate"
        case .locked:         return "locked"
        case .capturing:      return "capturing"
        case .refining:       return "refining"
        case .reviewReady:    return "reviewReady"
        case .captureFailed:  return "captureFailed"
        }
    }
}

// MARK: - Transitions-Regeln

extension ScanCaptureState {
    /// Prüft, ob der Übergang `self → next` erlaubt ist. Nicht jede
    /// Kombination ergibt Sinn (z. B. `reviewReady → locked`). Wird
    /// in `ScanCaptureMachine.transition(to:)` evaluiert.
    func canTransition(to next: ScanCaptureState) -> Bool {
        switch (self, next) {
        // Start / Stop — jeder Zustand darf nach `.idle` zurück.
        case (_, .idle):
            return true

        // Tracker-Updates: searching/candidate/locked dürfen
        // wechselseitig ineinander übergehen.
        case (.searching, .candidate), (.searching, .locked),
             (.candidate, .searching), (.candidate, .locked),
             (.locked, .searching),    (.locked, .candidate):
            return true

        // Von idle in den Live-Betrieb starten.
        case (.idle, .searching):
            return true

        // Shutter: jede Live-Stufe darf zum Capturing wechseln.
        case (.searching, .capturing),
             (.candidate, .capturing),
             (.locked, .capturing):
            return true

        // Capture-Lifecycle
        case (.capturing, .refining),
             (.capturing, .captureFailed),
             (.refining, .reviewReady),
             (.refining, .captureFailed):
            return true

        // **Multi-Shot-Direktrücksprung** (vocabularyList-Slice 3a):
        // Wenn ein Capture in vocabularyList in den Batch-Buffer
        // eingelegt wird statt zur Preview-Stage zu gehen, springt
        // die Machine direkt von `.refining` zurück auf `.searching`.
        // Ohne diese Transition würde der Multi-Shot-Pfad in
        // `.refining` festkleben → ProcessingStage hängt sichtbar
        // mit „wird korrigiert" + Spinner.
        case (.refining, .searching):
            return true

        // Review-Rückweg — `.idle` schon global oben abgedeckt.
        case (.reviewReady, .searching):
            return true

        // Retry nach Fehler — `.idle` schon global oben abgedeckt.
        case (.captureFailed, .searching):
            return true

        default:
            return false
        }
    }
}

// MARK: - Observable Machine

/// Observable-Wrapper, der die aktuelle `ScanCaptureState` trägt und
/// Transitionen validiert.
///
/// Thread-Modell: `@MainActor` — Scan-UI läuft auf dem Main-Thread,
/// und alle Call-Sites (Delegate-Hops über `Task { @MainActor in … }`,
/// SwiftUI-Views) sind schon da. Kein Cross-Thread-Zugriff nötig.
@MainActor
final class ScanCaptureMachine: ObservableObject {
    @Published private(set) var state: ScanCaptureState = .idle

    /// Führt eine Transition aus, wenn sie legal ist. Illegale
    /// Transitionen werden im Debug-Log vermerkt und verworfen —
    /// die Machine bleibt im alten Zustand, sodass der Scanner
    /// weiterläuft statt zu crashen.
    ///
    /// **AP11**: Zusätzlich im DEBUG-Build eine Assertion. Bei
    /// illegaler Transition crasht die App **nur im Debug-Build**
    /// mit klarer Meldung — zwingt Entwickler, Transition-Tables
    /// zu pflegen statt illegale Pfade schleichend zu akzeptieren.
    /// Release-Builds verhalten sich wie vorher (stilles Verwerfen).
    @discardableResult
    func transition(to next: ScanCaptureState) -> Bool {
        let oldState = state
        guard state.canTransition(to: next) else {
            #if DEBUG
            let message = "Invalid scan FSM transition: \(oldState.debugLabel) → \(next.debugLabel)"
            print("🔁 [FSM] ❌ \(message)")
            // Assertion-Failure nur bei wirklich unerwarteten
            // Transitionen — wir whitelisten Identitäts-Transitionen
            // (gleicher State → gleicher State), die als Idempotenz-
            // Calls vorkommen können.
            if oldState.debugLabel != next.debugLabel {
                assertionFailure(message)
            }
            #endif
            return false
        }
        #if DEBUG
        print("🔁 [FSM] \(oldState.debugLabel) → \(next.debugLabel)")
        #endif
        state = next
        return true
    }

    /// Synchron-Set auf `.idle` — benutzt z. B. in `stop()`-Pfaden.
    func reset() {
        transition(to: .idle)
    }
}
