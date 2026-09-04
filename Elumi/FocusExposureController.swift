import AVFoundation
import CoreGraphics

/// Dokumentzentrierte Fokus-/Belichtungssteuerung für den Smart Scanner.
///
/// Vorher: `AVCaptureDevice` lief mit den Default-Modi
/// (`continuousAutoFocus` + `continuousAutoExposure`) und AV suchte sich
/// den Fokuspunkt selbst. Auf einem Schreibtisch mit Dokument +
/// Hintergrund greift das oft daneben — der Fokus sitzt auf dem Holz,
/// nicht auf dem Papier.
///
/// Diese Utility:
/// 1. **Tap-to-Focus** — User tippt in den Preview-Layer, wir setzen
///    Focus + Exposure auf den getappten Punkt (einmalig, dann zurück
///    auf continuous).
/// 2. **Dokumentzentrum** — wenn der RectangleTracker ein stabiles
///    Dokument liefert, setzen wir Focus + Exposure auf dessen
///    Mittelpunkt. So konvergiert der Scanner automatisch auf die
///    Papierfläche, nicht den Tisch dahinter.
/// 3. **Reset** — beim Stop oder Profilwechsel zurück auf continuous,
///    damit die nächste Szene frisch beginnt.
///
/// Thread-Modell: Methoden sind queue-agnostisch, der Aufrufer (der
/// `SmartScannerSession` auf `sessionQueue`) ist fürs Serialisieren
/// zuständig. AVCaptureDevice-Konfiguration muss zwischen
/// `lockForConfiguration()` und `unlockForConfiguration()` gefasst
/// sein — wir kapseln das zentral.
enum FocusExposureController {

    // MARK: - Public API

    /// Setzt Focus + Exposure auf einen spezifischen Punkt im
    /// **capture-device normalisierten** Koordinatensystem (0…1,
    /// Ursprung oben links). Wird z. B. bei Tap-to-Focus aus der UI
    /// aufgerufen — die UI muss den Touch-Punkt vorher via
    /// `previewLayer.captureDevicePointConverted(fromLayerPoint:)`
    /// umrechnen.
    ///
    /// Nach dem Antriggern wechselt der Device-Modus auf `autoFocus` /
    /// `autoExpose` — einmalige Konvergenz, danach stehen bleibt, bis
    /// `resetToContinuous` wieder angestoßen wird.
    static func focus(
        device: AVCaptureDevice,
        atPoint point: CGPoint,
        autoReset: Bool = true
    ) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = point
            }
            if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = point
            }
            if device.isExposureModeSupported(.autoExpose) {
                device.exposureMode = .autoExpose
            }
            // Subjekt-Bereich-Änderungs-Monitoring aktivieren — AV
            // meldet dann über `.subjectAreaDidChangeNotification`,
            // wenn die Szene wechselt, und der Aufrufer kann bei
            // Bedarf auf continuous zurückstellen.
            if autoReset {
                device.isSubjectAreaChangeMonitoringEnabled = true
            }
        } catch {
            #if DEBUG
            appDebugLog("📷 [FocusExp] lockForConfiguration fehlgeschlagen: \(error)")
            #endif
        }
    }

    /// Setzt Focus + Exposure zurück auf den dokumentzentrierten
    /// **continuous**-Modus. Nach diesem Aufruf fokussiert AV wieder
    /// fortlaufend — ideal während der Scanner gerade sucht.
    static func resetToContinuous(device: AVCaptureDevice) {
        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
            }
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }
            // Zentrumspunkt als Default. Vision wächst von hier aus
            // nach außen — das Dokument liegt auf einem iPhone meist
            // mittig.
            let center = CGPoint(x: 0.5, y: 0.5)
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = center
            }
            if device.isExposurePointOfInterestSupported {
                device.exposurePointOfInterest = center
            }
            device.isSubjectAreaChangeMonitoringEnabled = true
        } catch {
            #if DEBUG
            appDebugLog("📷 [FocusExp] resetToContinuous fehlgeschlagen: \(error)")
            #endif
        }
    }

    /// Setzt Focus + Exposure auf den Mittelpunkt eines gegebenen
    /// Dokumentquads (normalisiert, Vision-Koordinaten mit Y-unten).
    /// Die Funktion rechnet Vision → capture-device-Koordinaten
    /// (beide 0…1, aber Y ist gespiegelt) und triggert eine einmalige
    /// Konvergenz.
    static func focusOnDocumentCenter(
        device: AVCaptureDevice,
        visionQuadCenter: CGPoint
    ) {
        // Vision: Y wächst nach oben. Capture-Device-Punkt: Y wächst
        // nach unten. Flip wie in `ScanCoordinateMapper.visionNormalizedToLayer`.
        let devicePoint = CGPoint(
            x: visionQuadCenter.x,
            y: 1 - visionQuadCenter.y
        )
        focus(device: device, atPoint: devicePoint, autoReset: true)
    }
}
