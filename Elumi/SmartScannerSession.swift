import AVFoundation
import Vision
import UIKit
import CoreImage

/// Kern-Session für den Smart Scanner.
///
/// Kombiniert AVCaptureSession (Video-Stream + Photo Output) mit einem
/// Vision-basierten Rectangle-Tracker, der pro Frame die Dokument-Ecken
/// sucht. Liefert Observations per Delegate und ein Still-Image via
/// `capturePhoto()`. Alles headless — die UI lebt in `SmartScannerView`.
///
/// Thread-Modell: die Session und der Tracker laufen auf einer eigenen
/// Queue. Callbacks an den Delegate springen explizit zurück auf main,
/// damit die UI sauber updaten kann.
@MainActor
protocol SmartScannerSessionDelegate: AnyObject {
    /// Pro Frame (gedrosselt auf ~10 Hz) mit aktueller Einschätzung.
    func smartScannerDidUpdateGuidance(_ guidance: SmartScannerGuidance)
    /// Nach `capturePhoto()` wenn das finale Still-Image da ist.
    /// Das Bild ist bereits orientation-korrekt (portrait).
    ///
    /// `frozenQuad` ist der Live-Quad, der zum Zeitpunkt des Shutter-
    /// Events zuletzt **gelockt** war — Downstream kann ihn als Fallback
    /// nutzen, falls das Post-Capture-Refinement kein Rechteck findet.
    /// Kann nil sein, wenn nie ein Lock erreicht wurde (z. B. Manual-
    /// Capture auf instabiler Szene).
    ///
    /// `frozenAttentionBox` ist die **FreeText-Attention-Region** (Vision-
    /// normalisiert, 0…1, Y-up) zum Zeitpunkt des Shutters — heute nur
    /// noch als Diagnose-Metadata; kein automatischer Crop mehr.
    ///
    /// `previewLayerSize` ist die Größe des Preview-Containers
    /// (`previewLayer.bounds.size`) zum Shutter-Zeitpunkt. Wird vom
    /// FreeText-Manual-WYSIWYG-Pfad genutzt.
    ///
    /// `captureID` ist eine **eindeutige UUID pro Capture** (Voraussetzung
    /// für Multi-Shot-Auswahl + saubere Trace ob Original/Crop/Optimized
    /// in Analyse). Wird vom Caller durch alle Pipeline-Stufen
    /// weitergereicht und in jedem Capture-Log als Prefix verwendet.
    func smartScannerDidCapturePhoto(
        _ image: UIImage,
        frozenQuad: VNRectangleObservation?,
        frozenAttentionBox: CGRect?,
        previewLayerSize: CGSize?,
        captureID: UUID
    )
    /// Bei Fehlern (Autorisierung, Setup, Capture).
    func smartScannerDidFail(_ error: SmartScannerError)
}

// MARK: - Öffentliche Typen

enum SmartScannerError: Error, LocalizedError {
    case notAuthorized
    case setupFailed
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Kamerazugriff wurde nicht erlaubt."
        case .setupFailed: return "Kamera konnte nicht gestartet werden."
        case .captureFailed: return "Foto konnte nicht aufgenommen werden."
        }
    }
}

/// Alles, was die UI zum Rendern des Overlays und der Hinweistexte braucht.
struct SmartScannerGuidance {
    enum Quality {
        case noRectangle       // kein Rechteck erkannt
        case tooSmall          // Rechteck zu klein → näher rangehen
        case tooSkewed         // zu schief → gerader halten
        case unstable          // wackelt noch → ruhig halten
        case good              // alles passt

        var hintText: String {
            switch self {
            case .noRectangle: return "Dokument ins Bild halten"
            case .tooSmall: return "Näher rangehen"
            case .tooSkewed: return "Gerader halten"
            case .unstable: return "Ruhig halten"
            // „Perfekt erkannt" war irreführend — der Tracker
            // verifiziert nicht, dass das erkannte Rechteck tatsächlich
            // mit den Papierkanten übereinstimmt, sondern nur, dass
            // ein stabiles Rechteck plausibler Größe/Schiefe da ist.
            // „Bereit — halten" ist ehrlicher: signalisiert dem User,
            // dass die Erkennung stabil ist und die Aufnahme gleich
            // folgt (Auto) bzw. ausgelöst werden kann (Manual).
            case .good: return "Bereit — halten"
            }
        }

        var isGood: Bool {
            if case .good = self { return true }
            return false
        }
    }

    /// Die aktuell besten vier Eckpunkte in **View-Koordinaten**
    /// (bereits ins Preview-Layer transformiert). nil wenn nichts
    /// erkannt wurde. Gegen Noise geglättet (EMA).
    let corners: RectangleCorners?
    /// **Raw Vision Detection** — Eckpunkte DIREKT vom Vision-Frame,
    /// **ohne** Smoothing, nur einmal-Y-geflippt im Mapper. Dient dem
    /// Debug-Overlay (roter Rahmen gegen grünen smoothed Rahmen), um
    /// Overlay-vs-Reality-Drift sichtbar zu machen.
    var rawCorners: RectangleCorners? = nil
    /// Qualitäts-Einschätzung fürs Overlay (Farbe) und den Hinttext.
    let quality: Quality
    /// Lock-Zustand vom `RectangleTracker` — steuert die Overlay-Farbe.
    var lockState: RectangleTracker.LockState = .searching
    /// **AP12** — true, wenn der Auto-Capture-Controller in der
    /// Ready-Phase ist (alle Gates offen, Shutter feuert in ≈0.3 s).
    var isAutoCaptureReady: Bool = false

    /// **FreeText-Attention**: weiches Overlay-Rect für den zentralen
    /// Text-/Saliency-Bereich, an dem die Kamera aktuell „zielt".
    /// Bereits in View-Layer-Koordinaten (Y-down, origin oben links)
    /// und EMA-geglättet vom `AttentionRegionTracker`. Nil, wenn weder
    /// Text noch Saliency einen hinreichend zentralen Bereich liefern
    /// (oder im `.vocabularyList`-Profil, das Attention-Detection gar
    /// nicht läuft).
    var attentionRegion: CGRect? = nil

    /// **FreeText-Fokus-Modus**: `.auto` (System detektiert) oder
    /// `.locked(rect)` (User hat einen Bereich per Tap gepinnt).
    /// UI nutzt das zum Färben des Overlays + zum Ein-/Ausblenden
    /// des Reset-Buttons.
    var focusMode: FocusMode = .auto
}

struct RectangleCorners {
    let topLeft: CGPoint
    let topRight: CGPoint
    let bottomLeft: CGPoint
    let bottomRight: CGPoint
}

// MARK: - Session

