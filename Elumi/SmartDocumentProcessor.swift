import UIKit
// `@preconcurrency` unterdrückt die Sendable-Warnung beim Weiterreichen
// von `VNRectangleObservation?` über die Background-Queue in
// `processAsync(…)`. Vision meldet die Klasse in iOS-SDKs vor 17 nicht
// als Sendable, obwohl sie in unserem Nutzungsprofil nur gelesen wird.
@preconcurrency import Vision
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal

/// Hochwertige Dokument-Nachbearbeitung für den Scan-Flow.
///
/// Pipeline:
/// 1. **Rechteckerkennung** via `VNDetectRectanglesRequest` — liefert die
///    vier Eckpunkte des Dokuments im Bild.
/// 2. **Padding-Expansion** — die erkannte Fläche wird um +4% auf allen
///    Seiten erweitert, damit bei leicht ungenauer Erkennung keine
///    Buchstaben am Rand abgeschnitten werden.
/// 3. **Perspektivkorrektur** via `CIPerspectiveCorrection` — liefert ein
///    perfekt rechteckiges Bild ohne Schiefe oder Trapezverzerrung.
/// 4. **Enhancement** (optional) — Kontrast +, Helligkeit +, leichtes
///    Schärfen für besseren „Scanner Look" und bessere OCR-Lesbarkeit.
///
/// Wird sowohl vom Vokabel-Scan als auch vom Freier-Text-Flow genutzt.
/// Single source of truth für hochwertige Dokument-Nachbearbeitung.
enum SmartDocumentProcessor {
    // MARK: - Konfiguration

    struct Config {
        /// Prozentualer Rand auf allen Seiten, um den der erkannte
        /// Rechteck-Bereich **erweitert** wird. 0.04 = 4%. Verhindert
        /// abgeschnittene Buchstaben bei leicht ungenauer Erkennung.
        var paddingPercent: CGFloat = 0.04

        /// Mindest-Konfidenz für ein akzeptiertes Rechteck. Unter dieser
        /// Schwelle wird das Originalbild unverändert zurückgegeben.
        var minimumConfidence: Float = 0.55

        /// Mindest-Seitenverhältnis (kurze/lange Seite). Unter 0.2 sind
        /// die Rechtecke meist falsch erkannte Schatten/Linien.
        var minimumAspectRatio: Float = 0.2

        /// Maximale Abweichung von 90° an den Ecken. Vision kann schief
        /// stehende Dokumente besser finden, wenn dieser Wert großzügig ist.
        var quadratureTolerance: Float = 30.0

        /// Mindest-Flächenanteil am Gesamtbild. Kleine Rechtecke sind meist
        /// falsche Detektionen (z. B. ein Text-Absatz statt des Dokuments).
        var minimumAreaFraction: Float = 0.2

        /// Legacy-Flag — bleibt für Call-Sites erhalten, die noch nicht
        /// auf `enhancementProfile` umgestellt sind. Wenn `false`,
        /// wird **nie** enhanced (egal welches Profil gesetzt ist);
        /// `true` lässt das Profil entscheiden.
        var applyEnhancement: Bool = true

        /// Auto-Enhance-Profil für die Post-Capture-Pipeline.
        /// Bestimmt, ob und wie sanft/aggressiv das finale Still-Image
        /// über `ScanImageEnhancer` nachbearbeitet wird.
        ///   • `.documentStrong` — Text-orientiert (für vocabularyList)
        ///   • `.sceneGentle`    — natürlich (für freeText)
        ///   • `.textDense`      — optimiert für kleinen Text (FreeText-textDense)
        ///   • `.auto`           — adaptiv nach Messwerten
        ///   • `.off`            — keine Bearbeitung
        var enhancementProfile: ScanEnhancementProfile = .documentStrong

        /// **Full-Frame-Bypass** (FreeText-Text-Dense-Modus).
        /// Wenn `true`: überspringt Rechteck-Erkennung + Perspektivkorrektur
        /// komplett. Gibt das Bild **unverändert** durch den Enhancer zurück.
        /// Für Screenshots, Speisekarten und Display-Fotos gedacht —
        /// dort gibt es kein Dokument-Quad, und aggressiver Crop würde
        /// Text abschneiden.
        var useFullFrame: Bool = false

