import CoreImage
import Foundation
import UIKit
import Vision

extension ScanOCRImagePreprocessor {
    func perspectiveCorrectedDocumentImage(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1
        request.minimumConfidence = 0.45
        request.minimumAspectRatio = 0.25
        request.quadratureTolerance = 25

        return autoreleasepool {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                return nil
            }

            guard let observation = request.results?.first else { return nil }
            let ciImage = CIImage(cgImage: cgImage)
            guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }

            let width = ciImage.extent.width
            let height = ciImage.extent.height

            func vector(_ point: CGPoint) -> CIVector {
                CIVector(x: point.x * width, y: point.y * height)
            }

            filter.setValue(ciImage, forKey: kCIInputImageKey)
            filter.setValue(vector(observation.topLeft), forKey: "inputTopLeft")
            filter.setValue(vector(observation.topRight), forKey: "inputTopRight")
            filter.setValue(vector(observation.bottomLeft), forKey: "inputBottomLeft")
            filter.setValue(vector(observation.bottomRight), forKey: "inputBottomRight")

            let context = CIContext(options: [.cacheIntermediates: false])
            guard let outputImage = filter.outputImage,
                  let correctedCGImage = context.createCGImage(outputImage, from: outputImage.extent) else {
                return nil
            }

            return UIImage(cgImage: correctedCGImage, scale: image.scale, orientation: .up)
        }
    }

    func trimmedScanMargins(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let insetX = width * 0.025
        let insetY = height * 0.025
        let cropRect = CGRect(
            x: insetX,
            y: insetY,
            width: width - insetX * 2,
            height: height - insetY * 2
        ).integral

        guard cropRect.width > 80,
              cropRect.height > 80,
              let croppedImage = cgImage.cropping(to: cropRect) else {
            return nil
        }

        return UIImage(cgImage: croppedImage, scale: image.scale, orientation: .up)
    }

    func autoCroppedDocumentImage(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 8
        request.minimumConfidence = 0.45
        request.minimumAspectRatio = 0.25
        request.quadratureTolerance = 25

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([request])
        } catch {
            return nil
        }

        guard let observations = request.results, !observations.isEmpty else {
            return nil
        }

        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let imageArea = imageWidth * imageHeight

        let bestRect = observations
            .map { observation -> CGRect in
                let box = observation.boundingBox
                return CGRect(
                    x: box.minX * imageWidth,
                    y: (1 - box.maxY) * imageHeight,
                    width: box.width * imageWidth,
                    height: box.height * imageHeight
                )
            }
            .filter { rect in
                let area = rect.width * rect.height
                return area >= imageArea * 0.22
            }
            .max { lhs, rhs in
                (lhs.width * lhs.height) < (rhs.width * rhs.height)
            }

        guard let bestRect else { return nil }

        let insetX = bestRect.width * 0.01
        let insetY = bestRect.height * 0.01
        let cropRect = bestRect
            .insetBy(dx: insetX, dy: insetY)
            .intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        guard cropRect.width > 40, cropRect.height > 40,
              let cropped = cgImage.cropping(to: cropRect.integral) else {
            return nil
        }

        return UIImage(cgImage: cropped, scale: image.scale, orientation: .up)
    }
}