final class SmartScannerSession: NSObject {
    weak var delegate: SmartScannerSessionDelegate?

    /// Das Preview-Layer, das die UI als Camera-Feed zeigt.
    /// Wird in `start()` konfiguriert.
    let previewLayer: AVCaptureVideoPreviewLayer

    /// **Freeze-Frame-Support** (User-Spec „wenn Shutter kommt, Bild
    /// einfrieren"): zuletzt empfangenes Video-Frame, gehalten als
    /// Pixel-Buffer. Wird bei jedem Delegate-Callback aktualisiert.
    /// Beim Shutter ruft der Controller `snapshotLatestFrame()` auf —
    /// das rendert einmalig zu UIImage und liefert den Freeze-Frame,
    /// den die View als Overlay über den weiterlaufenden Video-Feed
    /// legt, bis das Still-Photo zurück ist.
    ///
    /// Kein @Published — pro Frame aktualisieren würde die Haupt-Queue
    /// belasten. Access vom Session-Queue aus, Snapshot nur on-demand.
    private var latestPixelBuffer: CVPixelBuffer?
    private let snapshotContext = CIContext(options: [.useSoftwareRenderer: false])

    /// Auto-Capture aktiviert? Wenn true, triggert die Session automatisch
    /// `capturePhoto()` sobald die Stabilität-Bedingungen erfüllt sind.
    var autoCaptureEnabled: Bool = true

    /// Capture-Profil. Default `.vocabularyList` entspricht dem
    /// bisherigen Verhalten (Dokument-Scan mit Auto-Capture).
    /// `.freeText` schaltet Auto-Capture an der Quelle ab — selbst wenn
    /// `autoCaptureEnabled == true` feuert nichts, solange das Profil
    /// auto-capture ausschließt. So kann die UI den Toggle stehen
    /// lassen, ohne dass versehentlich auf Poster/Müslipackungen
    /// gespielt wird.
    var captureProfile: ScanCaptureProfile = .vocabularyList {
        didSet {
            guard oldValue != captureProfile else { return }
            // **Profile-Switch-Reset**: jeder Wechsel zwischen
            // vocabularyList ↔ freeText räumt FreeText-spezifische
            // Snapshots ab. Sonst könnte ein in FreeText gesammelter
            // Attention-Box-Snapshot in einen direkt folgenden
            // VocabularyList-Capture übernommen werden (oder umgekehrt
            // beim nächsten FreeText-Eintritt eine stale Box angezeigt).
            sessionQueue.async { [weak self] in
                self?.attentionTracker.reset()
                self?.lastConfidentAttentionBox = nil
                self?.frozenAttentionForCapture = nil
                #if DEBUG
                appDebugLog("🧹 [Reset] profile switch → cleared attention state")
                #endif
            }
        }
    }

    /// **FreeText-Fokus-Modus** (Tap-to-Lock): wenn der User einen
    /// Bereich gelockt hat, schläft der Attention-Tracker, und der
    /// Overlay rendert stabil an der gelockten Position. Beim Zurück
    /// auf `.auto` wird der Tracker-State zurückgesetzt, damit der
    /// nächste Auto-Lauf frisch beginnt.
    var focusMode: FocusMode = .auto {
        didSet {
            guard oldValue != focusMode else { return }
            if focusMode == .auto {
                sessionQueue.async { [weak self] in
                    self?.attentionTracker.reset()
                }
            }
        }
    }

    // MARK: Private

    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.frdevocab.smartscanner.session")
    private let videoOutput = AVCaptureVideoDataOutput()
    private let photoOutput = AVCapturePhotoOutput()

    /// Rechteckerkennung für Vokabel-Modus — lebt auf der sessionQueue.
    private let rectangleTracker = RectangleTracker()

    /// **Rechteckerkennung für FreeText-Auto/Rahmen-Modus** —
    /// lockerere Schwellen für nicht-dokumentartige Plakate, Cover,
    /// Schilder. Eigene Instanz, damit der Vokabel-Tracker davon
    /// unabhängig kalibriert bleibt und keine State-Reset-Konflikte
    /// beim Mode-Switch entstehen.
    private let assistRectangleTracker = RectangleTracker(config: .rectangleAssist)

    /// Attention-Tracker für den FreeText-Modus. Läuft nur, wenn
    /// `captureProfile.runsAttentionDetection == true` (aktuell
    /// ausschließlich `.freeText`). Erkennt zentralen Text-/Content-
    /// Bereich und liefert ein weiches Overlay-Rect an die UI.
    private let attentionTracker = AttentionRegionTracker()

    /// Zusätzlicher Gate-Layer für Auto-Capture. Misst Device-Motion
    /// via CoreMotion, prüft Focus-/Exposure-Status des Capture-Device
    /// und fordert einen kurzen Frame-Streak über `.locked`, bevor
    /// `capturePhoto()` auto-triggern darf. Verhindert blurry Auto-
    /// Shots kurz nach dem Absetzen der Hand.
    private let autoCaptureController = AutoCaptureController()

    /// Drosselt Frame-Processing auf ~10 Hz (sonst unnötige CPU-Last).
    private var lastProcessedTimestamp: CFTimeInterval = 0
    private let minFrameInterval: CFTimeInterval = 0.1

    /// **Queue-private Re-Entry-Protection** auf `sessionQueue`.
    ///
    /// **WICHTIG — nicht als globale Wahrheit lesen**:
    /// `ScanCaptureMachine.state == .capturing` ist die **public truth**
    /// für „läuft gerade eine Capture?". Diese Variable ist
    /// **ausschließlich** ein Implementation-Detail für die
    /// AVFoundation-Delegate-Queue-Sicherheit. Sie existiert, weil:
    ///
    ///   1. Die Machine auf MainActor lebt; Cross-Thread-Reads von der
    ///      sessionQueue wären mit async-Hops verzahnt, die zwischen
    ///      `photoOutput.capturePhoto(...)` und `didFinishProcessingPhoto`
    ///      Race-Windows öffnen würden.
    ///   2. Der Controller transitioniert die Machine auf `.capturing`
    ///      **bevor** `session.capturePhoto()` aufgerufen wird. Würden
    ///      wir einen Machine-derived Guard nutzen, würde der erste
    ///      legitime Capture-Call verworfen, weil er die eigene
    ///      Transition als "schon laufend" interpretieren würde.
    ///
    /// **Lifecycle**: `true` zwischen dem `photoOutput.capturePhoto(...)`-
    /// Call (in `capturePhoto()` auf sessionQueue) und dem
    /// `defer { … = false }` im `photoOutput(_:didFinishProcessingPhoto:
    /// error:)`-Delegate. Maximal eine Photo-Delivery gleichzeitig.
    ///
    /// **Konsistenz-Check (DEBUG)**: Im Photo-Delivery-Delegate sollte
    /// die Machine konzeptionell bei `.capturing` sein (vor unserem
    /// `defer`). Nicht aktiv geassertet, weil die Machine-Reads
    /// async-MainActor-bound wären — der DEBUG-Log
    /// `🔵 [AVFoundation] didFinishProcessingPhoto fired` reicht für
    /// nachträgliche Diagnose.
    private var isPhotoDeliveryInFlight = false

