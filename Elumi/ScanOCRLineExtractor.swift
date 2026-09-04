import UIKit
import Vision

struct ScanOCRLineExtractorDependencies {
    let sanitizedLine: (String) -> String
}

struct ScanOCRLineExtractor {
    let dependencies: ScanOCRLineExtractorDependencies

    func extractLineBoxes(
        from image: UIImage,
        sourceLanguage: StudyLanguage,
        includeGermanTargetLanguage: Bool,
        recognitionLevel: VNRequestTextRecognitionLevel,
        usesLanguageCorrection: Bool,
        customWordsLimit: Int
    ) -> [OCRLineBox] {
        guard let cgImage = image.cgImage else { return [] }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = usesLanguageCorrection
        request.recognitionLanguages = recognitionLanguages(
            for: sourceLanguage,
            includeGermanTargetLanguage: includeGermanTargetLanguage
        )
        request.minimumTextHeight = recognitionLevel == .fast ? 0.017 : 0.014
        if customWordsLimit > 0 {
            request.customWords = Array(DataStore.ocrCustomWords.prefix(customWordsLimit))
        }

        let handler = VNImageRequestHandler(
            cgImage: cgImage,
            orientation: CGImagePropertyOrientation(image.imageOrientation),
            options: [:]
        )

        do {
            try handler.perform([request])
        } catch {
            return []
        }

        let observations = request.results ?? []
        return observations.compactMap { observation -> OCRLineBox? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = dependencies.sanitizedLine(candidate.string)
            guard !text.isEmpty else { return nil }
            return OCRLineBox(text: text, boundingBox: observation.boundingBox)
        }
    }

    private func recognitionLanguages(
        for sourceLanguage: StudyLanguage,
        includeGermanTargetLanguage: Bool
    ) -> [String] {
        if includeGermanTargetLanguage {
            return [sourceLanguage.localeIdentifier, "de-DE"]
        }

        return [sourceLanguage.localeIdentifier]
    }
}
