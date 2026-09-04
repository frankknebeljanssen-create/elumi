import UIKit
import Vision

/// Findet einen zusammengefassten Textbereich im aufgenommenen Still-
/// Image — für den FreeText-Capture-Flow gedacht.
///
/// Produkt-Kontext (Master-Prompt-Ergänzung):
/// In FreeText-Szenen (Poster, Müslipackungen, Magazincover,
/// Zeitungsartikel) gibt es **kein** verlässliches Dokument-Rechteck.
/// Nach dem Shutter-Klick zeigt der Scanner deshalb statt eines hart
/// gecropten Dokuments die Full-Frame-Aufnahme UND optional einen
/// vorgeschlagenen Text-Ausschnitt an — der User entscheidet:
///   1. „Ganzes Bild verwenden"
///   2. „Vorgeschlagenen Textbereich verwenden"
///   3. „Neu aufnehmen"
///
/// Diese Utility liefert (2) — die zusammengefasste Bounding-Box aller
/// erkannten Text-Blöcke, leicht gepadded, auf Bildpixel umgerechnet.
///
/// Wenn kein plausibler Textbereich gefunden wird (z. B. reines
/// Produktfoto ohne Schrift), liefert die Methode `nil` — das UI zeigt
/// dann nur die beiden Standard-Buttons (Verwenden / Neu aufnehmen).
/// Klassifiziert ein Bild als „Text-Dense" (viele kleine Textblöcke —
/// Screenshot, Speisekarte, Display) oder nicht. Für den FreeText-
/// Modus entscheidet das zwischen:
///   • Dense → Rectangle-Detection + Perspektivkorrektur **überspringen**,
///     volles Bild verwenden, aggressives Text-Enhancement
///   • Nicht dense → klassischer freeText-Flow (opportunistische
///     Dokument-Refinement)
///
/// Läuft **ausschließlich** im freeText-Profil (vocabularyList bleibt
/// unverändert).
enum TextDensityDetector {

    /// Entscheidung über Text-Dichte. Läuft auf Background-Queue.
    static func isTextDenseAsync(_ image: UIImage) async -> Bool {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = isTextDense(image)
                continuation.resume(returning: result)
            }
        }
    }

    /// Synchron-Variante — immer von Background-Queue aufrufen.
    static func isTextDense(_ image: UIImage) -> Bool {
        guard let cg = image.cgImage else { return false }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        // Kleinere minimumTextHeight als der Region-Detector, weil wir
        // hier gerade das Signal „viele kleine Textboxen" suchen.
        request.minimumTextHeight = 0.008

        let handler = VNImageRequestHandler(
            cgImage: cg,
            orientation: CGImagePropertyOrientation(image.imageOrientation),
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            return false
        }
        guard let observations = request.results else { return false }

        let boxCount = observations.count
        let averageHeight = observations.isEmpty ? 0 :
            observations.map { Double($0.boundingBox.height) }.reduce(0, +) / Double(observations.count)

        // Dense = viele Boxen ODER viele Boxen mit sehr kleiner Höhe.
        // Schwellwerte empirisch: ab 10 Textboxen liegt ein Screenshot/
        // Speisekarten-Szenario nahe. Alternativ greift die Kombi
        // „mittlere Textbox < 4 % Bildhöhe UND min 6 Boxen".
        let isDense = (boxCount >= 10) || (averageHeight < 0.04 && boxCount >= 6)

        #if DEBUG
        appDebugLog("🧠 [TextDensity] boxes=\(boxCount), avgHeight=\(String(format: "%.3f", averageHeight)) → dense=\(isDense)")
        #endif
        return isDense
    }
}

enum SmartTextRegionDetector {

    /// Cropped die erkannte Text-Region aus dem Original-Bild und
    /// liefert das gecropte `UIImage` zurück. Nil, wenn:
    ///   • keine Text-Observations erkannt wurden
    ///   • die erkannte Region praktisch das gesamte Bild abdeckt
    ///     (dann macht der Crop keinen Sinn)
    ///   • das Cropping selbst fehlschlägt
    ///
    /// Wichtig: die Methode läuft auf einer Background-Queue und
    /// dauert ~100-300 ms auf einem A15-Gerät. Immer async aufrufen.
    static func detectCropAsync(_ image: UIImage) async -> UIImage? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = detectCrop(image)
                continuation.resume(returning: result)
            }
        }
    }

    /// Synchrone Variante — läuft auf dem aufrufenden Thread. **Immer
    /// von Background-Queue aufrufen**, sonst blockiert die UI.
    static func detectCrop(_ image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        // VNRecognizeTextRequest mit .fast — wir brauchen nur die
        // Positionen, keine exakten Transkripte; `.fast` spart ~40 %
        // Laufzeit gegenüber `.accurate`.
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.015  // 1.5 % Bildhöhe → filtert Rauschen

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation),
            options: [:]
        )
        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else {
            return nil
        }

        // Zusammenfassen: Bounding-Box aller erkannten Text-Blöcke.
        // Vision-Koordinaten (normiert, Y-up).
        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX: CGFloat = 0
        var maxY: CGFloat = 0
        for obs in observations {
            let box = obs.boundingBox
            minX = min(minX, box.minX)
            minY = min(minY, box.minY)
            maxX = max(maxX, box.maxX)
            maxY = max(maxY, box.maxY)
        }
        guard minX.isFinite, minY.isFinite, maxX > minX, maxY > minY else {
            return nil
        }

        // Padding: 4 % Randabstand nach außen, damit keine Buchstaben
        // am Crop-Rand kleben.
        let padding: CGFloat = 0.04
        let paddedMinX = max(0, minX - padding)
        let paddedMinY = max(0, minY - padding)
        let paddedMaxX = min(1, maxX + padding)
        let paddedMaxY = min(1, maxY + padding)

        // „Region ist praktisch das gesamte Bild" → kein Smart-Crop
        // nötig, User sieht ohnehin Full-Frame als Hauptvariante.
        let coverage = (paddedMaxX - paddedMinX) * (paddedMaxY - paddedMinY)
        if coverage >= 0.85 {
            return nil
        }

        // Vision-Y-up → UIImage-Pixel (Y-down).
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)
        let cropRect = CGRect(
            x: paddedMinX * imgW,
            y: (1 - paddedMaxY) * imgH,
            width: (paddedMaxX - paddedMinX) * imgW,
            height: (paddedMaxY - paddedMinY) * imgH
        ).integral

        guard cropRect.width > 0, cropRect.height > 0,
              let cropped = cgImage.cropping(to: cropRect)
        else {
            return nil
        }

        return UIImage(
            cgImage: cropped,
            scale: image.scale,
            orientation: image.imageOrientation
        )
    }
}