    /// Letzter Lock-State, an dem wir Fokus auf das Dokumentzentrum
    /// gezogen haben. Verhindert, dass wir bei jedem `.locked`-Frame
    /// einen neuen Focus-Triggern (unnötige Mechanik-Bewegung). Wird
    /// beim Lock-Verlust auf nil zurückgesetzt.
    private var lastDocumentFocusRect: VNRectangleObservation?

    /// Diagnostic-Throttle: logt Mapper-Output nur einmal pro
    /// Lock-State-Wechsel nach `.locked` (statt 10× pro Sekunde).
    private var lastLoggedLockState: RectangleTracker.LockState = .searching

    /// Eingefrorener Live-Quad zum Zeitpunkt des Shutter-Events
    /// (User-Auftrag „Fix B+C Manual-Freeze"). Sobald `capturePhoto()`
    /// aufgerufen wird, snapshotten wir das letzte gelockte Rechteck
    /// vom `RectangleTracker` — so hat Downstream einen stabilen Quad,
    /// selbst wenn die Live-Detection bis zum Photo-Delivery weiter
    /// mutiert. Wird nach dem Photo-Delivery bzw. Fail zurückgesetzt.
    /// Zugriff nur auf `sessionQueue`.
    private var frozenQuadForCapture: VNRectangleObservation?

    /// **Letzte vertrauenswürdige Attention-Region** vom
    /// `AttentionRegionTracker` — Vision-normalisiert (0…1, Y-up).
    /// Wird in `emitAttentionGuidance` aktualisiert, sobald die Region
    /// **stabil** ist UND einen ausreichend hohen Score (≥ 0.6) hat.
    /// Beim Shutter snapshotten wir sie als `frozenAttentionForCapture`,
    /// damit Downstream das Bild auf die Region cropen kann
    /// („Capture = Overlay"-Garantie).
    /// Zugriff nur auf `sessionQueue`.
    private var lastConfidentAttentionBox: CGRect?
    /// Eingefrorener Attention-Box zum Shutter-Zeitpunkt (snapshot
    /// von `lastConfidentAttentionBox` in `capturePhoto()`). Wird im
    /// Photo-Delivery durchgereicht und danach zurückgesetzt.
    /// Zugriff nur auf `sessionQueue`.
    private var frozenAttentionForCapture: CGRect?

    /// Mindest-Score für eine Region, damit sie als „capture-würdig"
    /// gilt. Unterhalb: full-frame Capture (kein Crop). Spec-Wert
    /// (`if confidence < 0.6 → useFullImage`).
    private let attentionConfidenceThreshold: Double = 0.6

    /// Eindeutige UUID für den **aktuellen Capture**. Wird in
    /// `capturePhoto()` neu gesetzt und durch das gesamte Photo-
    /// Delivery + Pipeline-Routing weitergereicht (Delegate, Controller,
    /// View). Erleichtert Multi-Shot-Auswahl und Diagnose-Trace.
    /// Zugriff nur auf `sessionQueue`.
    private var currentCaptureID: UUID? = nil

    /// **Größe des Preview-Containers** zum Shutter-Zeitpunkt
    /// (CGSize, ungeklemmt). Quelle: `previewLayer.bounds.size`.
    /// Wird in `capturePhoto()` snapshottet und im Photo-Delivery-
    /// Pfad an den Delegate weitergereicht.
    ///
    /// **Zweck**: WYSIWYG für FreeText-Manual-Capture.
    /// `ImageCropper.cropToAspectFill(image, containerSize: ...)`
    /// rechnet den sichtbaren Ausschnitt analytisch aus dem
    /// Photo-Aspect + Container-Aspect. Robust gegen Apple's
    /// metadataOutputRectConverted-Quirks (Orientation-/Rotation-
    /// abhängige Konventionen).
    private var previewLayerSizeForCapture: CGSize?

    override init() {
        self.previewLayer = AVCaptureVideoPreviewLayer()
        super.init()
        self.previewLayer.session = session
        self.previewLayer.videoGravity = .resizeAspectFill
    }

    // MARK: - Lifecycle

