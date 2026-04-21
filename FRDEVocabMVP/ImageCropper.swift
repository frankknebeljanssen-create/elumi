import UIKit
import CoreGraphics

/// Hilfsfunktionen, um ein UIImage auf eine Vision-normalisierte
/// Bounding-Box zu croppen.
///
/// **Kontext**: `AttentionRegionTracker` und der `RectangleTracker`
/// liefern Boxen in **Vision-Koordinaten** — Y-Up, Ursprung unten
/// links, Werte 0…1. Beim Capture-Crop muss diese Box auf die
/// **Pixel-Koordinaten** des UIImage abgebildet werden (Y-Down,
/// Ursprung oben links, Pixel-Einheiten).
///
/// Der Mapper hier erledigt die Y-Flipping-Konvertierung und das
/// Skalieren an die Bildauflösung. Output ist ein neues UIImage,
/// das exakt die Vision-Box-Region zeigt — orientation-korrekt
/// (Capture-Pipeline ruft vorher `image.upright()` auf, sodass die
/// Pixel-Daten der sichtbaren Orientierung entsprechen).
enum ImageCropper {

    /// Croppt ein UIImage auf eine Vision-normalisierte Bounding-Box.
    ///
    /// - Parameters:
    ///   - image: Das Quell-Bild (sollte upright sein, siehe Kontext).
    ///   - visionBox: Box in Vision-Koords (0…1, Y-Up). Wird intern
    ///     auf Pixel-Koords umgerechnet (Y-Flip, Skalierung).
    ///   - margin: Optionales Padding um die Box (in Vision-Einheiten,
    ///     also 0…1). Default 0 = exakter Crop. Sinnvoll zum Beispiel
    ///     0.02, wenn die Box den Rand zu eng schneidet.
    /// - Returns: Ein neues UIImage des Crop-Bereichs, oder nil wenn
    ///   das Bild kein CGImage liefert oder die Box außerhalb liegt.
    /// Croppt ein UIImage auf einen normalisierten Rect mit
    /// **AVMetadataOutput-Konvention** (Y-Down, Origin oben links).
    /// Direktes Cropping ohne Y-Flip — passt zu dem, was Apple-APIs
    /// wie `AVCaptureVideoPreviewLayer.metadataOutputRectConverted(
    /// fromLayerRect:)` zurückliefern.
    ///
    /// Anwendung: WYSIWYG-Crop des sichtbaren Preview-Ausschnitts auf
    /// das Full-Resolution-Foto. Das Preview-Layer rendert per
    /// `.resizeAspectFill` nur einen Teil des Sensor-Frames; wir
    /// wollen dasselbe Stück Foto am Ende analysieren.
    static func cropToMetadataRect(
        _ image: UIImage,
        normalizedRect rect: CGRect,
        margin: CGFloat = 0
    ) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let pxW = CGFloat(cg.width)
        let pxH = CGFloat(cg.height)

        let padded = rect.insetBy(dx: -margin, dy: -margin)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard padded.width > 0, padded.height > 0 else { return nil }

        // Direkt auf Pixel-Koords skalieren (kein Y-Flip — Y bereits
        // Y-Down, gleiche Konvention wie CG).
        let pxRect = CGRect(
            x: floor(padded.minX * pxW),
            y: floor(padded.minY * pxH),
            width: ceil(padded.width * pxW),
            height: ceil(padded.height * pxH)
        ).integral

        let safeRect = pxRect.intersection(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        guard safeRect.width > 1, safeRect.height > 1 else { return nil }

        guard let croppedCG = cg.cropping(to: safeRect) else { return nil }
        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }

