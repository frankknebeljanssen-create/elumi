import UIKit
import Accelerate
import CoreGraphics

/// Lokale Qualitätsanalyse eines Scan-Bildes — läuft vor dem API-Call,
/// damit schlechte Bilder gar nicht erst die Analyse-Pipeline belasten.
///
/// Sechs Dimensionen (jede 0...1, höher = besser):
/// - **Sharpness** (Laplacian-Varianz) — unscharfe Bilder erkennen
/// - **Contrast** (Luminanz-Standardabweichung) — blasse Bilder erkennen
/// - **Size** (Flächenanteil des Dokuments) — zu weit weg erkennen
/// - **Perspective** (maximale Ecken-Schiefe) — zu schräg erkennen
/// - **Completeness** (Abstand der Ecken zum Bildrand) — abgeschnitten
/// - **Glare-Free** (Anteil nahezu-weißer Pixel) — direkte Licht-
///   Reflexion auf glänzendem Papier/Foliendruck (Slice Glare)
///
/// Gewichteter Durchschnitt → Gesamt-Score → Level (gut/mittel/schlecht).
/// Dauert typisch ~30–80 ms auf einem A17-Gerät.
enum ImageQualityAnalyzer {

    // MARK: - Report

    struct Report {
        let overallScore: Double          // 0...1
        let level: Level
        let issues: [Issue]               // absteigend nach Schwere

        let sharpness: Double
        let contrast: Double
        let sizeFraction: Double
        let perspectiveQuality: Double    // 1 - normalized skew
        let completeness: Double
        /// Glare-Freiheit (0…1, höher = weniger Reflexion). 1.0 bei
        /// normalem Weißpapier ohne Spitzlichter, fällt linear zu 0
        /// wenn große Flächen blown-out (≥ 245/255 Luminanz) sind.
        let glareClean: Double
        /// Mittlere Luminanz (0…1, normalisiert auf 0…255). Wird
        /// genutzt, um `tooDark`-Issues zu erkennen UND um die richtige
        /// `EnhancementProfile`-Auswahl (Schatten-Lift) zu treiben.
        /// **Nicht** in den Overall-Score integriert — dunkle, aber
        /// scharfe und kontrastreiche Bilder bleiben „good".
        let luminanceMean: Double

        enum Level {
            case good        // > 0.8
            case medium      // 0.5 – 0.8
            case poor        // < 0.5

            /// Für Debug-Log-Formatierung.
            var debugLabel: String {
                switch self {
                case .good:   return "good"
                case .medium: return "medium"
                case .poor:   return "poor"
                }
            }
        }

        enum Issue: Equatable, Hashable {
            case blurry
            case lowContrast
            case tooSmall
            case tooSkewed
            case clipped
            case glare
            /// Bild insgesamt zu dunkel (mittlere Luminanz < 0.35).
            /// Triggert im Auto-Optimierungs-Pfad das `.tooDark`-Profil
            /// (Brightness + Shadow-Lift). Nicht im Overall-Score
            /// gewichtet — es reicht, dass der User es als Issue sieht.
            case tooDark

            /// **Diagnose-Hinweis** für den User. Beschreibt **nur** was
            /// die App beobachtet — Empfehlungen wie „Auto-Optimierung
            /// nutzen" stehen NICHT im Hint, weil es dafür einen
            /// expliziten Button im UI gibt (`canBeAutoFixed`).
            ///
            /// Regel (User-Auftrag „Auto-Optimierung Button + Quality
            /// UI Fix"): Jede Aktion, die im Hint genannt wird, MUSS
            /// auch als sichtbarer Button verfügbar sein. Hints, die
            /// nur Verhaltenstipps geben (ruhig halten, näher rangehen,
            /// gerader ausrichten), bleiben Hint-only — dort gibt es
            /// keinen Button, weil keine algorithmische Lösung möglich.
            var hint: String {
                switch self {
                case .blurry:       return "Bild ist unscharf"
                case .lowContrast:  return "Text schwer lesbar"
                case .tooSmall:     return "Näher rangehen oder zoomen"
                case .tooSkewed:    return "Gerader ausrichten"
                case .clipped:      return "Bild neu ausrichten"
                case .glare:        return "Reflexion stört das Bild"
                case .tooDark:      return "Bild ist zu dunkel"
                }
            }