    func start() {
        requestAuthorization { [weak self] granted in
            guard let self else { return }
            guard granted else {
                Task { @MainActor in self.delegate?.smartScannerDidFail(.notAuthorized) }
                return
            }
            self.sessionQueue.async {
                self.configureSession()
                if !self.session.isRunning {
                    self.session.startRunning()
                }
                // CoreMotion parallel zur AVCaptureSession hochfahren —
                // Motion-Gate braucht ein paar Samples Vorlauf, bevor
                // es sinnvoll greift.
                self.autoCaptureController.start()
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.session.isRunning {
                self.session.stopRunning()
            }
            self.autoCaptureController.stop()
            // Attention-Tracker zurücksetzen — sonst bleibt die
            // geglättete Box für die nächste Session sichtbar.
            self.attentionTracker.reset()
            // Frozen Region beim Stop löschen — bei nächstem Start
            // einer neuen Szene würde sonst der alte Crop greifen.
            self.lastConfidentAttentionBox = nil
            self.frozenAttentionForCapture = nil
            self.previewLayerSizeForCapture = nil
        }
    }

    /// Tap-to-Focus: der User tippt in den Preview-Layer, die View gibt
    /// uns den Layer-Point — wir rechnen um in Capture-Device-
    /// Koordinaten (0…1) und triggern eine einmalige Fokus-/
    /// Belichtungs-Konvergenz am Tap-Punkt.
    ///
    /// Erst sinnvoll nutzbar, sobald die View einen Tap-Gesture-
    /// Handler anbindet (folgendes Slice in der UI-Schicht).
    func tapToFocus(atLayerPoint layerPoint: CGPoint) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device
            else { return }
            let devicePoint = self.previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
            FocusExposureController.focus(device: device, atPoint: devicePoint)
        }
    }

    /// **Belichtungs-Korrektur** (Tap-to-Focus + Slider).
    /// Wert in EV (Exposure Value Stops). Pragmatischer User-Range
    /// `±2.0` EV; clamped intern auf `device.minExposureTargetBias` …
    /// `device.maxExposureTargetBias` (typisch ±8.0).
    ///
    /// Triggert `device.setExposureTargetBias(_:completionHandler:)`.
    /// `completionHandler` wird ignoriert — die UI braucht kein
    /// Feedback, der Effekt ist visuell sofort sichtbar.
    func setExposureBias(_ bias: Float) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device
            else { return }
            let clamped = max(device.minExposureTargetBias, min(device.maxExposureTargetBias, bias))
            do {
                try device.lockForConfiguration()
                device.setExposureTargetBias(clamped, completionHandler: nil)
                device.unlockForConfiguration()
            } catch {
                #if DEBUG
                appDebugLog("☀️ [Exposure] lockForConfiguration failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - Zoom (Feature B — Pinch-to-Zoom)

    /// Maximaler Zoom-Faktor, den wir dem User anbieten. `5.0` ist
    /// ein UX-Kompromiss: genug, um Speisekarten-Kleinschrift lesbar
    /// zu machen, aber unter der Schwelle, ab der typische Wide-Angle-
    /// Linsen unscharf werden (`videoMaxZoomFactor` reicht oft
    /// zwei- bis dreistellig, aber nur die ersten 5x sind praktisch
    /// nutzbar).
    static let maxUserVisibleZoom: CGFloat = 5.0

    /// Aktueller Zoom-Faktor des Capture-Devices. Read-only Exposure
    /// für den Controller (UI liest über Controller via Delegate-
    /// Callback oder @Published-Binding).
    var currentZoomFactor: CGFloat {
        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device
        else { return 1.0 }
        return device.videoZoomFactor
    }

    /// Setzt den Zoom-Faktor hart (ohne Ramping) — reagiert schnell
    /// auf Gesture-Events, was bei Pinch wichtig ist, damit die
    /// Preview-Darstellung direkt dem Finger folgt. Für animierte
    /// Übergänge (z. B. Reset auf 1x) existiert `rampZoom(to:)`.
    ///
    /// Clampt auf `[1.0, min(deviceMax, maxUserVisibleZoom)]`. Fehler
    /// beim `lockForConfiguration` werden im Debug geloggt und
    /// stillschweigend verworfen — der User sieht dann einfach keinen
    /// Zoom-Effekt.
    ///
    /// - Returns: Der **tatsächlich** angewandte Zoom-Faktor (nach
    ///   Clamping). Der Controller spiegelt den zurück ins UI, damit
    ///   der Indicator korrekt bleibt.
    @discardableResult
    func updateZoom(to factor: CGFloat) -> CGFloat {
        guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device
        else { return 1.0 }
        let maxZoom = min(device.activeFormat.videoMaxZoomFactor, Self.maxUserVisibleZoom)
        let clamped = max(1.0, min(factor, maxZoom))
        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = clamped
            device.unlockForConfiguration()
        } catch {
            #if DEBUG
            appDebugLog("❌ [Zoom] lockForConfiguration failed: \(error.localizedDescription)")
            #endif
        }
        return clamped
    }

    /// Animierter Zoom-Übergang via `ramp(toVideoZoomFactor:withRate:)`.
    /// Für Reset-Tap auf „1x" — dort ist ein fließender Übergang
    /// angenehmer als ein Ruck.
    func rampZoom(to factor: CGFloat, rate: Float = 4.0) {
        sessionQueue.async { [weak self] in
            guard let self,
                  let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device
            else { return }
            let maxZoom = min(device.activeFormat.videoMaxZoomFactor, Self.maxUserVisibleZoom)
            let clamped = max(1.0, min(factor, maxZoom))
            do {
                try device.lockForConfiguration()
                device.ramp(toVideoZoomFactor: clamped, withRate: rate)
                device.unlockForConfiguration()
            } catch {
                #if DEBUG
                appDebugLog("❌ [Zoom] ramp lockForConfiguration failed: \(error.localizedDescription)")
                #endif
            }
        }
    }

    /// Löst einen Still-Shot aus. Der Delegate-Callback feuert mit dem
    /// finalen UIImage, sobald es da ist.
    ///
    /// **Capture-Qualitäts-Einstellungen** (User-Auftrag „Fix D"):
    /// • `photoQualityPrioritization = .quality` — Full-Fidelity-Pipeline,
    ///   Deep-Fusion-/Smart-HDR-Nutzung wo unterstützt. `.balanced` hätte
    ///   auf mittlerer Stufe Auflösung/Schärfe geopfert.
    /// • `maxPhotoDimensions = activeFormat.supportedMaxPhotoDimensions.last`
    ///   — nutzt die maximale vom Device gelieferte Pixel-Anzahl (iOS 16+).
    ///   Wenn das Gerät das nicht meldet, bleibt der Default.
    /// • Stabile Mustererkennung beim Tap: `isPhotoDeliveryInFlight = true`
    ///   früh gesetzt, damit weitere Taps in der gleichen Sekunde
    ///   ignoriert werden.
    /// Rendert den zuletzt empfangenen Video-Frame als UIImage — für
    /// den Freeze-Frame-Overlay beim Shutter. Nil, solange noch kein
    /// Frame durch den Delegate gelaufen ist (typisch: erste 50 ms
    /// nach Session-Start). Orientation wird auf `.right` gesetzt, weil
    /// die Kamera-Buffer im Portrait-Modus als Landscape-Right liefern —
    /// ohne diesen Hinweis würde der Overlay auf dem Kopf stehen.
    func snapshotLatestFrame() -> UIImage? {
        guard let buffer = latestPixelBuffer else { return nil }
        let ciImage = CIImage(cvPixelBuffer: buffer)
        guard let cg = snapshotContext.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cg, scale: 1, orientation: .right)
    }

    func capturePhoto() {
        #if DEBUG
        appDebugLog("🟡 [Session] capturePhoto called")
        #endif
        // **Preview-Layer-Size snapshotten** (vor Dispatch zur
        // sessionQueue). CALayer-Property-Reads sind thread-safe;
        // wir nehmen die Größe genau so, wie sie zum Shutter-Zeitpunkt
        // sichtbar war.
        let previewBoundsSize = previewLayer.bounds.size
        let previewLayerSizeSnapshot: CGSize? = {
            guard previewBoundsSize.width > 0, previewBoundsSize.height > 0 else { return nil }
            return previewBoundsSize
        }()
        let previewGravityRaw = previewLayer.videoGravity.rawValue
        let zoomFactorAtCapture: CGFloat = {
            guard let device = (session.inputs.first as? AVCaptureDeviceInput)?.device
            else { return 1.0 }
            return device.videoZoomFactor
        }()
        #if DEBUG
        let szStr = previewLayerSizeSnapshot.map {
            String(format: "(%.0f×%.0f)", $0.width, $0.height)
        } ?? "nil"
        appDebugLog("📸 [Capture-Snapshot] previewBounds=\(previewBoundsSize) " +
              "previewLayerSize=\(szStr) " +
              "gravity=\(previewGravityRaw) zoom=\(zoomFactorAtCapture)")
        #endif

        sessionQueue.async { [weak self] in
            guard let self, !self.isPhotoDeliveryInFlight else { return }
            self.isPhotoDeliveryInFlight = true
            self.previewLayerSizeForCapture = previewLayerSizeSnapshot
            // Frische Capture-ID — eine pro Photo-Delivery. Wird im
            // Photo-Output-Delegate ans `smartScannerDidCapturePhoto`
            // weitergereicht und nach Delivery resettet.
            self.currentCaptureID = UUID()

            // Live-Quad einfrieren (User-Auftrag „Fix B+C").
            // **Welcher Tracker?** Vokabel: regulärer; FreeText auto/
            // Rahmen: assistRectangleTracker. Letzteres ist wichtig,
            // damit der freeText-Quad-Pfad in `runProcessing` mit der
            // assist-config-getunten Rectangle als fallbackQuad arbeitet.
            if self.captureProfile == .freeText && self.autoCaptureEnabled {
                self.frozenQuadForCapture = self.assistRectangleTracker.lastLockedRectangle
            } else {
                self.frozenQuadForCapture = self.rectangleTracker.lastLockedRectangle
            }

            // **Attention-Region einfrieren** — wird **nur** als
            // Debug/Metadata an Downstream gereicht. FreeText-Pipeline
            // verwendet sie nicht mehr automatisch zum Croppen
            // (Stabilisierungs-Slice). Der Snapshot dient zwei Zwecken:
            //   1. Diagnose: Logs zeigen was zur Shutter-Zeit „die
            //      vertrauenswürdige Region" war.
            //   2. Vorbereitung für späteres Smart-Crop-**Vorschlag**-
            //      Feature im Review (nicht implementiert in diesem
            //      Slice).
            //
            // **Locked-Mode-Override**: wenn der User per Tap eine
            // Region gelockt hat, gewinnt diese — auch ohne Tracker-
            // Stabilitäts-Check, weil sie explizit vom User gesetzt
            // wurde.
            if case .locked(let lockedRect) = self.focusMode {
                self.frozenAttentionForCapture = lockedRect
            } else {
                self.frozenAttentionForCapture = self.lastConfidentAttentionBox
            }
            // **Pre-Capture Reset von lastConfidentAttentionBox**:
            // Sobald der Snapshot in `frozenAttentionForCapture` liegt,
            // räumen wir die laufende Region ab. Damit kann ein direkt
            // anschließender Capture (z. B. nach Retake) nicht aus
            // Versehen die alte Region erben — er bekommt eine frische
            // (oder gar keine, falls der Tracker noch nicht wieder
            // konvergiert ist).
            self.lastConfidentAttentionBox = nil

            #if DEBUG
            if let q = self.frozenQuadForCapture {
                appDebugLog(String(
                    format: "📷 [Overlay] frozenQuad: tl=(%.3f,%.3f) tr=(%.3f,%.3f) bl=(%.3f,%.3f) br=(%.3f,%.3f)",
                    q.topLeft.x, q.topLeft.y,
                    q.topRight.x, q.topRight.y,
                    q.bottomLeft.x, q.bottomLeft.y,
                    q.bottomRight.x, q.bottomRight.y
                ))
            } else {
                appDebugLog("📷 [Overlay] frozenQuad: nil (no prior lock)")
            }
            #endif

            let settings = AVCapturePhotoSettings()
            // **Shutter-Lag-Fix**: `.quality` triggert Smart-HDR +
            // Deep-Fusion und kann 1-2 s dauern. `.balanced` ist deutlich
            // schneller (~200-400 ms) und reicht für FreeText/Vokabel-
            // Scans völlig aus. Wer Pixel-Perfekt-Fotos braucht, kann
            // das später als Settings-Toggle umstellen.
            settings.photoQualityPrioritization = .balanced

            // Max-Photo-Dimensions über das aktuelle Input-Device lesen.
            // Seit iOS 16 liefern manche Geräte mehrere erlaubte
            // Maximalgrößen — wir nehmen die letzte (= größte).
            if #available(iOS 16.0, *) {
                if let device = (self.session.inputs.first as? AVCaptureDeviceInput)?.device,
                   let maxDim = device.activeFormat.supportedMaxPhotoDimensions.last {
                    settings.maxPhotoDimensions = maxDim
                }
            }
            self.photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }

    // MARK: - Authorization

    private func requestAuthorization(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                completion(granted)
            }
        default:
            completion(false)
        }
    }

    // MARK: - Configuration

    private func configureSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        // Input: rückseitige Kamera.
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input)
        else {
            session.commitConfiguration()
            Task { @MainActor in self.delegate?.smartScannerDidFail(.setupFailed) }
            return
        }
        session.addInput(input)

        // Video-Output für die Rechteckerkennung (kein Still).
        videoOutput.setSampleBufferDelegate(self, queue: sessionQueue)
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }

        // Photo-Output für das finale Still.
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }

        // **Crash-Fix** (NSInvalidArgumentException aus User-Report):
        //   `*** -[AVCapturePhotoOutput capturePhotoWithSettings:delegate:]
        //        settings.photoQualityPrioritization must not be higher
        //        than self.maxPhotoQualityPrioritization`
        //
        // Apple-Regel: `AVCapturePhotoSettings.photoQualityPrioritization`
        // und `.maxPhotoDimensions` dürfen **niemals** höher sein als
        // die entsprechenden Werte auf `photoOutput`. Default auf
        // `photoOutput.maxPhotoQualityPrioritization` ist `.balanced` —
        // wenn wir in den Settings `.quality` fordern, crasht die App
        // in dem Moment, wo `capturePhoto(...)` aufgerufen wird (Auto-
        // Capture-Trigger, sobald der Rahmen grün wird).
        //
        // Fix: beide Obergrenzen hier synchron zu den Werten hochziehen,
        // die wir in `capturePhoto()` in den Settings nutzen.
        photoOutput.maxPhotoQualityPrioritization = .quality

        if #available(iOS 16.0, *) {
            if let device = (session.inputs.first as? AVCaptureDeviceInput)?.device,
               let maxDim = device.activeFormat.supportedMaxPhotoDimensions.last {
                photoOutput.maxPhotoDimensions = maxDim
            }
        }

        // Video-Orientation synchronisieren (portrait fix — der Scanner
        // nimmt nur hochformatige Dokumente auf; Landscape macht hier
        // keinen Sinn).
        //
        // **Slice Z — Overlay-Präzision**: Alle drei Verbindungen
        // (videoOutput, photoOutput, previewLayer) müssen dieselbe
        // Rotation haben, sonst liegt der coordinate-frame von
        // Vision (portrait pixel buffer) nicht deckungsgleich mit
        // dem, was der Preview-Layer als `captureDevicePoint`
        // interpretiert. Symptom vorher: der gezeichnete grüne
        // Rahmen saß leicht neben den echten Papierkanten — das
        // gemachte Foto war korrekt, nur die Live-Preview-Darstellung
        // nicht.
        if let connection = videoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        if let connection = photoOutput.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
        if let connection = previewLayer.connection,
           connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }

        // Fokus + Belichtung von Anfang an auf Dokumentzentrum
        // (continuous). Ohne diesen Aufruf läuft AV mit sensorweitem
        // Default, was auf einem typischen Schreibtisch-Setup gerne
        // den Tisch statt das Papier anfokussiert.
        if let device = (session.inputs.first as? AVCaptureDeviceInput)?.device {
            FocusExposureController.resetToContinuous(device: device)
        }

        // Debug-Log: welches Device, welches Preset — hilft beim
        // Diagnostizieren von Qualitätsproblemen. Einmalig beim
        // Session-Setup, kein Laufzeit-Overhead.
        #if DEBUG
        if let device = (session.inputs.first as? AVCaptureDeviceInput)?.device {
            var maxDimText = "n/a"
            if #available(iOS 16.0, *) {
                if let last = device.activeFormat.supportedMaxPhotoDimensions.last {
                    maxDimText = "\(last.width)×\(last.height)"
                }
            }
            appDebugLog("📷 [Scan] Setup: device=\(device.localizedName) type=\(device.deviceType.rawValue) " +
                  "preset=\(session.sessionPreset.rawValue) maxPhotoDim=\(maxDimText)")
        }
        #endif

        session.commitConfiguration()
    }

    /// Vergleich zweier Rectangles auf „ungefähr gleiche Mitte". Nutzen
    /// wir, um wiederholten Fokus-Pull auf denselben Dokumentpunkt zu
    /// unterdrücken. Schwelle normalisiert (0.02 = 2 % der Bildkante).
    private func rectsApproximatelyEqual(
        _ a: VNRectangleObservation?,
        _ b: VNRectangleObservation?
    ) -> Bool {
        guard let a, let b else { return false }
        let centerA = CGPoint(
            x: (a.topLeft.x + a.topRight.x + a.bottomLeft.x + a.bottomRight.x) / 4,
            y: (a.topLeft.y + a.topRight.y + a.bottomLeft.y + a.bottomRight.y) / 4
        )
        let centerB = CGPoint(
            x: (b.topLeft.x + b.topRight.x + b.bottomLeft.x + b.bottomRight.x) / 4,
            y: (b.topLeft.y + b.topRight.y + b.bottomLeft.y + b.bottomRight.y) / 4
        )
        return abs(centerA.x - centerB.x) < 0.02 && abs(centerA.y - centerB.y) < 0.02
    }

    // MARK: - Guidance-Emission

    /// Wandelt die Tracker-Einschätzung in ein UI-taugliches
    /// Guidance-Objekt um und sendet es an den Delegate.
    ///
    /// Während `isPhotoDeliveryInFlight == true` (d. h. zwischen
    /// Shutter-Event und Photo-Delivery) **emittieren wir keine neuen
    /// Guidance-Updates** — das friert das Overlay optisch ein und
    /// vermittelt dem User, dass das Bild gerade „geknipst" wird.
    /// Entspricht User-Auftrag „Manual-Freeze" auf UI-Ebene.
    private func emitGuidance(_ assessment: RectangleTracker.Assessment, bufferSize: CGSize) {
        if isPhotoDeliveryInFlight { return }

        // Diagnostic-Throttling: Log die Koordinaten-Übersetzung **nur
        // bei Lock-State-Änderung** auf .locked, damit wir Overlay-
        // Alignment sehen können ohne Log-Flood.
        let shouldLogMapping = (assessment.lockState == .locked
            && lastLoggedLockState != .locked)
        lastLoggedLockState = assessment.lockState

        // Vision-Ecken → Preview-Layer-Koordinaten zentral via
        // `ScanCoordinateMapper`. Der Mapper hält den Y-Flip an
        // **einer** Stelle (Vision = Y-up, Preview = Y-down).
        let cornersInView: RectangleCorners? = {
            guard let rect = assessment.smoothedRectangle else { return nil }
            let c = ScanCoordinateMapper.visionCornersToLayer(rect, in: previewLayer)
            if shouldLogMapping {
                let rotation = previewLayer.connection?.videoRotationAngle ?? -1
                appDebugLog("📐 [Mapper Diagnostic]")
                appDebugLog("   previewLayer.bounds = \(previewLayer.bounds)")
                appDebugLog("   previewLayer.frame  = \(previewLayer.frame)")
                appDebugLog("   previewLayer.videoGravity = \(previewLayer.videoGravity.rawValue)")
                appDebugLog("   previewLayer.connection.rotation = \(rotation)°")
                appDebugLog("   Vision rect (Y-up normalized):")
                appDebugLog("     tl=(\(String(format: "%.3f", rect.topLeft.x)), \(String(format: "%.3f", rect.topLeft.y)))")
                appDebugLog("     tr=(\(String(format: "%.3f", rect.topRight.x)), \(String(format: "%.3f", rect.topRight.y)))")
                appDebugLog("     bl=(\(String(format: "%.3f", rect.bottomLeft.x)), \(String(format: "%.3f", rect.bottomLeft.y)))")
                appDebugLog("     br=(\(String(format: "%.3f", rect.bottomRight.x)), \(String(format: "%.3f", rect.bottomRight.y)))")
                appDebugLog("   Mapped to Layer-Points:")
                appDebugLog("     tl=(\(String(format: "%.1f", c.tl.x)), \(String(format: "%.1f", c.tl.y)))")
                appDebugLog("     tr=(\(String(format: "%.1f", c.tr.x)), \(String(format: "%.1f", c.tr.y)))")
                appDebugLog("     bl=(\(String(format: "%.1f", c.bl.x)), \(String(format: "%.1f", c.bl.y)))")
                appDebugLog("     br=(\(String(format: "%.1f", c.br.x)), \(String(format: "%.1f", c.br.y)))")
            }
            return RectangleCorners(topLeft: c.tl, topRight: c.tr, bottomLeft: c.bl, bottomRight: c.br)
        }()

        // Raw-Corners (ungeglättet) für Debug-Overlay: zeigt die echte
        // Vision-Detection direkt, sodass Overlay-vs-Realität-Drift
        // sichtbar wird.
        let rawCornersInView: RectangleCorners? = {
            guard let rect = assessment.rawRectangle else { return nil }
            let c = ScanCoordinateMapper.visionCornersToLayer(rect, in: previewLayer)
            return RectangleCorners(topLeft: c.tl, topRight: c.tr, bottomLeft: c.bl, bottomRight: c.br)
        }()

        // AP12: Auto-Capture-State FIRST evaluieren — dann in die
        // Guidance mit reinpacken, damit die UI synchron dazu pulsen
        // kann. `shouldFireAutoCapture` muss bei jedem Tick laufen
        // (auch bei deaktiviertem Auto), damit der Streak-Zähler
        // nicht abbricht.
        let device = (session.inputs.first as? AVCaptureDeviceInput)?.device
        let gatesOpen = autoCaptureController.shouldFireAutoCapture(
            lockState: assessment.lockState,
            isAdjustingFocus: device?.isAdjustingFocus ?? false,
            isAdjustingExposure: device?.isAdjustingExposure ?? false
        )

        let guidance = SmartScannerGuidance(
            corners: cornersInView,
            rawCorners: rawCornersInView,
            quality: assessment.quality,
            lockState: assessment.lockState,
            isAutoCaptureReady: autoCaptureController.autoCaptureState == .ready
        )

        Task { @MainActor in
            self.delegate?.smartScannerDidUpdateGuidance(guidance)
        }
        if autoCaptureEnabled,
           captureProfile.allowsAutoCapture,
           gatesOpen,
           !isPhotoDeliveryInFlight {
            autoCaptureController.resetStreak()
            capturePhoto()
        }
    }
}

