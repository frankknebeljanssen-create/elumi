// DownscaleImageHelper.swift
// **Meine Scans — Phase A (2026-05-20)** — Allgemeiner Bild-Downscale-
// Helper. Reine UIImage→UIImage-Skalierung, kein I/O, kein Logging.
//
// Die Logik ist bewusst aus `AIScanProvider+Payload.swift`
// (downscaledImageIfNeeded) PORTIERT statt wiederverwendet — die
// dortige Variante ist eine Extension auf der Scan-Pipeline-internen
// `AIScanProvider` und soll nicht in den Foundation-Layer eingezogen
// werden. Hier steht eine standalone, dependency-freie Kopie.

import UIKit

enum DownscaleImageHelper {
    /// Skaliert `image` so, dass die längere Kante höchstens `maxLongEdge`
    /// Punkte misst. Ist das Bild bereits kleiner (oder gleich), wird es
    /// unverändert zurückgegeben.
    static func downscaled(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage {
        let size = image.size
        let longEdge = max(size.width, size.height)
        guard longEdge > maxLongEdge, longEdge > 0 else { return image }

        let scale = maxLongEdge / longEdge
        let targetSize = CGSize(
            width: max(1, floor(size.width * scale)),
            height: max(1, floor(size.height * scale))
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