            /// Kann dieses Issue durch Auto-Optimierung **algorithmisch**
            /// (mindestens teilweise) behoben werden?
            ///
            /// - `blurry`, `lowContrast`, `glare`, `tooDark`: ja —
            ///   `EnhancementProfile.recommended(for:)` hat ein
            ///   spezialisiertes Preset für jedes davon.
            /// - `tooSmall`, `tooSkewed`, `clipped`: nein — sind
            ///   physikalische Aufnahme-Probleme, die nur ein erneuter
            ///   Capture lösen kann.
            ///
            /// Das UI nutzt diesen Flag, um zu entscheiden, ob der
            /// „Auto optimieren"-Button angezeigt wird.
            var canBeAutoFixed: Bool {
                switch self {
                case .blurry, .lowContrast, .glare, .tooDark: return true
                case .tooSmall, .tooSkewed, .clipped:         return false
                }
            }

            /// Kurzer Tag für Debug-Logs (ohne User-Formulierung).
            var debugLabel: String {
                switch self {
                case .blurry:       return "blur"
                case .lowContrast:  return "lowContrast"
                case .tooSmall:     return "small"
                case .tooSkewed:    return "skew"
                case .clipped:      return "clip"
                case .glare:        return "glare"
                case .tooDark:      return "dark"
                }
            }
        }

        /// Kurzer Titel über dem Hinweis-Banner.
        var headline: String {
            switch level {
            case .good:   return "Gute Bildqualität"
            case .medium: return "Bild könnte verbessert werden"
            case .poor:   return "Bild zu unscharf oder unvollständig"
            }
        }

        // MARK: - AP13 — Priorisierung + kombinierte Message

        /// Sortiert die Issues nach Aktions-Dringlichkeit: was sollte
        /// der User **zuerst** angehen? Sortierschlüssel orientiert
        /// sich daran, wie „schnell lösbar" und „hoch-impact" die
        /// Korrektur ist:
        ///   1. `.tooSmall`    — Schritt näher, trivial
        ///   2. `.clipped`     — Frame verschieben, trivial
        ///   3. `.blurry`      — ruhiger halten, braucht Übung
        ///   4. `.glare`       — Licht umlenken, manuell
        ///   5. `.lowContrast` — ambientes Licht ändern, schwierigster Fix
        ///
        /// Rückgabe: max 2 Issues — mehr ist Overload und wird vom UI
        /// sowieso nicht gerendert.
        var prioritizedIssues: [Issue] {
            Self.prioritizedIssues(issues)
        }

        /// Static-Helper, nutzbar auch mit externen Issue-Listen
        /// (z. B. für Unit-Tests oder wenn ein Caller die Prioritäts-
        /// logik ohne ganzen Report anwenden will).
        ///
        /// `tooDark` rangiert nach `lowContrast` — beides sind Hinweise
        /// auf eine Beleuchtungs-Lage, die Auto-Optimierung lösen kann.
        static func prioritizedIssues(_ issues: [Issue]) -> [Issue] {
            let priority: [Issue: Int] = [
                .tooSmall:    1,
                .clipped:     2,
                .blurry:      3,
                .glare:       4,
                .lowContrast: 5,
                .tooDark:     6,
                .tooSkewed:   7
            ]
            return issues
                .sorted { priority[$0, default: 99] < priority[$1, default: 99] }
                .prefix(2)
                .map { $0 }
        }

        /// Kombinierte, scanbare 1-Zeilen-Anzeige: bis zu 2 Hinweise
        /// mit „ • " getrennt. Beispiel:
        ///   `"Näher rangehen • Bild nicht vollständig"`
        ///
        /// Leer, wenn es keine Issues gibt.
        var combinedMessage: String {
            prioritizedIssues.map(\.hint).joined(separator: " • ")
        }

        /// Lesbarer Score-Wert für die UI-Badge („Score 72 %"). Rundet
        /// auf 1-Prozent-Schritte und klemmt auf 0…100.
        var scoreDisplay: String {
            let percent = Int((overallScore * 100).rounded())
            return "\(max(0, min(100, percent))) %"
        }

