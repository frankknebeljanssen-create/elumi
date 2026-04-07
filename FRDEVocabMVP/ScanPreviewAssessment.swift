import Foundation

enum ImportPreviewAssessment {
    case complete
    case incomplete
    case suspicious
}

struct ScanPreviewAssessor {
    let extractedDisplayTerm: (String) -> String
    let bestVocabularyPairScore: (String, String, StudyLanguage) -> Double
    let sourceLanguageScore: (String, StudyLanguage) -> Double
    let germanScore: (String) -> Double
    let normalizedWords: (String) -> [String]

    func visiblePreviewPairs(
        from previewPairs: [ImportPreviewPair],
        sourceLanguage: StudyLanguage
    ) -> [ImportPreviewPair] {
        previewPairs
    }

    func assessment(
        for pair: ImportPreviewPair,
        sourceLanguage: StudyLanguage
    ) -> ImportPreviewAssessment {
        if !pair.isImportable {
            return .complete
        }

        if pair.isReviewed {
            return .complete
        }

        let source = extractedDisplayTerm(pair.french)
        let target = extractedDisplayTerm(pair.german)

        guard !source.isEmpty, !target.isEmpty else { return .incomplete }

        let pairScore = bestVocabularyPairScore(source, target, sourceLanguage)
        let sourceLanguageStrength = sourceLanguageScore(source, sourceLanguage)
        let sourceGermanStrength = germanScore(source)
        let targetGermanStrength = germanScore(target)
        let targetForeignStrength = sourceLanguageScore(target, sourceLanguage)
        let isSuspiciousShortTarget = normalizedWords(target).count == 1 && target.count <= 2
        let isSuspiciousAllCapsTarget =
            target.range(of: #"^[A-ZÄÖÜ]{2,4}$"#, options: .regularExpression) != nil

        if pairScore < 1.15 ||
            sourceLanguageStrength + 0.05 < sourceGermanStrength ||
            targetGermanStrength + 0.1 < targetForeignStrength ||
            isSuspiciousShortTarget ||
            isSuspiciousAllCapsTarget {
            return .suspicious
        }

        return .complete
    }
}