        /// Standard-Profil für Vokabel-Scan (OCR-orientiert).
        static let vocabularyOCR = Config(
            paddingPercent: 0.04,
            applyEnhancement: true,
            enhancementProfile: .documentStrong
        )

        /// Profil für Freier-Text (Claude Vision — weicher).
        ///
        /// **FreeText-Stabilisierungs-Slice**: `useFullFrame = true`.
        /// Vorher liess das Profil weiterhin Rechteck-Detection +
        /// Perspektivkorrektur laufen — bei Müslipackungen, Plakaten
        /// und Magazinen führte das zu unerwünschten Verzerrungen,
        /// wenn Vision z. B. eine Karton-Kante als „Dokument" fand.
        ///
        /// Neue Policy: FreeText-Pipeline lässt das Bild geometrisch
        /// **unverändert** und wendet nur den (sanften) Enhancer an.
        /// Der textDense-Sonderpfad bleibt davon getrennt, weil dort
        /// ein noch stärker text-orientiertes Enhancement-Profil läuft.
        static let freierText = Config(
            paddingPercent: 0.04,
            applyEnhancement: true,            // Legacy-Flag an; Profil steuert den tatsächlichen Effekt
            enhancementProfile: .sceneGentle,
            useFullFrame: true
        )

        /// **Text-Dense-Profil**: für Screenshots / Speisekarten /
        /// Displays. Kein Rechteck-Crop, keine Perspektivkorrektur,
        /// nur aggressives Text-Enhancement aufs volle Bild.
        static let textDense = Config(
            paddingPercent: 0.0,
            applyEnhancement: true,
            enhancementProfile: .textDense,
            useFullFrame: true
        )

        /// **FreeText-Rectangle-Assist** (Slice B):
        /// Für den FreeText-„Auto/Rahmen"-Modus. Lässt die Quad-
        /// Detection laufen (`useFullFrame: false`), aber mit dem
        /// **sceneGentle**-Enhancement (statt documentStrong). So wird
        /// ein gefundenes Plakat/Cover/Schild perspektivisch korrigiert,
        /// ohne dass der Text wie im Vokabel-Modus stark nachgeschärft
        /// wird. Im Caller (`runProcessing`) wird das Resultat
        /// **nur dann** verwendet, wenn `didCorrectPerspective == true`;
        /// sonst greift der WYSIWYG-Fallback.
        static let freierTextRectangleAssist = Config(
            paddingPercent: 0.04,
            applyEnhancement: true,
            enhancementProfile: .sceneGentle,
            useFullFrame: false
        )
    }

    // MARK: - Result

    struct ProcessingResult {
        /// Das nachbearbeitete Bild — entweder perspektiv-korrigiert und
        /// enhanced, oder das Original, falls kein Rechteck erkannt wurde.
        let image: UIImage

        /// Hat die Pipeline tatsächlich ein Rechteck gefunden und korrigiert?
        /// Falls false, wurde das Original nur (leicht) nachgeschärft.
        let didCorrectPerspective: Bool

        /// Konfidenz der Rechteckerkennung, falls detected.
        let confidence: Float?

        /// Metriken vom erkannten Rechteck — nil wenn keins gefunden wurde.
        /// Wird vom ImageQualityAnalyzer konsumiert.
        let rectangleMetrics: ImageQualityAnalyzer.RectangleMetrics?
    }

    // MARK: - Public API