        /// True, wenn mindestens ein erkanntes Issue über Auto-
        /// Optimierung adressierbar ist. Triggert die Sichtbarkeit
        /// des „Auto optimieren"-Buttons im Preview-Screen.
        var hasAutoFixableIssue: Bool {
            issues.contains(where: { $0.canBeAutoFixed })
        }

        /// Kompakter Debug-String mit allen Sub-Scores — geht ins
        /// Log, sobald die Pipeline einen Scan abschließt. Hilft bei
        /// „warum wurde der Scan als mittel/schlecht gemeldet?".
        var debugSummary: String {
            String(format: "overall=%.2f (%@) | sharp=%.2f cont=%.2f size=%.2f persp=%.2f compl=%.2f glare=%.2f lum=%.2f | issues=[%@]",
                   overallScore, level.debugLabel,
                   sharpness, contrast, sizeFraction, perspectiveQuality, completeness, glareClean, luminanceMean,
                   issues.map(\.debugLabel).joined(separator: ","))
        }
    }

    // MARK: - EnhancementProfile (adaptive Auto-Optimization)

    /// Filterparameter für die Auto-Optimierung.
    /// Alle Werte bewusst klein — keine Über-Bearbeitung, nur sanftes
    /// Aufhellen / Schärfen / Kontrast-Hub. Das System wählt **adaptiv**
    /// das passende Profil basierend auf den erkannten `Issue`s.
    ///
    /// Wertebereiche (Konvention):
    ///   • `brightness`      −0.20 …  +0.20 (additive Brightness, 0 = keine)
    ///   • `contrast`         0.50 …   2.00 (multiplikativ, 1.0 = keine)
    ///   • `sharpen`          0.00 …   1.00 (Unsharp-Intensität, 0 = aus)
    ///   • `shadowLift`      −0.50 …  +0.50 (Tonkurven-Lift im Schatten)
    ///   • `highlightReduce`  0.00 …   1.00 (Komprimierung im Lichter-Bereich)
    struct EnhancementProfile: Equatable {
        let brightness: CGFloat
        let contrast: CGFloat
        let sharpen: CGFloat
        let shadowLift: CGFloat
        let highlightReduce: CGFloat

        /// Sanfte Standardwerte — leichte Schärfung, leichter Kontrast,
        /// minimaler Brightness-Boost.
        static let `default` = EnhancementProfile(
            brightness: 0.03, contrast: 1.15, sharpen: 0.25,
            shadowLift: 0.10, highlightReduce: 0.0
        )

        /// Stärkere Schärfung, milder Kontrast — für unscharfe Bilder.
        static let blurry = EnhancementProfile(
            brightness: 0.0,  contrast: 1.10, sharpen: 0.50,
            shadowLift: 0.05, highlightReduce: 0.0
        )

        /// Starker Kontrast + sanfter Shadow-Lift — für blasse Bilder.
        static let lowContrast = EnhancementProfile(
            brightness: 0.02, contrast: 1.25, sharpen: 0.20,
            shadowLift: 0.20, highlightReduce: 0.0
        )

        /// Highlight komprimieren + Brightness leicht senken — gegen
        /// Reflexe auf Folie/Display.
        static let glare = EnhancementProfile(
            brightness: -0.02, contrast: 1.10, sharpen: 0.15,
            shadowLift: 0.10, highlightReduce: 0.30
        )

        /// Brightness + starker Shadow-Lift — für unterbelichtete Szenen.
        static let tooDark = EnhancementProfile(
            brightness: 0.08, contrast: 1.10, sharpen: 0.20,
            shadowLift: 0.30, highlightReduce: 0.0
        )

        /// Wählt ein Profil **adaptiv** anhand der Issue-Liste.
        ///
        /// Prioritätsreihenfolge: `glare` > `blurry` > `lowContrast` >
        /// `tooDark` > sonst `.default`. Mehrere Issues werden bewusst
        /// **nicht** kombiniert — das würde zu Überprozessierung
        /// führen. Stattdessen löst das System das *dominante* Problem.
        ///
        /// Wenn die Issue-Liste leer ist → `.default` (= sanfter Boost,
        /// der ein „gutes" Bild trotzdem etwas verbessert).
        static func recommended(for issues: [Report.Issue]) -> EnhancementProfile {
            if issues.contains(.glare)       { return .glare }
            if issues.contains(.blurry)      { return .blurry }
            if issues.contains(.lowContrast) { return .lowContrast }
            if issues.contains(.tooDark)     { return .tooDark }
            return .default
        }