// MARK: - Video-Frame-Processing

extension SmartScannerSession: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Profil-Dispatch:
        //   • vocabularyList → RectangleTracker (full Quality + Auto-
        //     Capture-Trigger via emitGuidance).
        //   • freeText manual → AttentionRegionTracker (weiches
        //     Overlay, kein Auto-Trigger).
        //   • freeText auto/Rahmen → AttentionRegionTracker
        //     (Fokushinweis) + RectangleTracker (Rahmen-Assistenz für
        //     Plakat/Cover/Schild). Beide Tracker laufen, aber das
        //     Result wird **gemeinsam** in `emitAttentionGuidance(...)`
        //     verarbeitet — keine Quality-Hint-Pollution, kein Auto-
        //     Trigger (Profile-Flag `allowsAutoCapture=false` blockt
        //     ohnehin).
        let rectangleAssistEnabled = (captureProfile == .freeText && autoCaptureEnabled)
        let runsRectangle = captureProfile.runsLiveDetection || rectangleAssistEnabled
        let runsAttention = captureProfile.runsAttentionDetection
        guard runsRectangle || runsAttention else { return }

        // Drossel gilt für beide Tracker — sonst feuern wir bei 60fps
        // Vision-Requests, die das CPU-Budget sprengen.
        let now = CACurrentMediaTime()
        guard now - lastProcessedTimestamp >= minFrameInterval else { return }
        lastProcessedTimestamp = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Latest-Frame-Cache für Freeze-Frame on Shutter — nur die
        // Referenz halten, keine UIImage-Konvertierung pro Frame.
        latestPixelBuffer = pixelBuffer

        // **VocabularyList-Pfad**: nur RectangleTracker, mit voller
        // Quality + Auto-Trigger über emitGuidance.
        if captureProfile.runsLiveDetection {
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            let assessment = rectangleTracker.process(pixelBuffer: pixelBuffer)
            emitGuidance(assessment, bufferSize: CGSize(width: width, height: height))
            return
        }

        // **FreeText-Pfad** (manual oder auto): Attention immer
        // (außer im Locked-Mode, dort übernimmt der User die Region),
        // Rectangle-Assist nur wenn der User auf „Rahmen" geschaltet
        // hat — mit dem **assistRectangleTracker** (lockere Config
        // für Plakate/Cover/Schilder).
        if runsAttention {
            var assistAssessment: RectangleTracker.Assessment? = nil
            if rectangleAssistEnabled {
                assistAssessment = assistRectangleTracker.process(pixelBuffer: pixelBuffer)
            }
            switch focusMode {
            case .auto:
                let region = attentionTracker.process(pixelBuffer: pixelBuffer)
                emitAttentionGuidance(region: region, assistRectangle: assistAssessment)
            case .locked:
                emitAttentionGuidance(region: nil, assistRectangle: assistAssessment)
            }
        }
    }
}

