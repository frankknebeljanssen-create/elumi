import Foundation
import UIKit

/// **Per-Image-State** für den Galerie-Mehrbild-Review (User-Spec
/// 2026-04-23 nachmittags).
///
/// Vorher lief der Galerie-Mehrbild-Pfad mit globalen Variablen
/// (`optimizedVariant`, `optimizationApplied`) — Optimierung von
/// Bild 1 hätte fälschlich Bild 2/3/4 beeinflusst, weil kein
/// per-image Zustand existierte.
///
/// Jedes `GalleryReviewItem` trägt seinen eigenen kompletten
/// Optimierungs- und Display-Zustand. Die finale Pipeline-Übergabe
/// nutzt pro Item das `finalImage` — entweder das Original oder
/// die Optimierung, je nach `optimizationApplied`.
///
/// **Reihenfolge**: `sourceIndex` erhält die Reihenfolge aus der
/// Picker-Auswahl, damit der User die Bilder in genau der Reihenfolge
/// reviewt, in der er sie ausgewählt hat.
struct GalleryReviewItem: Identifiable {
    let id: UUID
    let sourceIndex: Int
    let originalImage: UIImage

    // MARK: Per-Image Optimization-State

    /// Quality-Report aus der lokalen `ImageQualityAnalyzer`-Pipeline.
    /// `nil` solange der Async-Analyse-Task noch läuft.
    var qualityReport: ImageQualityAnalyzer.Report?
    /// Optimierte Variante, falls der User „Auto optimieren" gedrückt hat.
    var optimizedVariant: UIImage?
    /// User-Entscheidung: Optimized-Variante als Final markiert?
    /// Default `false` — das Original ist immer der sichere Fallback.
    var optimizationApplied: Bool
    /// Empfohlenes Profile aus dem Quality-Report (für „Auto optimieren"-CTA).
    var recommendedProfile: ImageQualityAnalyzer.EnhancementProfile?
    /// Während die Async-Optimierung läuft — UI zeigt Spinner statt Button.
    var isOptimizing: Bool

    init(
        id: UUID = UUID(),
        sourceIndex: Int,
        originalImage: UIImage,
        qualityReport: ImageQualityAnalyzer.Report? = nil,
        optimizedVariant: UIImage? = nil,
        optimizationApplied: Bool = false,
        recommendedProfile: ImageQualityAnalyzer.EnhancementProfile? = nil,
        isOptimizing: Bool = false
    ) {
        self.id = id
        self.sourceIndex = sourceIndex
        self.originalImage = originalImage
        self.qualityReport = qualityReport
        self.optimizedVariant = optimizedVariant
        self.optimizationApplied = optimizationApplied
        self.recommendedProfile = recommendedProfile
        self.isOptimizing = isOptimizing
    }

    // MARK: Derived

    /// Aktuell anzuzeigendes Bild (Big-Preview + Filmstrip).
    var displayImage: UIImage {
        if optimizationApplied, let opt = optimizedVariant {
            return opt
        }
        return originalImage
    }

    /// Bild, das in die Analyse-Pipeline geht. Identisch zu `displayImage`,
    /// als semantisch eigene Property für Klarheit am Submit-Punkt.
    var finalImage: UIImage { displayImage }
}
