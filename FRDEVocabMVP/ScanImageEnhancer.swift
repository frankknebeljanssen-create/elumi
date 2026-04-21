import UIKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal

/// Auto-Enhance-Modul für finale Scan-Aufnahmen.
///
/// Einsatz: **nur auf dem Full-Resolution Still-Image**, nie auf
/// Preview-/Video-Frames (Regel 1 der Produktspec). Läuft als eigener
/// Schritt zwischen `SmartDocumentProcessor`-Perspektivkorrektur und
/// `ImageQualityAnalyzer`-Bewertung.
///
/// Vier Profile:
///   • `.off`             — keine Veränderung
///   • `.auto`             — adaptiv nach Bildmessung (Luminanz-Mittel
///                           entscheidet, ob Brightness/Shadow-Lift nötig)
///   • `.documentStrong`   — Text-orientiert (Kontrast↑, Shadow-Lift,
///                           sehr milde Schärfung). Default für
///                           `vocabularyList`
///   • `.sceneGentle`      — natürliche Szenen (minimale Brightness,
///                           keine Schärfung, keine NR). Default für
///                           `freeText`
///
/// Design-Leitplanken (aus der Spec):
///   • Keine aggressive Manipulation — alle Werte konservativ.
///   • Keine Halo-Artefakte — Sharpen-Radius < 1.5 pt.
///   • Keine Textdetail-Verschlechterung — Noise-Reduction
///     standardmäßig aus; nur bei `auto` mit Low-Light-Signal an.
///   • Unterschiedliche Defaults pro Profil (siehe oben).
///   • Starker Blur → nicht sharpen (würde nur Artefakte amplifizieren) —
///     der Quality-Analyzer soll in dem Fall stattdessen Retake empfehlen.
enum ScanEnhancementProfile: Equatable {
    case off
    case auto
    case documentStrong
    case sceneGentle
    /// **Text-Dense** — für Screenshots, Speisekarten, Displays, kleine
    /// Schrift. Stärkerer Kontrast + mehr Schärfe als `.documentStrong`,
    /// weil Text-Lesbarkeit vor „Scanner-Look" geht. Minimale Brightness,
    /// damit helle Bildschirm-Hintergründe nicht ausbrennen.
    case textDense
}

/// Ergebnis des Enhancement-Laufs — Bild + welche Filter angewendet wurden.
struct ScanEnhancementResult {
    /// Das verbesserte (oder unveränderte) Bild.
    let image: UIImage
    /// Lesbare Liste der tatsächlich angewendeten Filter
    /// (`["brightness+0.04", "contrast×1.12"]`). Wird ins Debug-Log
    /// geschrieben und hilft bei „warum sieht das so aus?".
    let appliedFilters: [String]
    /// Mittlere Luminanz VOR der Bearbeitung (0…1). Informativ —
    /// wird in `.auto` als Entscheidungsgrundlage benutzt.
    let measuredBrightness: Double?
}

enum ScanImageEnhancer {

    // MARK: - Public API

    /// Enhancement sync — **immer auf Background-Queue aufrufen**.
    /// Typisches Laufzeit-Profil: 20-80 ms auf A17.
    static func enhance(
        _ image: UIImage,
        profile: ScanEnhancementProfile
    ) -> ScanEnhancementResult {
        guard profile != .off else {
            return ScanEnhancementResult(image: image, appliedFilters: [], measuredBrightness: nil)
        }
        guard let cg = image.cgImage else {
            return ScanEnhancementResult(image: image, appliedFilters: [], measuredBrightness: nil)
        }

        // AP5: Skip-Enhancement für sehr kleine Bilder. Unter ~400 px
        // Kantenlänge ist der Content meist zu klein, um vom Filter-
        // Stack zu profitieren — Sharpen+Contrast auf solche Thumbs
        // erzeugt eher Artefakte als Verbesserung.
        let minEdge = min(cg.width, cg.height)
        if minEdge < 400 {
            #if DEBUG
            print("📷 [Scan-Enhance] skipped: image too small (min-edge=\(minEdge)px)")
            #endif
            return ScanEnhancementResult(image: image, appliedFilters: ["skipped:small"], measuredBrightness: nil)
        }

        // **TODO 6 — Poor-Quality Early-Return**: pathologische
        // Eingaben filtern, bevor wir den Filter-Stack zünden.
        //
        // Fälle, in denen Enhancement nicht hilft, sondern schadet:
        //   • **Nahezu schwarz** (mean < 0.03) — Linse verdeckt, Raum
        //     dunkel. Brightness-Lift würde nur Sensor-Noise
        //     amplifizieren.
        //   • **Nahezu weiß** (mean > 0.97) — komplett überbelichtet.
        //     Kontrast-Push würde nur geringfügige Helligkeits-
        //     Unterschiede zu Fake-Kanten aufblasen.
        //   • **Fast uniform** (stddev < 5/255) — featureless (z. B.
        //     geschlossener Deckel, Folie). Sharpening erzeugt
        //     Ring-Artefakte, Shadow-Lift bringt Noise hoch.
        //
        // Der Enhancement-Stack bleibt für „normale" Bilder unverändert
        // schnell — die Stats-Messung kostet ~10 ms auf einem 256-Pixel-
        // Grayscale-Downscale und ersetzt gleichzeitig den Mean-Only-
        // Messpfad für `.auto`.
        let stats = measureLuminanceStats(image: image)
        if let stats, stats.mean < 0.03 || stats.mean > 0.97 || stats.stddev < 5 {
            #if DEBUG
            print(String(format: "📷 [Scan-Enhance] skipped: pathological image (mean=%.3f, stddev=%.1f)",
                         stats.mean, stats.stddev))
            #endif
            return ScanEnhancementResult(
                image: image,
                appliedFilters: ["skipped:pathological"],
                measuredBrightness: stats.mean
            )
        }

        let ciImage = CIImage(cgImage: cg)
            .oriented(forExifOrientation: image.imageOrientation.exifOrientation)

        // Bildmessung für `.auto`: wir recyceln die Stats-Messung von
        // oben (sie lief eh schon für den Early-Return-Check) und
        // sparen den zweiten Downscale-Render.
        let measured: Double? = (profile == .auto) ? stats?.mean : nil

        let (enhancedCI, applied) = applyFilterStack(
            on: ciImage,
            profile: profile,
            measuredBrightness: measured
        )

        guard let rendered = renderToUIImage(enhancedCI) else {
            return ScanEnhancementResult(image: image, appliedFilters: [], measuredBrightness: measured)
        }

        #if DEBUG
        let mStr = measured.map { String(format: "%.2f", $0) } ?? "n/a"
        print("📷 [Scan-Enhance] profile=\(profile.debugLabel) meanY=\(mStr) applied=[\(applied.joined(separator: ", "))]")
        #endif

        return ScanEnhancementResult(
            image: rendered,
            appliedFilters: applied,
            measuredBrightness: measured
        )
    }

