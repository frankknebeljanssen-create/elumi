import SwiftUI
import UIKit

extension ScanImportView {
    func scanStopWords(for language: StudyLanguage) -> Set<String> {
        switch language {
        case .french:
            return [
                "je", "tu", "il", "elle", "nous", "vous", "ils", "elles", "le", "la",
                "les", "un", "une", "des", "de", "du", "et", "ou", "à", "au", "aux",
                "dans", "sur", "avec", "pour", "mais", "ne", "pas", "que", "qui"
            ]
        case .english:
            return [
                "i", "you", "he", "she", "we", "they", "the", "a", "an", "and", "or",
                "to", "of", "in", "on", "at", "with", "for", "from", "is", "are"
            ]
        }
    }

    func deduplicatedPreviewPairs(_ pairs: [ImportPreviewPair]) -> [ImportPreviewPair] {
        ScanReviewMapper.deduplicatedPreviewPairs(
            pairs,
            normalizedPreviewPair: { normalizedPreviewPair($0) },
            normalizedLookupText: { normalizedLookupText($0) },
            extractedDisplayTerm: { extractedDisplayTerm(from: $0) }
        )
    }

    func parsePreviewPairs(from rawText: String) -> [ImportPreviewPair] {
        scanPreviewPairParser.parsePreviewPairs(
            from: rawText,
            sourceLanguage: scanSourceLanguage
        )
    }

    func splitLine(_ line: String) -> (String, String)? {
        scanPreviewPairParser.splitLine(line)
    }

    func filteredVocabularyBoxes(from boxes: [OCRLineBox]) -> [OCRLineBox] {
        scanOCRNoiseFilter.filteredVocabularyBoxes(from: boxes)
    }

    func makeColumnPairs(
        from boxes: [OCRLineBox],
        preferredLanguage: StudyLanguage? = nil
    ) -> [(String, String)] {
        scanColumnPairMatcher.makeColumnPairs(
            from: boxes,
            preferredLanguage: preferredLanguage
        )
    }

    func makePreviewPair(first: String, second: String) -> ImportPreviewPair? {
        scanPreviewPairParser.makePreviewPair(
            first: first,
            second: second,
            sourceLanguage: scanSourceLanguage
        )
    }

    func makeIncompletePreviewPair(from line: String) -> ImportPreviewPair? {
        scanPreviewPairParser.makeIncompletePreviewPair(
            from: line,
            sourceLanguage: scanSourceLanguage
        )
    }

    func inferredCardType(forSource source: String, target: String) -> CardType {
        let sourceWordCount = normalizedWords(in: source).count
        let targetWordCount = normalizedWords(in: target).count
        let maxWordCount = max(sourceWordCount, targetWordCount)

        if maxWordCount <= 1 {
            return .words
        }

        if maxWordCount >= 3 {
            return .phrases
        }

        let sentencePunctuationPattern = #"[.!?]"#
        if maxWordCount >= 2 &&
            (source.range(of: sentencePunctuationPattern, options: .regularExpression) != nil ||
             target.range(of: sentencePunctuationPattern, options: .regularExpression) != nil) {
            return .phrases
        }

        return .words
    }

    func isLikelyOrphanTargetPreviewLine(
        _ line: String,
        sourceLanguage: StudyLanguage? = nil
    ) -> Bool {
        let cleanedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanedLine.isEmpty else { return true }

        let germanStrength = germanScore(for: cleanedLine)
        let resolvedSourceLanguage = sourceLanguage ?? scanSourceLanguage
        let sourceStrength = sourceLanguageScore(for: cleanedLine, language: resolvedSourceLanguage)
        let wordCount = normalizedWords(in: cleanedLine).count
        let hasKnownGermanCoverage = germanDictionaryCoverageScore(for: cleanedLine) >= 0.45
        let isSingleWord = wordCount == 1

        return germanStrength > sourceStrength + 0.22 &&
            isSingleWord &&
            hasKnownGermanCoverage
    }

    func normalizedPreviewPair(_ pair: ImportPreviewPair) -> ImportPreviewPair {
        scanPreviewPairParser.normalizedPreviewPair(
            pair,
            sourceLanguage: scanSourceLanguage
        )
    }

    func canonicalizedGermanTargetIfNeeded(
        _ target: String,
        source: String,
        cardType: CardType,
        sourceLanguage: StudyLanguage
    ) -> String {
        scanImportNormalizer.canonicalizedGermanTargetIfNeeded(
            target,
            source: source,
            cardType: cardType,
            sourceLanguage: sourceLanguage
        )
    }

    func normalizedSourceImportTerm(_ text: String) -> String {
        normalizedSourceImportTerm(text, sourceLanguage: scanSourceLanguage)
    }

    func normalizedSourceImportTerm(
        _ text: String,
        sourceLanguage: StudyLanguage
    ) -> String {
        scanImportNormalizer.normalizedSourceImportTerm(
            text,
            sourceLanguage: sourceLanguage
        )
    }

    func normalizedEnglishVerbMarker(in text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let normalizedPrefix = trimmed
            .replacingOccurrences(of: #"(?i)^\s*\(\s*to\s*$"#, with: "(to)", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*to\)\s*$"#, with: "(to)", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*\(\s*to\)\s*"#, with: "(to) ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*to\)\s*"#, with: "(to) ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^\s*\(to\s*"#, with: "(to) ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let range = normalizedPrefix.range(
            of: #"(?i)^\s*\(?\s*to\)?\s*(.+)$"#,
            options: .regularExpression
        ) {
            let remainder = String(normalizedPrefix[range])
            let cleanedRemainder = remainder
                .replacingOccurrences(of: #"(?i)^\s*\(?\s*to\)?\s*"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"^\)+\s*"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !cleanedRemainder.isEmpty else { return "(to)" }
            return "(to) \(cleanedRemainder)"
        }

        return normalizedPrefix
    }

    func looksLikeEnglishInfinitiveMarker(_ text: String) -> Bool {
        text.range(
            of: #"(?i)^\s*(\(?\s*to\)?)(\s|$)"#,
            options: .regularExpression
        ) != nil
    }
}
