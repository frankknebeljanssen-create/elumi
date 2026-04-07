import Foundation
import CoreGraphics

extension ScanColumnPairMatcher {
    func shouldAppendContinuationRow(
        _ rightRow: OCRLineBox,
        to previousPair: PositionedLinePair,
        nextLeftRow: OCRLineBox?,
        averageHeight: CGFloat,
        preferredLanguage: StudyLanguage?
    ) -> Bool {
        let cleanedContinuation = dependencies.extractedDisplayTerm(rightRow.text)
        guard
            !cleanedContinuation.isEmpty,
            !dependencies.isLikelyHeadingOrMetaLine(cleanedContinuation)
        else {
            return false
        }

        let verticalGap = abs(previousPair.2 - rightRow.midY)
        guard verticalGap <= max(averageHeight * 1.35, 0.05) else { return false }

        let currentScore = dependencies.bestVocabularyPairScore(
            previousPair.0,
            previousPair.1,
            preferredLanguage
        )
        let combinedTarget = combinedContinuationTarget(previousPair.1, continuation: cleanedContinuation)
        let combinedScore = dependencies.bestVocabularyPairScore(
            previousPair.0,
            combinedTarget,
            preferredLanguage
        )
        let nextPairScore = nextLeftRow.map {
            dependencies.bestVocabularyPairScore($0.text, cleanedContinuation, preferredLanguage)
        } ?? -10

        let continuationBias = looksLikeTranslationContinuation(cleanedContinuation) ? -0.05 : 0.18
        if looksLikeTranslationContinuation(cleanedContinuation) &&
            nextPairScore < currentScore + 0.2 {
            return combinedScore >= currentScore - 0.05
        }

        return combinedScore >= currentScore + 0.04 && combinedScore >= nextPairScore + continuationBias
    }

    func combinedContinuationTarget(_ target: String, continuation: String) -> String {
        let trimmedTarget = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedContinuation = continuation.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedTarget.isEmpty else { return trimmedContinuation }
        guard !trimmedContinuation.isEmpty else { return trimmedTarget }

        let needsSeparator = !trimmedTarget.hasSuffix(",") &&
            !trimmedTarget.hasSuffix(";") &&
            !trimmedContinuation.hasPrefix(",") &&
            !trimmedContinuation.hasPrefix(";")

        return needsSeparator
            ? "\(trimmedTarget) \(trimmedContinuation)"
            : "\(trimmedTarget)\(trimmedContinuation)"
    }

    func looksLikeTranslationContinuation(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let normalized = dependencies.normalizedLookupText(trimmed)
        let continuationMarkers = [
            "oder", "auch", "etw", "etwas", "jdn", "jemanden", "jemandem", "sich",
            "bzw", "zum", "zur", "mit", "von", "für", "in", "bei", "auf"
        ]

        if continuationMarkers.contains(where: { normalized.hasPrefix($0) }) {
            return true
        }

        if let first = trimmed.first, first.isLowercase {
            return true
        }

        return trimmed.hasPrefix(",") || trimmed.hasPrefix(";") || trimmed.hasPrefix("(")
    }
}