        /// Kurzname für Debug-Logs.
        var debugLabel: String {
            if self == .glare       { return "glare" }
            if self == .blurry      { return "blurry" }
            if self == .lowContrast { return "lowContrast" }
            if self == .tooDark     { return "tooDark" }
            if self == .default     { return "default" }
            return "custom"
        }
    }

    // MARK: - Input

    /// Optionale Metriken aus dem Perspective-Correction-Schritt. Wenn
    /// vorhanden, werden die rectangle-basierten Checks (Größe, Perspektive,
    /// Completeness) präzise; sonst nutzen wir Fallback-Heuristiken.
    struct RectangleMetrics {
        /// Flächenanteil des erkannten Rechtecks am Originalbild (0...1).
        let areaFraction: Double
        /// Maximale Abweichung einer Ecke von 90° (in Grad).
        let maxSkewDegrees: Double
        /// Minimaler Abstand irgendeiner Ecke zum Bildrand (0...1,
        /// normalisiert auf die Bildlänge).
        let minBorderDistance: Double
    }

    /// Kontext-Hinweise, die bestimmte Checks **relaxen** oder
    /// deaktivieren. Nicht-default-Werte signalisieren, dass der
    /// Aufrufer weiß, dass eine Standard-Metrik hier irreführend wäre.
    struct AnalysisHints {
        /// Capture war „text-dense" — Screenshot, Speisekarte,
        /// Display. Es gibt **kein** erkanntes Rechteck, deshalb sind
        /// Skew/Size/Completeness bedeutungslos (wir neutralisieren
        /// sie). Außerdem reflektieren Displays systembedingt, also
        /// wird die Glare-Schwelle gelockert. Sharpness + Kontrast
        /// bleiben scharf geprüft — blurry/low-contrast-Screenshots
        /// gibt's genauso wie bei Papier.
        var isTextDense: Bool = false
    }

    // MARK: - Public API