    /// Führt die komplette Pipeline synchron aus. Läuft auf dem aufrufenden
    /// Thread — **immer auf einer Background-Queue aufrufen!**
    ///
    /// `fallbackQuad` ist der Live-Quad, der zur Shutter-Zeit zuletzt
    /// **gelockt** war (siehe `SmartScannerSession.frozenQuadForCapture`).
    /// Wird nur genutzt, wenn sowohl `VNDetectDocumentSegmentationRequest`
    /// als auch `VNDetectRectanglesRequest` auf dem Still-Image nichts
    /// liefern. Ohne Fallback würde in diesem Fall das Originalbild
    /// unkorrigiert zurückgegeben.
    static func process(
        _ image: UIImage,
        config: Config = .vocabularyOCR,
        fallbackQuad: VNRectangleObservation? = nil
    ) -> ProcessingResult {
        guard let cgImage = image.cgImage else {
            return ProcessingResult(image: image, didCorrectPerspective: false, confidence: nil, rectangleMetrics: nil)
        }

        // **Full-Frame-Bypass** (Text-Dense-Profil): überspringt
        // komplette Rechteck-Logik. Nur Enhancement aufs volle Bild,
        // dann zurück. Ziel: Text-Bilder (Screenshots, Speisekarten,
        // Displays) **unverkürzt** an die Downstream-Pipeline geben.
        if config.useFullFrame {
            #if DEBUG
            appDebugLog("📷 [Scan] Full-frame bypass active — profile=\(config.enhancementProfile)")
            #endif
            let enhanced: UIImage
            if config.applyEnhancement, config.enhancementProfile != .off {
                let result = ScanImageEnhancer.enhance(image, profile: config.enhancementProfile)
                enhanced = result.image
            } else {
                enhanced = image
            }
            return ProcessingResult(
                image: enhanced,
                didCorrectPerspective: false,
                confidence: nil,
                rectangleMetrics: nil
            )
        }

        // 1. Rechteckerkennung
        let ciImage = CIImage(cgImage: cgImage).oriented(forExifOrientation: image.imageOrientation.exifOrientation)

        // Zuerst Post-Capture-Refinement, dann Fallback auf den Live-Quad.
        let detected = detectBestRectangle(in: cgImage, orientation: image.imageOrientation, config: config)

        guard let rectangle = detected ?? fallbackQuad else {
            // Kein Rechteck gefunden und kein Fallback → optional leichtes
            // Enhancement, aber keine Perspektivkorrektur.
            let enhanced = fallbackEnhancedImage(
                ciImage: ciImage,
                original: image,
                apply: config.applyEnhancement,
                profile: config.enhancementProfile
            )
            return ProcessingResult(image: enhanced, didCorrectPerspective: false, confidence: nil, rectangleMetrics: nil)
        }

        #if DEBUG
        if detected == nil, fallbackQuad != nil {
            appDebugLog("📷 [Scan] Post-capture refinement failed — using frozen live-quad as fallback.")
        }
        let source = (detected != nil) ? "document-segmentation" : "frozen-live-quad"
        appDebugLog(String(
            format: "📷 [Crop] quad used (%@): tl=(%.3f,%.3f) tr=(%.3f,%.3f) bl=(%.3f,%.3f) br=(%.3f,%.3f)",
            source,
            rectangle.topLeft.x, rectangle.topLeft.y,
            rectangle.topRight.x, rectangle.topRight.y,
            rectangle.bottomLeft.x, rectangle.bottomLeft.y,
            rectangle.bottomRight.x, rectangle.bottomRight.y
        ))
        #endif

        // Metriken fürs Quality-Check berechnen, bevor wir expandieren.
        let metrics = rectangleMetrics(from: rectangle)

        // 2. Padding-Expansion + 3. Perspektivkorrektur
        let imageSize = ciImage.extent.size
        let expandedCorners = expandedCorners(
            rectangle: rectangle,
            imageSize: imageSize,
            paddingPercent: config.paddingPercent
        )

        guard let corrected = perspectiveCorrected(ciImage: ciImage, corners: expandedCorners) else {
            let enhanced = fallbackEnhancedImage(
                ciImage: ciImage,
                original: image,
                apply: config.applyEnhancement,
                profile: config.enhancementProfile
            )
            return ProcessingResult(image: enhanced, didCorrectPerspective: false, confidence: rectangle.confidence, rectangleMetrics: metrics)
        }

        // 4. Enhancement — delegiert an `ScanImageEnhancer` (Auto-
        // Enhance-Modul). Profile-Kontrolle:
        //   • `applyEnhancement == false` → skip (Legacy-Off-Schalter)
        //   • sonst greift `config.enhancementProfile`:
        //     documentStrong / sceneGentle / auto / off
        // Der Enhancer rendert selbst zu UIImage zurück; wir bringen
        // das CIImage davor erstmal in eine UIImage-Zwischenstufe.
        let correctedUI: UIImage = {
            if let cg = renderToCGImage(corrected) {
                return UIImage(cgImage: cg)
            }
            return image
        }()

        let finalImage: UIImage
        if config.applyEnhancement, config.enhancementProfile != .off {
            let enhanced = ScanImageEnhancer.enhance(correctedUI, profile: config.enhancementProfile)
            finalImage = enhanced.image
        } else {
            finalImage = correctedUI
        }

        return ProcessingResult(
            image: finalImage,
            didCorrectPerspective: true,
            confidence: rectangle.confidence,
            rectangleMetrics: metrics
        )
    }