// MARK: - Attention-Guidance-Emission

extension SmartScannerSession {
    /// FreeText-Variant von `emitGuidance(...)`. Liefert dem Delegate:
    ///   • `attentionRegion` als visuellen Fokushinweis (immer)
    ///   • `corners` (smoothed) als Rahmen-Assistenz, wenn der User
    ///     den FreeText-„Auto/Rahmen"-Modus aktiv hat und der
    ///     RectangleTracker einen Quad geliefert hat.
    ///
    /// **Wichtig**: kein Auto-Shutter und kein automatischer Crop —
    /// `quality` bleibt konstant `.good`, `isAutoCaptureReady` immer
    /// `false`. FreeText-Profile-Flag `allowsAutoCapture=false`
    /// blockt zusätzlich jeden Trigger-Pfad.
    fileprivate func emitAttentionGuidance(
        region: AttentionRegionTracker.Region?,
        assistRectangle: RectangleTracker.Assessment? = nil
    ) {
        if isPhotoDeliveryInFlight { return }

        // Locked-Mode hat Vorrang: der User-gewählte Rect ist die
        // einzige Attention-Quelle.
        let sourceBox: CGRect?
        if case .locked(let lockedRect) = focusMode {
            sourceBox = lockedRect
        } else {
            sourceBox = region?.boundingBox
        }
        let attentionLayerRect: CGRect? = sourceBox.flatMap { box in
            visionBoxToLayerRect(box)
        }

        // **lastConfidentAttentionBox aktualisieren** — bleibt erhalten
        // als Diagnose-Snapshot. Wird **nicht** automatisch zum Crop.
        switch focusMode {
        case .locked(let lockedRect):
            lastConfidentAttentionBox = lockedRect
        case .auto:
            if let region, region.isStable, region.score >= attentionConfidenceThreshold {
                lastConfidentAttentionBox = region.boundingBox
            }
        }

        // **Rectangle-Assist-Quad** (freeText auto/Rahmen-Modus):
        // Smoothed Quad → Layer-Corners. Wenn nicht gefunden:
        // `corners == nil` → die View rendert keinen Quad-Overlay.
        let assistCornersInView: RectangleCorners? = {
            guard let rect = assistRectangle?.smoothedRectangle else { return nil }
            let c = ScanCoordinateMapper.visionCornersToLayer(rect, in: previewLayer)
            return RectangleCorners(topLeft: c.tl, topRight: c.tr, bottomLeft: c.bl, bottomRight: c.br)
        }()
        let assistRawCornersInView: RectangleCorners? = {
            guard let rect = assistRectangle?.rawRectangle else { return nil }
            let c = ScanCoordinateMapper.visionCornersToLayer(rect, in: previewLayer)
            return RectangleCorners(topLeft: c.tl, topRight: c.tr, bottomLeft: c.bl, bottomRight: c.br)
        }()

        let guidance = SmartScannerGuidance(
            corners: assistCornersInView,
            rawCorners: assistRawCornersInView,
            quality: .good,
            lockState: .searching,
            isAutoCaptureReady: false,
            attentionRegion: attentionLayerRect,
            focusMode: focusMode
        )
        Task { @MainActor in
            self.delegate?.smartScannerDidUpdateGuidance(guidance)
        }

        // **Defense-in-depth**: Selbst wenn `autoCaptureEnabled == true`
        // (FreeText-Auto/Rahmen-Toggle), blockt
        // `captureProfile.allowsAutoCapture == false` jeden Auto-
        // Trigger-Pfad. Auto-Capture existiert ausschließlich für
        // VocabularyList über `emitGuidance(...)`.
    }

