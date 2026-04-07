import Foundation

extension ScanImportView {
    func repairedVocabularyPairs(
        _ pairs: [(String, String)],
        sourceLanguage: StudyLanguage
    ) -> [(String, String)] {
        scanVocabularyPairRepair.repairedVocabularyPairs(
            pairs,
            sourceLanguage: sourceLanguage
        )
    }

    func vocabularyPairScore(
        source: String,
        target: String,
        sourceLanguage: StudyLanguage
    ) -> Double {
        scanVocabularyPairRepair.vocabularyPairScore(
            source: source,
            target: target,
            sourceLanguage: sourceLanguage
        )
    }

    func bestVocabularyPairScore(
        source: String,
        target: String,
        preferredLanguage: StudyLanguage?
    ) -> Double {
        scanVocabularyPairRepair.bestVocabularyPairScore(
            source: source,
            target: target,
            preferredLanguage: preferredLanguage
        )
    }

    func vocabularyPairPenalty(for semanticScore: Double, pairTolerance: Double) -> Double {
        scanVocabularyPairRepair.vocabularyPairPenalty(
            for: semanticScore,
            pairTolerance: pairTolerance
        )
    }

    func correctedPairIfNeeded(
        source: String,
        target: String,
        sourceLanguage: StudyLanguage
    ) -> (String, String) {
        scanVocabularyPairRepair.correctedPairIfNeeded(
            source: source,
            target: target,
            sourceLanguage: sourceLanguage
        )
    }

    func bestLocalTranslationMatch(
        for source: String,
        sourceLanguage: StudyLanguage
    ) -> (sourceTerm: String, suggestions: [String], matchDistance: Double)? {
        scanVocabularyPairRepair.bestLocalTranslationMatch(
            for: source,
            sourceLanguage: sourceLanguage
        )
    }

    func shouldPreserveScannedSourceText(
        _ original: String,
        insteadOf canonical: String,
        sourceLanguage: StudyLanguage
    ) -> Bool {
        scanVocabularyPairRepair.shouldPreserveScannedSourceText(
            original,
            insteadOf: canonical,
            sourceLanguage: sourceLanguage
        )
    }

    func shouldPreserveScannedGermanTargetText(
        _ original: String,
        insteadOf canonical: String
    ) -> Bool {
        scanVocabularyPairRepair.shouldPreserveScannedGermanTargetText(
            original,
            insteadOf: canonical
        )
    }

    func canonicalizedSourceTermIfNeeded(
        _ source: String,
        sourceLanguage: StudyLanguage
    ) -> String {
        scanVocabularyPairRepair.canonicalizedSourceTermIfNeeded(
            source,
            sourceLanguage: sourceLanguage
        )
    }

    func isLikelyMarkerNoise(_ text: String) -> Bool {
        scanVocabularyPairRepair.isLikelyMarkerNoise(text)
    }

    func isLikelyOCRCorruptedWordToken(_ text: String) -> Bool {
        scanVocabularyPairRepair.isLikelyOCRCorruptedWordToken(text)
    }
}