    /// Rendert ein CIImage intermediately zu einem CGImage — für den
    /// Enhancer-Handoff, der mit UIImage-API arbeitet. Fehlschlag
    /// liefert nil → Call-Site fällt auf das Eingabebild zurück.
    private static func renderToCGImage(_ ciImage: CIImage) -> CGImage? {
        let context = SharedCIContext.context
        return context.createCGImage(ciImage, from: ciImage.extent)
    }

    // MARK: - Metriken für Quality-Check

    /// Berechnet die Metriken, die der ImageQualityAnalyzer braucht.
    /// Flächenanteil aus normalisierten Koordinaten, Ecken-Schiefe aus
    /// Winkel-Abweichungen, Completeness aus Rand-Abständen.
    private static func rectangleMetrics(from rectangle: VNRectangleObservation) -> ImageQualityAnalyzer.RectangleMetrics {
        let area = Double(rectangle.boundingBox.width * rectangle.boundingBox.height)

        // Min. Abstand irgendeiner Ecke zum Bildrand (normalisiert 0…1).
        let corners = [rectangle.topLeft, rectangle.topRight, rectangle.bottomLeft, rectangle.bottomRight]
        let minDistance = corners.map { p in
            Double(min(p.x, 1 - p.x, p.y, 1 - p.y))
        }.min() ?? 0

        // Max. Ecken-Abweichung von 90°.
        let maxSkew = maxCornerAngleDeviation(rectangle)

        return ImageQualityAnalyzer.RectangleMetrics(
            areaFraction: area,
            maxSkewDegrees: maxSkew,
            minBorderDistance: minDistance
        )
    }

    /// Max. Abweichung eines Ecken-Winkels von 90°, in Grad.
    private static func maxCornerAngleDeviation(_ rect: VNRectangleObservation) -> Double {
        func angle(at p: CGPoint, from a: CGPoint, to b: CGPoint) -> Double {
            let v1 = CGPoint(x: a.x - p.x, y: a.y - p.y)
            let v2 = CGPoint(x: b.x - p.x, y: b.y - p.y)
            let dot = Double(v1.x * v2.x + v1.y * v2.y)
            let m1 = sqrt(Double(v1.x * v1.x + v1.y * v1.y))
            let m2 = sqrt(Double(v2.x * v2.x + v2.y * v2.y))
            guard m1 > 0, m2 > 0 else { return 0 }
            let cosA = max(-1, min(1, dot / (m1 * m2)))
            return acos(cosA) * 180 / .pi
        }

        let angles = [
            angle(at: rect.topLeft,     from: rect.bottomLeft, to: rect.topRight),
            angle(at: rect.topRight,    from: rect.topLeft,    to: rect.bottomRight),
            angle(at: rect.bottomRight, from: rect.topRight,   to: rect.bottomLeft),
            angle(at: rect.bottomLeft,  from: rect.bottomRight, to: rect.topLeft)
        ]
        return angles.map { abs($0 - 90) }.max() ?? 0
    }

    /// Async-Wrapper — hält den Aufrufer sauber, ohne dass er selbst
    /// `DispatchQueue.global().async` schreiben muss.
    static func processAsync(
        _ image: UIImage,
        config: Config = .vocabularyOCR,
        fallbackQuad: VNRectangleObservation? = nil
    ) async -> ProcessingResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = process(image, config: config, fallbackQuad: fallbackQuad)
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Rechteckerkennung

    /// Sucht das beste (größte + konfidenteste) Rechteck im Bild.
    /// Liefert nil, wenn nichts brauchbares gefunden wurde.
    ///
    /// **Post-Capture-Refinement (User-Fix E)**: Zuerst wird
    /// `VNDetectDocumentSegmentationRequest` versucht (iOS 15+) — das
    /// ist ein ML-Modell speziell für Dokument-Segmentierung und liefert
    /// deutlich präzisere Ecken als `VNDetectRectanglesRequest`,
    /// besonders bei schrägen Aufnahmen und unsauberen Kanten.
    /// Wenn Document-Segmentation nichts liefert oder nicht verfügbar
    /// ist, läuft das klassische Rectangles-Request als Fallback. Der
    /// Live-Quad-Fallback passiert eine Ebene höher im `process(…)`.
    private static func detectBestRectangle(
        in cgImage: CGImage,
        orientation: UIImage.Orientation,
        config: Config
    ) -> VNRectangleObservation? {
        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation(orientation),
            options: [:]
        )

