import CoreImage
import Foundation
import UIKit

extension ScanOCRImagePreprocessor {
    func softlyEnhancedOCRImage(from image: UIImage) -> UIImage? {
        autoreleasepool {
            guard let ciImage = CIImage(image: image),
                  let colorControls = CIFilter(name: "CIColorControls") else {
                return nil
            }

            colorControls.setValue(ciImage, forKey: kCIInputImageKey)
            colorControls.setValue(0.1, forKey: kCIInputBrightnessKey)
            colorControls.setValue(1.18, forKey: kCIInputContrastKey)
            colorControls.setValue(0.0, forKey: kCIInputSaturationKey)

            let context = CIContext(options: [.cacheIntermediates: false])
            guard let outputImage = colorControls.outputImage,
                  let cgImage = context.createCGImage(outputImage, from: outputImage.extent) else {
                return nil
            }

            return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
        }
    }

    func enhancedOCRImage(from image: UIImage) -> UIImage? {
        autoreleasepool {
            guard let ciImage = CIImage(image: image),
                  let colorControls = CIFilter(name: "CIColorControls"),
                  let unsharpMask = CIFilter(name: "CIUnsharpMask") else {
                return nil
            }

            colorControls.setValue(ciImage, forKey: kCIInputImageKey)
            colorControls.setValue(0.06, forKey: kCIInputBrightnessKey)
            colorControls.setValue(1.32, forKey: kCIInputContrastKey)
            colorControls.setValue(0.0, forKey: kCIInputSaturationKey)

            guard let colorAdjusted = colorControls.outputImage else { return nil }

            unsharpMask.setValue(colorAdjusted, forKey: kCIInputImageKey)
            unsharpMask.setValue(0.7, forKey: kCIInputRadiusKey)
            unsharpMask.setValue(0.55, forKey: kCIInputIntensityKey)

            let context = CIContext(options: [.cacheIntermediates: false])
            guard let sharpened = unsharpMask.outputImage,
                  let cgImage = context.createCGImage(sharpened, from: sharpened.extent) else {
                return nil
            }

            return UIImage(cgImage: cgImage, scale: image.scale, orientation: .up)
        }
    }
}
