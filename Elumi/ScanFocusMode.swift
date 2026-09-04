import CoreGraphics

/// Fokus-Steuerung im FreeText-Scan — entweder automatisch (System
/// entscheidet, wo der zentrale Bereich ist) oder vom User gelockt
/// auf einen spezifischen Ausschnitt.
///
/// **Nicht zu verwechseln mit dem AVFoundation-Kamera-Fokus** (der
/// sitzt am Capture-Device und wird über `FocusExposureController`
/// gesteuert). `FocusMode` hier bezeichnet den **konzeptionellen**
/// Bereich, auf den das System bei der Analyse achten soll — der
/// Overlay folgt diesem Modus, und die spätere KI-Analyse kann auf
/// den Locked-Bereich vorcroppen.
///
/// **Koordinaten-Konvention**: der CGRect im `.locked`-Fall liegt in
/// **Vision-normalisierten** Koordinaten (0…1 auf beiden Achsen,
/// Ursprung unten links, Y-up). Dieselbe Konvention wie
/// `VNRectangleObservation.boundingBox`. Umrechnung in Layer-Points
/// für den Overlay läuft über `ScanCoordinateMapper.visionBoxToLayerRect`
/// (analog zur Attention-Region).
///
/// **Produkt-Verhalten**:
///   • Default `.auto` — `AttentionRegionTracker` detektiert zentralen
///     Text-/Content-Bereich und zeigt weichen Overlay.
///   • `.locked(rect)` — User hat einen Bereich durch Tap „gepinnt";
///     der Attention-Tracker schläft (spart CPU + verhindert
///     Überschreiben des gelockten Overlays), der Overlay bleibt
///     sichtbar stabil mit visuell stärkerer Behandlung + Lock-Icon.
enum FocusMode: Equatable {
    case auto
    case locked(CGRect)

    /// True, wenn der User gerade einen spezifischen Bereich gelockt
    /// hat. Praktisch für SwiftUI-Bedingungen („`.tint(isLocked ?
    /// .blue : .white)`").
    var isLocked: Bool {
        if case .locked = self { return true }
        return false
    }

    /// Der gelockte Rect in Vision-Koordinaten, sofern `.locked`.
    var lockedRect: CGRect? {
        if case .locked(let r) = self { return r }
        return nil
    }
}