    /// Mapped eine Vision-normierte axis-aligned Bounding-Box auf ein
    /// View-Layer-Rect. Da `layerPointConverted` eine rein affine
    /// Transformation (Rotation + Skalierung + Translation) ausführt,
    /// bleibt die Box axis-aligned — wir mappen 4 Ecken und ziehen
    /// die Bounding-Box über ihre Layer-Koordinaten.
    fileprivate func visionBoxToLayerRect(_ visionBox: CGRect) -> CGRect? {
        let cornersVision: [CGPoint] = [
            CGPoint(x: visionBox.minX, y: visionBox.minY),
            CGPoint(x: visionBox.maxX, y: visionBox.minY),
            CGPoint(x: visionBox.minX, y: visionBox.maxY),
            CGPoint(x: visionBox.maxX, y: visionBox.maxY),
        ]
        let cornersLayer = cornersVision.map {
            ScanCoordinateMapper.visionNormalizedToLayer($0, in: previewLayer)
        }
        let xs = cornersLayer.map(\.x)
        let ys = cornersLayer.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max()
        else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Photo-Capture

extension SmartScannerSession: AVCapturePhotoCaptureDelegate {
    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        // Eintritts-Log (Capture-Determinismus): bestätigt, dass
        // AVFoundation die Capture-Delivery tatsächlich ausgelöst hat.
        // Im Fehler-Fall (Delegate feuert nie) greift auf Controller-
        // Seite der Timeout-Guard.
        #if DEBUG
        appDebugLog("🔵 [AVFoundation] didFinishProcessingPhoto fired")
        if let error = error {
            appDebugLog("❌ [AVFoundation] Error: \(error.localizedDescription)")
        }
        #endif

        // Frozen-Quad + Attention-Box + Preview-Layer-Size + Capture-ID
        // lokal rauslesen, dann zurücksetzen.
        let frozenQuad = self.frozenQuadForCapture
        let frozenAttentionBox = self.frozenAttentionForCapture
        let previewLayerSize = self.previewLayerSizeForCapture
        let captureID = self.currentCaptureID ?? UUID()  // Defensive: nie nil ohne Capture
        defer {
            self.frozenQuadForCapture = nil
            self.frozenAttentionForCapture = nil
            self.previewLayerSizeForCapture = nil
            self.currentCaptureID = nil
            self.isPhotoDeliveryInFlight = false
            // **Bug-Fix 2026-04-23**: Tracker-Locks aktiv resetten,
            // damit der NÄCHSTE manuelle Capture nicht den Quad vom
            // GERADE abgelieferten Photo wiederverwendet. Vorher konnte
            // ein zu schnelles 2./3. Foto mit dem alten lock-rect
            // perspektiv-korrigiert werden, was die berichtete
            // 90°-Rotation/Falsch-Zoom/Wrong-Angle-Symptomatik erzeugt.
            // Beide Tracker werden geleert — der nächste Live-Stream-
            // Frame baut frische Locks auf.
            self.rectangleTracker.clearLastLockedRectangle()
            self.assistRectangleTracker.clearLastLockedRectangle()
        }

        if error != nil {
            Task { @MainActor in self.delegate?.smartScannerDidFail(.captureFailed) }
            return
        }

        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            Task { @MainActor in self.delegate?.smartScannerDidFail(.captureFailed) }
            return
        }

        // Debug-Log: finale Pixelmaße des aufgenommenen Fotos. Hilft bei
        // der Diagnose, wenn das Ergebnis „zu klein" wirkt — zeigt klar,
        // ob das Photo selbst bereits niedrig aufgelöst ankommt (Sensor/
        // Settings-Problem) oder ob erst die Nachverarbeitung schlägt.
        #if DEBUG
        let pxW = Int(image.size.width * image.scale)
        let pxH = Int(image.size.height * image.scale)
        appDebugLog("📷 [Scan] Photo received: \(pxW)×\(pxH) px " +
              "(orientation=\(image.imageOrientation.rawValue), scale=\(image.scale))")
        #endif

        // Orientation normalisieren — das Bild kommt mit EXIF-Metadata;
        // fürs Downstream-Processing wollen wir eine „physisch" gerade
        // Portrait-Bitmap, damit die Perspektivkorrektur sauber greift.
        let upright = image.upright()

        Task { @MainActor in
            self.delegate?.smartScannerDidCapturePhoto(
                upright,
                frozenQuad: frozenQuad,
                frozenAttentionBox: frozenAttentionBox,
                previewLayerSize: previewLayerSize,
                captureID: captureID
            )
        }
    }
}

// MARK: - UIImage Orientation Fix

private extension UIImage {
    /// Gibt eine Bitmap zurück, deren Pixel tatsächlich der sichtbaren
    /// Orientierung entsprechen (imageOrientation == .up). Wichtig, weil
    /// CoreImage/Vision-Filter die EXIF-Orientation nicht immer respektieren.
    func upright() -> UIImage {
        guard imageOrientation != .up else { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalized = UIGraphicsGetImageFromCurrentImageContext() ?? self
        UIGraphicsEndImageContext()
        return normalized
    }
}