    static func analyze(
        image: UIImage,
        rectangleMetrics: RectangleMetrics? = nil,
        hints: AnalysisHints = .init()
    ) -> Report {
        // 1. Pixel-basierte Metriken auf einer heruntergerechneten Fassung
        //    (schnell genug für < 100 ms). Sharpness + Contrast + Glare
        //    + Luminanz-Mean nutzen alle dieselbe Grayscale-Bitmap.
        let (sharpness, contrast, glareClean, luminanceMean) = analyzePixels(image: image)

        // 2. Rechteck-Metriken (falls vorhanden). Bei text-dense
        //    ignorieren wir übergebene Metriken bewusst — der Scan
        //    hat keinen echten Rechteck-Rahmen, alles darauf wäre
        //    Pseudo-Signal.
        let sizeFraction: Double
        let perspectiveQuality: Double
        let completeness: Double

        if hints.isTextDense {
            // Neutrale Top-Werte — Score-Gewicht fließt zu
            // Sharpness/Contrast/Glare, die tatsächlich greifbar sind.
            sizeFraction = 1.0
            perspectiveQuality = 1.0
            completeness = 1.0
        } else if let m = rectangleMetrics {
            sizeFraction = normalizedSize(m.areaFraction)
            perspectiveQuality = normalizedPerspective(m.maxSkewDegrees)
            completeness = normalizedCompleteness(m.minBorderDistance)
        } else {
            // Kein Rechteck erkannt — neutrale Werte, damit Pixel-Metriken
            // (Sharpness/Contrast/Glare) den Score bestimmen.
            sizeFraction = ScanTuning.Quality.neutralSizeFraction
            perspectiveQuality = ScanTuning.Quality.neutralPerspectiveQuality
            completeness = ScanTuning.Quality.neutralCompleteness
        }

        // Gewichteter Score — Schwellen + Gewichte zentral in
        // `ScanTuning.Quality`.
        let weights = ScanTuning.Quality.scoreWeights
        let values: [Double]  = [sharpness, contrast, sizeFraction, perspectiveQuality, completeness, glareClean]
        let overall = zip(weights, values).map(*).reduce(0, +)

        // 4. Issues ableiten — Schwellen zentral in `ScanTuning.Quality`.
        var issues: [Report.Issue] = []
        if sharpness          < ScanTuning.Quality.blurryThreshold      { issues.append(.blurry) }
        if contrast           < ScanTuning.Quality.lowContrastThreshold { issues.append(.lowContrast) }

        // Rect-basierte Issues nur wenn nicht-text-dense — sonst sind
        // sie Pseudo-Signal (siehe oben).
        if !hints.isTextDense {
            if sizeFraction       < ScanTuning.Quality.tooSmallThreshold  { issues.append(.tooSmall) }
            if completeness       < ScanTuning.Quality.clippedThreshold   { issues.append(.clipped) }
            if perspectiveQuality < ScanTuning.Quality.tooSkewedThreshold { issues.append(.tooSkewed) }
        }

        // Glare: bei Displays/Screens tolerieren wir mehr Reflexion
        // (Systembedingt). Bei Papier normale Schwelle.
        let glareThreshold = hints.isTextDense
            ? ScanTuning.Quality.glareThresholdTextDense
            : ScanTuning.Quality.glareThresholdPaper
        if glareClean         < glareThreshold { issues.append(.glare) }

        // TooDark-Check für Auto-Optimierungs-Profil-Auswahl.
        if luminanceMean      < ScanTuning.Quality.tooDarkThreshold { issues.append(.tooDark) }

        let level: Report.Level = {
            if overall > ScanTuning.Quality.goodLevelThreshold { return .good }
            if overall >= ScanTuning.Quality.mediumLevelThreshold { return .medium }
            return .poor
        }()

        return Report(
            overallScore: overall,
            level: level,
            issues: issues,
            sharpness: sharpness,
            contrast: contrast,
            sizeFraction: sizeFraction,
            perspectiveQuality: perspectiveQuality,
            completeness: completeness,
            glareClean: glareClean,
            luminanceMean: luminanceMean
        )
    }

