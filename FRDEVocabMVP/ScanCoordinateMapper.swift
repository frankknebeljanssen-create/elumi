import CoreGraphics
import AVFoundation
import Vision

/// Single Source of Truth für alle Koordinaten-Umrechnungen im Scan-Stack.
///
/// Der Scan-Stack lebt in **drei** unterschiedlichen Koordinatenräumen:
///
/// 1. **Vision-Normalized** (was `VNRectangleObservation` liefert)
///    — Bereich 0…1 auf beiden Achsen, Ursprung **unten links** (Y wächst
///    nach oben, Vision-Konvention).
/// 2. **CIImage-Pixel** (was `CIPerspectiveCorrection` braucht)
///    — Pixel-Koordinaten auf der `.extent.size` des `CIImage`. Ebenfalls
///    **unten links** als Ursprung — deshalb KEIN Y-Flip beim Mapping.
/// 3. **Preview-Layer-Points** (`AVCaptureVideoPreviewLayer`)
///    — SwiftUI-kompatible Points, Ursprung **oben links** (Y wächst nach
///    unten). Der Layer bringt `layerPointConverted(fromCaptureDevicePoint:)`
///    mit, der erwartet **oben-links-normalized** Input — daher flippen
///    wir hier Y **vor** dem Aufruf.
///
/// Vorher lebten diese drei Umrechnungen verteilt in
/// `SmartScannerSession.emitGuidance()` (mit Y-Flip),
/// `SmartDocumentProcessor.expandedCorners()` (ohne Y-Flip) und
/// Ad-hoc in `ManualCropSheet`. Dieser Mapper ist **die** Stelle, an der
/// die Konventionen festgeschrieben sind.
///
/// `enum`-based Namespace statt `struct` — rein statische API, keine
/// Instanziierung nötig.
enum ScanCoordinateMapper {

    // MARK: - Vision-Normalized → CIImage-Pixel

    /// Wandelt einen Vision-normalisierten Punkt (0…1, Ursprung unten-
    /// links) in Pixel-Koordinaten auf der angegebenen Bildgröße um.
    /// Vision und CIImage teilen denselben Y-up-Ursprung — daher einfach
    /// `* imageSize`, **kein** Y-Flip.
    static func visionNormalizedToPixel(
        _ point: CGPoint,
        imageSize: CGSize
    ) -> CGPoint {
        CGPoint(
            x: point.x * imageSize.width,
            y: point.y * imageSize.height
        )
    }

    /// Bequeme 4-Ecken-Variante für `CIPerspectiveCorrection`. Liefert die
    /// Ecken in derselben Reihenfolge wie die Vision-Observation:
    /// topLeft, topRight, bottomLeft, bottomRight.
    static func visionCornersToPixel(
        _ rect: VNRectangleObservation,
        imageSize: CGSize
    ) -> (tl: CGPoint, tr: CGPoint, bl: CGPoint, br: CGPoint) {
        (
            tl: visionNormalizedToPixel(rect.topLeft,     imageSize: imageSize),
            tr: visionNormalizedToPixel(rect.topRight,    imageSize: imageSize),
            bl: visionNormalizedToPixel(rect.bottomLeft,  imageSize: imageSize),
            br: visionNormalizedToPixel(rect.bottomRight, imageSize: imageSize)
        )
    }

    // MARK: - Vision-Normalized → Preview-Layer

    /// Wandelt einen Vision-normalisierten Punkt (Y-up) in einen
    /// Layer-Point um, den SwiftUI als View-Koordinate zeichnen kann.
    ///
    /// **Empirisch validiert** (iOS 18 + `connection.videoRotationAngle
    /// = 90`): `AVCaptureVideoPreviewLayer.layerPointConverted(
    /// fromCaptureDevicePoint:)` interpretiert die Eingabe als
    /// **landscape-native Y-down** — also im unrotiert-sensor-Frame.
    /// Die Rotation (90° CW Richtung portrait) wird intern angewandt.
    ///
    /// Das ist entgegen der verbreiteten Annahme, dass die Methode
    /// die Rotation der `connection` berücksichtigt und
    /// portrait-Y-down-Input erwartet. Ein reiner Y-Flip (Vision
    /// Y-up → portrait Y-down) lieferte daher verschobene Layer-
    /// Koordinaten (TL des Papiers am rechten Bildrand statt links).
    ///
    /// **Korrekte Transformation** (Vision portrait-Y-up → landscape-
    /// native Y-down):
    ///   1. Y-Flip: portrait (vx, 1 − vy) Y-down
    ///   2. Un-rotate 90° CCW (portrait → landscape):
    ///      landscape (py, 1 − px) = (1 − vy, 1 − vx)
    ///
    /// Diagnose-Daten (A4-Blatt, iPhone portrait, iOS 18):
    /// Vision tl=(0.162, 0.791) → Apple-raw (382.6, 137.7) [verrutscht],
    /// mit neuer Formel → Apple-raw (−19.5, 178.1) [korrekt, links-oben].
    static func visionNormalizedToLayer(
        _ point: CGPoint,
        in previewLayer: AVCaptureVideoPreviewLayer
    ) -> CGPoint {
        previewLayer.layerPointConverted(
            fromCaptureDevicePoint: CGPoint(x: 1 - point.y, y: 1 - point.x)
        )
    }