    /// Async-Wrapper — hält den Aufrufer sauber.
    static func enhanceAsync(
        _ image: UIImage,
        profile: ScanEnhancementProfile
    ) async -> ScanEnhancementResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = enhance(image, profile: profile)
                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Filter Stack

    /// Baut die profilabhängige CIFilter-Kette auf. Jeder Filter fügt
    /// sich selbst in die `applied`-Liste ein, wenn er tatsächlich
    /// angewendet wurde.
    private static func applyFilterStack(
        on inputCI: CIImage,
        profile: ScanEnhancementProfile,
        measuredBrightness: Double?
    ) -> (CIImage, [String]) {
        var current = inputCI
        var applied: [String] = []

        // 1) Color Controls (Brightness + Contrast).
        let (brightness, contrast): (Double, Double) = {
            switch profile {
            case .off:             return (0, 1.0)
            case .documentStrong:  return (0.04, 1.14)
            case .sceneGentle:     return (0.02, 1.06)
            case .textDense:       return (0.02, 1.20)
            case .auto:
                // Adaptiv: dunkles Bild → stärkerer Brightness-Lift.
                // Schwellwerte empirisch. Unter 0.35 ist typisch
                // Low-Light-Szene, über 0.65 ist schon recht hell.
                let meanY = measuredBrightness ?? 0.5
                if meanY < 0.35 {
                    return (0.08, 1.12)  // dunkel → Lift
                } else if meanY > 0.70 {
                    return (0.00, 1.06)  // hell → nur minimaler Kontrast
                } else {
                    return (0.03, 1.10)  // Mittelbereich → sanft
                }
            }
        }()

        if brightness != 0 || contrast != 1.0 {
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = current
            colorControls.brightness = Float(brightness)
            colorControls.contrast = Float(contrast)
            colorControls.saturation = 1.0  // Farbe unverändert — wichtig für AI-Analyse
            if let out = colorControls.outputImage {
                current = out
                if brightness != 0 {
                    applied.append(String(format: "brightness%+.2f", brightness))
                }
                if contrast != 1.0 {
                    applied.append(String(format: "contrast×%.2f", contrast))
                }
            }
        }

        // 2) Highlight/Shadow-Adjust (Glare-Dämpfung + dunkle Stellen lift).
        let (highlight, shadow): (Double, Double) = {
            switch profile {
            case .off:             return (1.0, 0.0)
            case .documentStrong:  return (0.85, 0.20)  // leichte Glare-Dämpfung + Shadow-Lift
            case .sceneGentle:     return (1.0, 0.10)   // nur sanfter Shadow-Lift
            case .textDense:       return (0.90, 0.10)  // leichte Glare-Dämpfung für helle Screens
            case .auto:
                let meanY = measuredBrightness ?? 0.5
                return (meanY > 0.70 ? 0.85 : 1.0,
                        meanY < 0.40 ? 0.25 : 0.10)
            }
        }()

        if highlight != 1.0 || shadow != 0.0 {
            let hs = CIFilter.highlightShadowAdjust()
            hs.inputImage = current
            hs.highlightAmount = Float(highlight)
            hs.shadowAmount = Float(shadow)
            if let out = hs.outputImage {
                current = out
                if highlight != 1.0 {
                    applied.append(String(format: "highlight×%.2f", highlight))
                }
                if shadow != 0.0 {
                    applied.append(String(format: "shadow+%.2f", shadow))
                }
            }
        }

        // 3) Noise-Reduction — standardmäßig aus, nur bei `.auto` und
        //    dunklem Bild vorsichtig dazu. Text-Details werden sonst
        //    geglättet.
        let applyNR: Bool = {
            switch profile {
            case .auto:
                return (measuredBrightness ?? 0.5) < 0.35
            default:
                return false
            }
        }()

        if applyNR {
            let nr = CIFilter.noiseReduction()
            nr.inputImage = current
            nr.noiseLevel = 0.02  // sehr konservativ
            nr.sharpness = 0.3    // kompensiert die Glättung
            if let out = nr.outputImage {
                current = out
                applied.append("noise-reduction(low)")
            }
        }

        // 4) Sharpening — nur `.documentStrong` (für OCR) und nur
        //    leicht. `.sceneGentle` und `.auto`/`.off` verzichten —
        //    Halo-Risiko + Textdetail-Verschlechterung.
        let (sharpenAmount, sharpenRadius): (Double, Double) = {
            switch profile {
            case .documentStrong:  return (0.28, 1.20)
            case .textDense:       return (0.40, 1.30)  // stärker fürs Lesen kleiner Schrift
            default:                return (0.0, 0.0)
            }
        }()

        if sharpenAmount > 0 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = current
            sharpen.sharpness = Float(sharpenAmount)
            sharpen.radius = Float(sharpenRadius)
            if let out = sharpen.outputImage {
                current = out
                applied.append(String(format: "sharpen%.2f/r%.1f", sharpenAmount, sharpenRadius))
            }
        }