    /// **Analytischer aspectFill-Crop** — schneidet ein Photo so zu,
    /// dass es im aspectFill-Preview eines Containers (z. B.
    /// `AVCaptureVideoPreviewLayer.bounds`) als sichtbarer Bereich
    /// entstanden wäre.
    ///
    /// **Warum analytisch statt `metadataOutputRectConverted(...)`**:
    /// Apple's API liefert je nach Orientation/Rotation andere
    /// Konventionen (Y-Up vs Y-Down, Achsentausch bei Portrait-Capture).
    /// In Praxis-Tests kam das Crop-Ergebnis manchmal seitenverkehrt
    /// oder mit zu kleiner Höhe — User-Bug „unten abgeschnitten".
    ///
    /// Diese Methode rechnet nur mit Photo-Pixel-Ratios und Container-
    /// Aspect-Ratio. Apple's Zoom (`videoZoomFactor`) braucht hier
    /// **kein** separates Handling: das `AVCapturePhotoOutput` liefert
    /// das Photo bereits gezoomt (Sensor-Crop intern), die Aspect-
    /// Ratio des Photos bleibt aber erhalten.
    ///
    /// - Parameters:
    ///   - image: Das volle Photo (orientation-korrigiert via
    ///     `UIImage.upright()`).
    ///   - containerSize: Die Größe des Preview-Containers (z. B.
    ///     `previewLayer.bounds.size`). Aspect-Ratio wird daraus
    ///     berechnet.
    /// - Returns: Center-gecropptes Photo entsprechend aspectFill,
    ///   oder nil bei degenerierten Inputs.
    static func cropToAspectFill(
        _ image: UIImage,
        containerSize: CGSize
    ) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let pxW = CGFloat(cg.width)
        let pxH = CGFloat(cg.height)
        guard pxW > 0, pxH > 0,
              containerSize.width > 0, containerSize.height > 0
        else { return nil }

        let photoAspect = pxW / pxH
        let containerAspect = containerSize.width / containerSize.height

        let visibleW: CGFloat
        let visibleH: CGFloat
        if photoAspect > containerAspect {
            // Photo breiter als Container → links/rechts beschnitten,
            // Höhe voll sichtbar.
            visibleH = pxH
            visibleW = pxH * containerAspect
        } else {
            // Photo schmaler oder gleich → oben/unten beschnitten,
            // Breite voll sichtbar.
            visibleW = pxW
            visibleH = pxW / containerAspect
        }

        let xOffset = (pxW - visibleW) / 2
        let yOffset = (pxH - visibleH) / 2
        let cropRect = CGRect(x: xOffset, y: yOffset, width: visibleW, height: visibleH).integral

        let safeRect = cropRect.intersection(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        guard safeRect.width > 1, safeRect.height > 1 else { return nil }

        guard let croppedCG = cg.cropping(to: safeRect) else { return nil }
        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }

    static func cropToVisionBox(
        _ image: UIImage,
        visionBox: CGRect,
        margin: CGFloat = 0.02
    ) -> UIImage? {
        guard let cg = image.cgImage else { return nil }
        let pxW = CGFloat(cg.width)
        let pxH = CGFloat(cg.height)

        // Optional padding und auf [0,1]² clamp
        let padded = visionBox.insetBy(dx: -margin, dy: -margin)
            .intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard padded.width > 0, padded.height > 0 else { return nil }

        // Y-Flip: Vision Y-Up (origin unten links) → CG Y-Down
        // (origin oben links). neue origin.y = 1 - (originalOrigin.y + height).
        let cgRectNormalized = CGRect(
            x: padded.minX,
            y: 1 - padded.minY - padded.height,
            width: padded.width,
            height: padded.height
        )

        // Auf Pixel-Koords skalieren.
        let pxRect = CGRect(
            x: floor(cgRectNormalized.minX * pxW),
            y: floor(cgRectNormalized.minY * pxH),
            width: ceil(cgRectNormalized.width * pxW),
            height: ceil(cgRectNormalized.height * pxH)
        ).integral

        // Sicherheitsschnitt am Bildrand.
        let safeRect = pxRect.intersection(CGRect(x: 0, y: 0, width: pxW, height: pxH))
        guard safeRect.width > 1, safeRect.height > 1 else { return nil }

        guard let croppedCG = cg.cropping(to: safeRect) else { return nil }
        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }
}