    /// Bequeme 4-Ecken-Variante für den Overlay-Pfad. Nimmt eine
    /// `VNRectangleObservation` und liefert fertige Layer-Corners, die
    /// `QuadrilateralOverlay` direkt zeichnen kann.
    static func visionCornersToLayer(
        _ rect: VNRectangleObservation,
        in previewLayer: AVCaptureVideoPreviewLayer
    ) -> (tl: CGPoint, tr: CGPoint, bl: CGPoint, br: CGPoint) {
        (
            tl: visionNormalizedToLayer(rect.topLeft,     in: previewLayer),
            tr: visionNormalizedToLayer(rect.topRight,    in: previewLayer),
            bl: visionNormalizedToLayer(rect.bottomLeft,  in: previewLayer),
            br: visionNormalizedToLayer(rect.bottomRight, in: previewLayer)
        )
    }

    // MARK: - Preview-Layer → Vision-Normalized (Tap-to-Lock)

    /// Umkehrung von `visionNormalizedToLayer`. Nimmt einen Tap-Punkt
    /// in View-Layer-Koordinaten (Y-down, origin oben links) und
    /// liefert den Vision-normalisierten Punkt (Y-up, origin unten
    /// links), den eine Vision-Observation liefern würde.
    ///
    /// **Herleitung**: `layerPointConverted(fromCaptureDevicePoint:)`
    /// erwartet landscape-native Y-down mit Formel
    /// `input = (1 − vy, 1 − vx)`. `captureDevicePointConverted(
    /// fromLayerPoint:)` invertiert den Layer-Schritt, sodass wir
    /// den capturedevice-Punkt wiederbekommen; die Vertauschung
    /// x/y + Inversion lösen wir separat auf:
    /// ```
    /// devicePoint = (1 − vy, 1 − vx)
    /// ⇒ vy = 1 − devicePoint.x
    /// ⇒ vx = 1 − devicePoint.y
    /// ```
    static func layerPointToVisionNormalized(
        _ layerPoint: CGPoint,
        in previewLayer: AVCaptureVideoPreviewLayer
    ) -> CGPoint {
        let devicePoint = previewLayer.captureDevicePointConverted(
            fromLayerPoint: layerPoint
        )
        return CGPoint(x: 1 - devicePoint.y, y: 1 - devicePoint.x)
    }

    // MARK: - Aspect-Fit (ManualCrop / Review)

    /// Berechnet das sichtbare Image-Rect eines `scaledToFit`-Bildes
    /// innerhalb eines Container-Frames. Nützlich für manuelle Crop-
    /// und Review-Layer, die User-Touches auf Bildpixel abbilden.
    ///
    /// Liefert das Rect **in Container-Koordinaten** (Origin oben links).
    static func aspectFitFrame(
        imageSize: CGSize,
        in containerSize: CGSize
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              containerSize.width > 0, containerSize.height > 0
        else {
            return .zero
        }
        let imageAspect = imageSize.width / imageSize.height
        let containerAspect = containerSize.width / containerSize.height

        let size: CGSize
        if imageAspect > containerAspect {
            // Bild ist breiter → füllt die Container-Breite, lässt oben/unten Luft.
            size = CGSize(width: containerSize.width,
                          height: containerSize.width / imageAspect)
        } else {
            // Bild ist schmaler oder gleich → füllt die Container-Höhe.
            size = CGSize(width: containerSize.height * imageAspect,
                          height: containerSize.height)
        }
        let origin = CGPoint(
            x: (containerSize.width  - size.width)  / 2,
            y: (containerSize.height - size.height) / 2
        )
        return CGRect(origin: origin, size: size)
    }
}