        return (current, applied)
    }

    // MARK: - Luminanz-Messung

    /// Mittlere Y-Luminanz **und** Standardabweichung auf einer ~256-
    /// Pixel-Downscale. Dient zwei Zwecken in der Pipeline:
    ///
    ///   1. **Early-Return-Gate** — pathologische Bilder (pitch-black,
    ///      blown-out, featureless) überspringen den Filter-Stack.
    ///   2. **`.auto`-Entscheidung** — dunkel/hell → anderer Filter-
    ///      Preset. Nutzt nur den `mean`-Wert.
    ///
    /// Ein Render-Pass für beide Zwecke — spart ~10 ms gegenüber dem
    /// vorherigen Zwei-Pass-Setup.
    private static func measureLuminanceStats(image: UIImage) -> (mean: Double, stddev: Double)? {
        guard let cg = image.cgImage else { return nil }
        let maxEdge: CGFloat = 256
        let srcW = CGFloat(cg.width), srcH = CGFloat(cg.height)
        let scale = min(1, maxEdge / max(srcW, srcH))
        let w = max(1, Int(srcW * scale))
        let h = max(1, Int(srcH * scale))
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let ctx = CGContext(
            data: nil,
            width: w,
            height: h,
            bitsPerComponent: 8,
            bytesPerRow: w,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let data = ctx.data else { return nil }
        let buffer = UnsafeMutablePointer<UInt8>(OpaquePointer(data))
        let count = w * h
        guard count > 0 else { return nil }

        // Single-Pass: Σx und Σx² für Welford-style mean+std.
        var sum: Int = 0
        var sqSum: Int = 0
        for i in 0..<count {
            let v = Int(buffer[i])
            sum += v
            sqSum += v * v
        }
        let mean = Double(sum) / Double(count)
        let variance = Double(sqSum) / Double(count) - mean * mean
        let stddev = variance > 0 ? sqrt(variance) : 0
        return (mean: mean / 255.0, stddev: stddev)
    }

    // MARK: - Rendering

    /// Rendert CI→UIImage über den App-weiten Metal-Kontext.
    /// Dupliziert bewusst nicht `SmartDocumentProcessor.renderToUIImage` —
    /// das ist `private` dort. Eigener sharedContext hier kostet
    /// Setup-Zeit einmalig, rendert danach billig.
    private static func renderToUIImage(_ ciImage: CIImage) -> UIImage? {
        let context = EnhancerCIContext.shared
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Shared CIContext

private enum EnhancerCIContext {
    static let shared: CIContext = {
        if let device = MTLCreateSystemDefaultDevice() {
            return CIContext(mtlDevice: device)
        }
        return CIContext(options: [.useSoftwareRenderer: false])
    }()
}

// MARK: - Debug Labels

private extension ScanEnhancementProfile {
    var debugLabel: String {
        switch self {
        case .off:              return "off"
        case .auto:             return "auto"
        case .documentStrong:   return "documentStrong"
        case .sceneGentle:      return "sceneGentle"
        case .textDense:        return "textDense"
        }
    }
}

// MARK: - UIImage.Orientation → EXIF (Duplikat-frei via fileprivate)

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

