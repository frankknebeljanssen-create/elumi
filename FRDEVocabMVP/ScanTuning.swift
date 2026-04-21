import Foundation
import CoreGraphics

/// **Zentrale Tuning-Konstanten für das Scan-Modul.**
///
/// Alle Magic Numbers, die früher inline in `ImageQualityAnalyzer.analyze(...)`,
/// `SmartScannerSession` und `AutoCaptureController` als hardcoded-`Double`
/// /  `Float`/`CGFloat` lebten, sind hier gesammelt. Pro-Tracker-Konfigs
/// (`RectangleTracker.Config`, `AttentionRegionTracker`-private-lets) bleiben
/// in den Tracker-Dateien — sie sind dort bereits strukturiert.
///
/// **Warum hier zentral?**
///   • Tuning ohne Code-Such-und-Find quer durch 5 Dateien.
///   • Klar-trennbar Architektur-Konstante vs. inline-Berechnung.
///   • Doc-Comments machen die Intention der Werte explizit (warum 0.5,
///     warum 0.28, etc.).
///
/// Kein State, keine Mutation — alles `static let` in einem `enum`-Namespace.
enum ScanTuning {

    // MARK: - Quality

    /// Konstanten für den `ImageQualityAnalyzer`.
    enum Quality {
        // ── Score-Gewichtung ───────────────────────────────────────
        /// **Score-Gewichte** für die 6 Sub-Metriken. Reihenfolge muss
        /// zu `[sharpness, contrast, sizeFraction, perspectiveQuality,
        /// completeness, glareClean]` passen.
        ///
        /// Begründung:
        ///   • `sharpness` (0.26): dominantester OCR-Faktor.
        ///   • `sizeFraction` (0.20): zweitwichtigster — kleine Dokumente
        ///     scheitern an OCR auch bei perfekter Schärfe.
        ///   • `contrast` (0.15) + `completeness` (0.15): mittlere Wichtung.
        ///   • `perspectiveQuality` (0.14): leicht abgewertet, weil unsere
        ///     Perspektivkorrektur das in der Pipeline schon ausgleicht.
        ///   • `glareClean` (0.10): kleinste Wichtung — relevant aber nicht
        ///     dominant. Höhere Werte würden normales Weißpapier-Foto
        ///     fälschlich abwerten.
        static let scoreWeights: [Double] = [0.26, 0.15, 0.20, 0.14, 0.15, 0.10]

        // ── Level-Grenzen (Report.Level) ───────────────────────────
        /// `overallScore > goodLevelThreshold` → `.good`.
        static let goodLevelThreshold: Double = 0.8
        /// `overallScore >= mediumLevelThreshold` → `.medium`.
        /// Darunter: `.poor`.
        static let mediumLevelThreshold: Double = 0.5

        // ── Issue-Schwellen ────────────────────────────────────────
        /// `sharpness < blurryThreshold` → `.blurry`-Issue.
        static let blurryThreshold: Double = 0.5
        /// `contrast < lowContrastThreshold` → `.lowContrast`-Issue.
        static let lowContrastThreshold: Double = 0.5
        /// `sizeFraction < tooSmallThreshold` → `.tooSmall`-Issue.
        /// Vorher 0.5 → 0.35 (User-Bug „kommt bei jedem Bild").
        static let tooSmallThreshold: Double = 0.35
        /// `completeness < clippedThreshold` → `.clipped`-Issue.
        static let clippedThreshold: Double = 0.5
        /// `perspectiveQuality < tooSkewedThreshold` → `.tooSkewed`-Issue.
        static let tooSkewedThreshold: Double = 0.5
        /// `luminanceMean < tooDarkThreshold` → `.tooDark`-Issue.
        /// Triggert das Auto-Optimierungs-Profil mit Brightness-Boost.
        static let tooDarkThreshold: Double = 0.35

        // ── Glare-Detection ────────────────────────────────────────
        /// `glareClean < glareThresholdPaper` (normales Papier) → `.glare`.
        static let glareThresholdPaper: Double = 0.6
        /// `glareClean < glareThresholdTextDense` (Display/Screen-Capture).
        /// Lockerer, weil Bildschirm-Reflexe systembedingt sind.
        static let glareThresholdTextDense: Double = 0.35

        // ── Neutrale Fallback-Werte (kein Rechteck-Match) ──────────
        /// Wenn weder `RectangleMetrics` noch `text-dense`-Hint vorhanden,
        /// werden diese neutralen Werte für Size/Perspective/Completeness
        /// genutzt — Pixel-Metriken (Sharpness/Contrast/Glare) bestimmen
        /// dann den Overall-Score.
        static let neutralSizeFraction: Double = 0.6
        static let neutralPerspectiveQuality: Double = 0.7
        static let neutralCompleteness: Double = 0.7

        // ── normalizedSize Rampe ───────────────────────────────────
        /// Lineare Rampe: `areaFraction <= sizeRampLow` → 0,
        /// `areaFraction >= sizeRampHigh` → 1.
        /// Vorher 0.55 (high) → 0.42 (User-Bug-Fix).
        static let sizeRampLow: Double = 0.18
        static let sizeRampHigh: Double = 0.42

        // ── normalizedPerspective Rampe (Skew in Grad) ─────────────
        /// `skew <= perspectiveRampLow°` → 1, `skew >= perspectiveRampHigh°` → 0.
        static let perspectiveRampLow: Double = 5
        static let perspectiveRampHigh: Double = 35

        // ── normalizedGlare Rampe (Anteil weißer Pixel) ────────────
        /// `nearWhiteFraction <= glareRampLow` → 1.0 (sauber),
        /// `nearWhiteFraction >= glareRampHigh` → 0 (heftig verspiegelt).
        static let glareRampLow: Double = 0.02
        static let glareRampHigh: Double = 0.10

        // ── Glare-Pixel-Threshold (8-bit Luminanz) ─────────────────
        /// Pixel mit Luminanz ≥ diesem Wert zählen als "near-white"
        /// (potenziell ausgebrannt durch Glare). 245/255 lässt normales
        /// Weißpapier (220-240) durchgehen, flaggt nur Spitzlichter.
        static let nearWhitePixelThreshold: UInt8 = 245
    }

    // MARK: - Camera / Session

    /// Konstanten für `SmartScannerSession`.
    enum Camera {
        /// **Frame-Drossel** — Vision-Pipeline läuft auf max. ~10 Hz,
        /// damit CPU-Budget nicht gesprengt wird. Höher = mehr Updates,
        /// aber Stabilitäts-Hysteresen werden empfindlicher.
        static let minFrameInterval: CFTimeInterval = 0.1

        /// **Maximaler Zoom-Faktor** für User-Pinch. UX-Kompromiss:
        /// genug für kleinschriftige Speisekarten, unter der Schwelle
        /// wo digital-Zoom matschig wird.
        static let maxUserVisibleZoom: CGFloat = 5.0

        /// **Attention-Confidence-Threshold** — eine Region gilt erst
        /// dann als „capture-würdig", wenn sie stable ist UND ihren
        /// Score ≥ diesem Wert hat. Heute primär als Diagnose-Snapshot
        /// (kein automatischer Crop mehr — siehe FreeText-Stabilisierung).
        static let attentionConfidenceThreshold: Double = 0.6
    }
}
