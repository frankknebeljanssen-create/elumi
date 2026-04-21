import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// **Adaptive Auto-Optimierung** für Scan-Bilder.
///
/// Wendet eine sanfte CoreImage-Filter-Kette auf ein UIImage an,
/// gesteuert durch ein `ImageQualityAnalyzer.EnhancementProfile`.
/// Die Profile sind problem-spezifisch (blurry, lowContrast, glare,
/// tooDark, default) — siehe `EnhancementProfile.recommended(for:)`.
///
/// **Design-Prinzipien**:
///   1. **Keine Über-Bearbeitung** — alle Werte bleiben in einem
///      konservativen Bereich (siehe `EnhancementProfile`-Doc).
///   2. **Reproduzierbar** — jeder Aufruf mit demselben Input liefert
///      denselben Output (kein Random, kein State).
///   3. **Background-tauglich** — kein MainActor, kein UIKit-Render,
///      kann auf einer beliebigen `DispatchQueue.global()` laufen.
///
/// **Filter-Kette** (in Reihenfolge):
///   1. Brightness/Contrast — `CIColorControls` (Brightness, Contrast,
///      Saturation = 1.0)
///   2. Shadow-Lift / Highlight-Reduce — `CIHighlightShadowAdjust`
///   3. Schärfung — `CIUnsharpMask` mit Radius 1.5, Intensity = profile.sharpen
///
/// Skip-Logik: ist `profile == .default` UND alle Werte minimal,
/// liefert `optimize(_:profile:)` das Original (no-op) zurück.
enum ImageEnhancer {

    /// Geteiltes Context-Singleton — CIContext-Setup ist teuer
    /// (~30-50 ms beim ersten Render), Wiederverwendung amortisiert.
    /// `useSoftwareRenderer: false` → Metal/GPU-Pfad.
    private static let sharedContext: CIContext = {
        CIContext(options: [
            .useSoftwareRenderer: false,
            .priorityRequestLow: true       // Background-friendly Scheduling
        ])
    }()

    /// Wendet das Profil auf das Bild an. Gibt das Original zurück,
    /// wenn das Profil keine effektive Änderung verursacht oder das
    /// CGImage nicht zugänglich ist.
    ///
    /// **Performance**: typisch 80–200 ms für 8-MP-Bilder auf einem
    /// A17 (Metal-Pfad). Caller sollten das auf `DispatchQueue.global()`
    /// oder via `optimizeAsync(_:profile:)` ausführen.
    static func optimize(
        _ image: UIImage,
        profile: ImageQualityAnalyzer.EnhancementProfile
    ) -> UIImage {
        guard let cgInput = image.cgImage else { return image }
        var ci = CIImage(cgImage: cgInput)

        // 1. Color-Controls — Brightness + Contrast.
        if profile.brightness != 0 || profile.contrast != 1.0 {
            let cc = CIFilter.colorControls()
            cc.inputImage = ci
            cc.brightness = Float(profile.brightness)
            cc.contrast = Float(profile.contrast)
            cc.saturation = 1.0
            if let out = cc.outputImage { ci = out }
        }

        // 2. Highlight/Shadow-Adjust — sanftes Aufhellen der Schatten,
        //    optional Komprimieren der Lichter (gegen Glare).
        if profile.shadowLift != 0 || profile.highlightReduce != 0 {
            let hs = CIFilter.highlightShadowAdjust()
            hs.inputImage = ci
            hs.radius = 4
            hs.shadowAmount = Float(profile.shadowLift)
            // CIHighlightShadowAdjust: highlightAmount 1.0 = neutral,
            // 0.0 = volle Komprimierung. Wir mappen highlightReduce
            // (0…1) entsprechend: 0 = neutral, 1 = volle Reduktion.
            hs.highlightAmount = Float(1.0 - profile.highlightReduce)
            if let out = hs.outputImage { ci = out }
        }

        // 3. Schärfung — `CIUnsharpMask` mit konservativem Radius.
        if profile.sharpen > 0 {
            let um = CIFilter.unsharpMask()
            um.inputImage = ci
            um.radius = 1.5
            um.intensity = Float(profile.sharpen)
            if let out = um.outputImage { ci = out }
        }

        // Render zurück nach UIImage. Falls CIContext nichts liefert
        // (sehr selten — z. B. extrem große Bilder, OOM), Original
        // zurückgeben statt zu crashen.
        guard let cgOutput = sharedContext.createCGImage(ci, from: ci.extent)
        else { return image }
        return UIImage(cgImage: cgOutput, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Async-Wrapper auf Background-Queue. Caller muss das Resultat
    /// selbst auf den MainActor zurückbringen, falls UI-relevant.
    static func optimizeAsync(
        _ image: UIImage,
        profile: ImageQualityAnalyzer.EnhancementProfile
    ) async -> UIImage {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = optimize(image, profile: profile)
                continuation.resume(returning: result)
            }
        }
    }
}