    /// Async-Wrapper auf Background-Queue, damit der Aufrufer nicht
    /// selbst `DispatchQueue.global()` schreiben muss.
    static func analyzeAsync(
        image: UIImage,
        rectangleMetrics: RectangleMetrics? = nil,
        hints: AnalysisHints = .init()
    ) async -> Report {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let report = analyze(image: image, rectangleMetrics: rectangleMetrics, hints: hints)
                continuation.resume(returning: report)
            }
        }
    }

    // MARK: - Pixel-basierte Analyse

    /// Liefert (sharpness, contrast, glareClean, luminanceMean),
    /// alle 0...1.
    ///
    /// Pipeline:
    /// 1. Bild auf ~512px skalieren → Bitmap in 8-bit Grayscale rendern
    /// 2. Laplacian-Kernel via vImage → Varianz = Sharpness
    /// 3. Luminanz-Stddev + Mean aus demselben Bitmap (vDSP_normalize
    ///    liefert beides in einem Pass) → Contrast + LuminanzMean
    /// 4. Near-White-Pixel-Fraction → Glare-Freiheit
    private static func analyzePixels(image: UIImage) -> (sharpness: Double, contrast: Double, glareClean: Double, luminanceMean: Double) {
        guard let gray = grayscaleBitmap(image: image, maxLongEdge: 512) else {
            return (0.5, 0.5, 1.0, 0.5)
        }

        // --- Contrast + Mean: Luminanz-Standardabweichung / 128
        //     (clamped 0...1) und mittlere Luminanz / 255 (0...1).
        let (lumMean, lumStddev) = luminanceMeanAndStddev(pixels: gray.pixels)
        let contrast = lumStddev / 128.0
        let luminanceMean = min(1, max(0, lumMean / 255.0))

        // --- Sharpness: Laplacian-Varianz
        let lapVar = laplacianVariance(pixels: gray.pixels, width: gray.width, height: gray.height)
        // Typische Varianz: gutes Scan-Bild ~200–2000, unscharf <50.
        // Wir mappen log-skaliert auf 0...1.
        let sharpness: Double = {
            guard lapVar > 1 else { return 0 }
            let mapped = (log(lapVar) - log(20)) / (log(800) - log(20))
            return min(1, max(0, mapped))
        }()

        // --- Glare: Anteil der Pixel ≥ 245 (nahe-weiß/blown out).
        let glareFraction = nearWhitePixelFraction(pixels: gray.pixels)
        let glareClean = normalizedGlare(glareFraction)

        return (sharpness, min(1, max(0, contrast)), glareClean, luminanceMean)
    }

    // MARK: - Glare

    /// Anteil der Pixel, deren Luminanz ≥ 245/255 ist. Lässt normales
    /// weißes Papier (typisch 220-240) unberührt, flaggt aber
    /// ausgebrannte Spitzlichter. Der Schwellwert ist bewusst hoch
    /// (245 statt 230) — wir wollen False-Positives auf Weißpapier
    /// absolut vermeiden.
    private static func nearWhitePixelFraction(pixels: [UInt8]) -> Double {
        let n = pixels.count
        guard n > 0 else { return 0 }
        let threshold = ScanTuning.Quality.nearWhitePixelThreshold
        var count: Int = 0
        for p in pixels where p >= threshold {
            count += 1
        }
        return Double(count) / Double(n)
    }

    /// Rampe Glare-Anteil → Glare-Freiheits-Score.
    /// - ≤ 2 % near-white  → 1.0 (sauber)
    /// - 10 % near-white   → 0.0 (heftig verspiegelt)
    /// - dazwischen linear
    ///
    /// Kalibriert so, dass ein komplett weißes Blatt Papier, das mit
    /// Licht von der Decke aufgenommen wird, typisch < 2 % überhalb
    /// 245 hat und damit glareClean == 1.0 bleibt.
    private static func normalizedGlare(_ fraction: Double) -> Double {
        let lo = ScanTuning.Quality.glareRampLow
        let hi = ScanTuning.Quality.glareRampHigh
        if fraction <= lo { return 1.0 }
        if fraction >= hi { return 0.0 }
        return 1.0 - (fraction - lo) / (hi - lo)
    }

    // MARK: - Grayscale Bitmap

    private struct Grayscale {
        let pixels: [UInt8]
        let width: Int
        let height: Int
    }

    /// Rendert das Bild auf maxLongEdge und extrahiert ein 8-bit
    /// Grayscale-Array. Einzige Bitmap-Allokation in der Pipeline.
    private static func grayscaleBitmap(image: UIImage, maxLongEdge: CGFloat) -> Grayscale? {
        guard let cg = image.cgImage else { return nil }

        let srcW = CGFloat(cg.width), srcH = CGFloat(cg.height)
        let scale = min(1, maxLongEdge / max(srcW, srcH))
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
        let pixels = Array(UnsafeBufferPointer(start: buffer, count: w * h))
        return Grayscale(pixels: pixels, width: w, height: h)
    }

    // MARK: - Laplacian

    /// Applying the 3x3 Laplacian kernel via vImage and returning
    /// the variance of the result — klassische "focus measure".
    private static func laplacianVariance(pixels: [UInt8], width: Int, height: Int) -> Double {
        let count = pixels.count
        guard count > 0 else { return 0 }

        // Eingang als Float kopieren — Accelerate rechnet mit Floats.
        var input = [Float](repeating: 0, count: count)
        vDSP_vfltu8(pixels, 1, &input, 1, vDSP_Length(count))

        // 3x3 Laplacian-Kernel (Center = 4, Kanten = -1).
        // Wir nutzen vImage für Convolution — schnell auf Accelerate.
        var output = [Float](repeating: 0, count: count)

        var srcBuffer = input.withUnsafeMutableBufferPointer { ptr -> vImage_Buffer in
            vImage_Buffer(data: ptr.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * MemoryLayout<Float>.size)
        }
        var dstBuffer = output.withUnsafeMutableBufferPointer { ptr -> vImage_Buffer in
            vImage_Buffer(data: ptr.baseAddress, height: vImagePixelCount(height), width: vImagePixelCount(width), rowBytes: width * MemoryLayout<Float>.size)
        }

        let kernel: [Float] = [
             0, -1,  0,
            -1,  4, -1,
             0, -1,  0
        ]
        var divisor: Float = 1
        let error = kernel.withUnsafeBufferPointer { kptr -> vImage_Error in
            vImageConvolve_PlanarF(
                &srcBuffer,
                &dstBuffer,
                nil,
                0, 0,
                kptr.baseAddress!,
                3, 3,
                divisor,
                vImage_Flags(kvImageEdgeExtend)
            )
        }
        _ = divisor  // silence unused warning on some toolchains
        guard error == kvImageNoError else { return 0 }

        // Varianz = mean(x²) - mean(x)²
        var mean: Float = 0
        vDSP_meanv(output, 1, &mean, vDSP_Length(count))

        var sqrs = [Float](repeating: 0, count: count)
        vDSP_vsq(output, 1, &sqrs, 1, vDSP_Length(count))
        var meanOfSquares: Float = 0
        vDSP_meanv(sqrs, 1, &meanOfSquares, vDSP_Length(count))

        let variance = Double(meanOfSquares - mean * mean)
        return max(0, variance)
    }

    // MARK: - Contrast (Luminanz-Stddev)

    private static func luminanceStddev(pixels: [UInt8]) -> Double {
        return luminanceMeanAndStddev(pixels: pixels).stddev
    }

    /// Mean + Standardabweichung in einem Pass (vDSP_normalize liefert
    /// beide ohnehin gleichzeitig). Wir teilen das Resultat zwischen
    /// Contrast-Score und `luminanceMean` (für `tooDark`-Check und
    /// Auto-Optimierungs-Profil-Auswahl).
    private static func luminanceMeanAndStddev(pixels: [UInt8]) -> (mean: Double, stddev: Double) {
        let n = pixels.count
        guard n > 0 else { return (0, 0) }

        var floats = [Float](repeating: 0, count: n)
        vDSP_vfltu8(pixels, 1, &floats, 1, vDSP_Length(n))

        var mean: Float = 0
        var stddev: Float = 0
        vDSP_normalize(floats, 1, nil, 1, &mean, &stddev, vDSP_Length(n))
        return (Double(mean), Double(stddev))
    }

    // MARK: - Rectangle-basierte Normalisierungen

    /// area fraction → 0...1. 0.42+ = optimal, <0.18 = zu klein.
    ///
    /// Rekalibriert nach User-Report „'bitte näher rangehen' kommt bei
    /// jedem Bild, auch wenn die Form perfekt ist". Vorher war die
    /// Schwelle für ‚optimal' bei 0.55 Flächenanteil — das ist für
    /// typische Handhaltungsabstände (~20-30 cm) zu streng. Jetzt
    /// zählt 0.42 (ca. knapp die Hälfte des Bildes) als top, 0.18
    /// (ein Viertel) als untere Grenze.
    private static func normalizedSize(_ areaFraction: Double) -> Double {
        // Lineare Rampe — Werte in `ScanTuning.Quality.sizeRamp{Low,High}`.
        let lo = ScanTuning.Quality.sizeRampLow
        let hi = ScanTuning.Quality.sizeRampHigh
        let mapped = (areaFraction - lo) / (hi - lo)
        return min(1, max(0, mapped))
    }

    /// Max. Ecken-Abweichung von 90° (in Grad) → 0...1.
    /// Rampen-Werte in `ScanTuning.Quality.perspectiveRamp{Low,High}`.
    private static func normalizedPerspective(_ skewDegrees: Double) -> Double {
        let lo = ScanTuning.Quality.perspectiveRampLow
        let hi = ScanTuning.Quality.perspectiveRampHigh
        let mapped = 1 - (skewDegrees - lo) / (hi - lo)
        return min(1, max(0, mapped))
    }

    /// Min. Abstand zum Bildrand (normalized) → 0...1.
    /// 0 = touching edge = schlecht, 0.04+ = genügend.
    private static func normalizedCompleteness(_ minBorderDistance: Double) -> Double {
        let mapped = minBorderDistance / 0.04
        return min(1, max(0, mapped))
    }
}