        // (1) Dokument-Segmentation bevorzugen (iOS 15+).
        if #available(iOS 15.0, *) {
            if let refined = detectViaDocumentSegmentation(handler: handler) {
                return refined
            }
        }

        // (2) Klassisches Rectangles-Request als Fallback.
        let request = VNDetectRectanglesRequest()
        request.minimumConfidence = config.minimumConfidence
        request.minimumAspectRatio = config.minimumAspectRatio
        request.quadratureTolerance = config.quadratureTolerance
        request.maximumObservations = 8

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else {
            return nil
        }

        // Filtere nach Flächenanteil — zu kleine Rechtecke sind meist Fehldetektionen.
        let filtered = observations.filter { obs in
            let area = obs.boundingBox.width * obs.boundingBox.height
            return Float(area) >= config.minimumAreaFraction
        }

        guard !filtered.isEmpty else { return nil }

        // Wähle das beste: kombinierter Score aus Fläche und Konfidenz.
        return filtered.max { a, b in
            let scoreA = a.confidence * Float(a.boundingBox.width * a.boundingBox.height)
            let scoreB = b.confidence * Float(b.boundingBox.width * b.boundingBox.height)
            return scoreA < scoreB
        }
    }

    /// Post-Capture-Refinement (iOS 15+).
    ///
    /// `VNDetectDocumentSegmentationRequest` ist ein ML-Modell, das
    /// speziell auf Dokument-Segmentierung trainiert wurde. Es liefert
    /// `VNRectangleObservation`-Ergebnisse mit deutlich präziseren
    /// Eckpunkten als `VNDetectRectanglesRequest` — besonders bei
    /// schrägen Aufnahmen, unsauberen Kanten und schwachem Kontrast
    /// (z. B. Papier auf heller Schreibtischfläche).
    ///
    /// Wir wählen die Observation mit dem größten Flächenanteil —
    /// kleine Rechtecke sind meist Artefakte (Absätze, Seitenzahlen).
    /// Ein Confidence-Filter wird nicht angewendet, weil die Request
    /// intern bereits nur plausible Dokumente zurückgibt.
    @available(iOS 15.0, *)
    private static func detectViaDocumentSegmentation(
        handler: VNImageRequestHandler
    ) -> VNRectangleObservation? {
        let request = VNDetectDocumentSegmentationRequest()
        do {
            try handler.perform([request])
        } catch {
            return nil
        }
        guard let results = request.results, !results.isEmpty else {
            return nil
        }
        return results.max { a, b in
            let areaA = a.boundingBox.width * a.boundingBox.height
            let areaB = b.boundingBox.width * b.boundingBox.height
            return areaA < areaB
        }
    }

    // MARK: - Padding-Expansion

    /// Liefert die vier Eckpunkte in Pixel-Koordinaten (bottom-left origin),
    /// leicht nach außen expandiert — ohne die Bildgrenzen zu überschreiten.
    private static func expandedCorners(
        rectangle: VNRectangleObservation,
        imageSize: CGSize,
        paddingPercent: CGFloat
    ) -> (tl: CGPoint, tr: CGPoint, bl: CGPoint, br: CGPoint) {
        // Vision-Ecken → CIImage-Pixel via zentralen Mapper. Vision und
        // CIImage teilen Y-up-Ursprung, daher kein Flip — der Mapper
        // hält diese Konvention an einer Stelle.
        //
        // **WICHTIG**: NIEMALS `visionCornersToLayer` hier verwenden —
        // das würde Preview-Layer-Points liefern, die nicht zur
        // tatsächlichen Bild-Pixel-Fläche passen. Der Crop würde vom
        // Overlay abweichen, das Foto sähe „verrutscht" aus. Der
        // Layer-Mapper gilt ausschließlich für die Live-Preview-
        // Overlay-Darstellung.
        let c = ScanCoordinateMapper.visionCornersToPixel(rectangle, imageSize: imageSize)
        let tl = c.tl
        let tr = c.tr
        let bl = c.bl
        let br = c.br

        // Debug-Trail für Crop-Verifikation (User-Report „Overlay ≠
        // tatsächliches Foto"). Zeigt Vision-Bounding-Box + konkrete
        // Pixel-Ecken + area-Fraction. Abweichung zwischen Overlay
        // und finalem Bild lässt sich anhand der Logs verifizieren.
        #if DEBUG
        let areaFraction = rectangle.boundingBox.width * rectangle.boundingBox.height
        appDebugLog(String(
            format: "📷 [Crop] areaFraction=%.3f | pixelCorners: tl=(%.0f,%.0f) tr=(%.0f,%.0f) bl=(%.0f,%.0f) br=(%.0f,%.0f)",
            areaFraction,
            tl.x, tl.y, tr.x, tr.y, bl.x, bl.y, br.x, br.y
        ))
        #endif

        // Mittelpunkt des Rechtecks — von dort aus expandieren wir jede Ecke
        // nach außen. So wächst das Rechteck in alle Richtungen proportional,
        // auch wenn es schief liegt.
        let centerX = (tl.x + tr.x + bl.x + br.x) / 4
        let centerY = (tl.y + tr.y + bl.y + br.y) / 4

        func expand(_ p: CGPoint) -> CGPoint {
            let dx = p.x - centerX
            let dy = p.y - centerY
            let newX = centerX + dx * (1 + paddingPercent)
            let newY = centerY + dy * (1 + paddingPercent)
            // Clamp an Bildgrenzen, damit wir nicht ins Leere crophen.
            return CGPoint(
                x: min(max(newX, 0), imageSize.width),
                y: min(max(newY, 0), imageSize.height)
            )
        }

        return (tl: expand(tl), tr: expand(tr), bl: expand(bl), br: expand(br))
    }

    // MARK: - Perspektivkorrektur

    private static func perspectiveCorrected(
        ciImage: CIImage,
        corners: (tl: CGPoint, tr: CGPoint, bl: CGPoint, br: CGPoint)
    ) -> CIImage? {
        let filter = CIFilter.perspectiveCorrection()
        filter.inputImage = ciImage
        filter.topLeft = corners.tl
        filter.topRight = corners.tr
        filter.bottomLeft = corners.bl
        filter.bottomRight = corners.br
        return filter.outputImage
    }

    // MARK: - Enhancement
    // **Umgezogen** in `ScanImageEnhancer.swift` (Auto-Enhance-Modul).
    // Dieses File ist jetzt nur noch für Perspektivkorrektur +
    // Rechteckerkennung verantwortlich. Enhancement läuft profile-
    // gesteuert (`.documentStrong` / `.sceneGentle` / `.auto` / `.off`)
    // und hat Debug-Log-Ausgabe pro angewendetem Filter.

    // MARK: - Fallback (kein Rechteck gefunden)

    /// Wenn keine Rechteckerkennung gelang: Original zurückgeben, optional
    /// durch den profilabhängigen `ScanImageEnhancer` gelaufen.
    /// `apply` bleibt das Legacy-Flag — `false` überspringt auch das
    /// Profile-gestützte Enhancement.
    private static func fallbackEnhancedImage(
        ciImage: CIImage,
        original: UIImage,
        apply: Bool,
        profile: ScanEnhancementProfile
    ) -> UIImage {
        guard apply, profile != .off else { return original }
        let enhanced = ScanImageEnhancer.enhance(original, profile: profile)
        return enhanced.image
    }

    // MARK: - Rendering

    /// Rendert ein CIImage zu UIImage. Nutzt den shared CIContext, der
    /// zur Laufzeit gecached wird — wiederholtes Rendern ist billig.
    private static func renderToUIImage(_ ciImage: CIImage) -> UIImage? {
        let context = SharedCIContext.context
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}

// MARK: - Shared CIContext

/// Ein app-weiter CIContext spart teures Setup bei jedem Scan.
/// GPU-basiert (Metal), falls verfügbar, sonst CPU-Fallback.
private enum SharedCIContext {
    static let context: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()
}

// MARK: - UIImage.Orientation → CGImagePropertyOrientation + EXIF

private extension UIImage.Orientation {
    var exifOrientation: Int32 {
        switch self {
        case .up: return 1
        case .down: return 3
        case .left: return 8
        case .right: return 6
        case .upMirrored: return 2
        case .downMirrored: return 4
        case .leftMirrored: return 5
        case .rightMirrored: return 7
        @unknown default: return 1
        }
    }
}

