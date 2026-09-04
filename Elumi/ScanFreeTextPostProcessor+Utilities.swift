import Foundation
import NaturalLanguage

extension ScanFreeTextPostProcessor {
    func deduplicatedReviewEntries(
        _ entries: [ScanFreeTextReviewEntry]
    ) -> [ScanFreeTextReviewEntry] {
        reviewEntries(from: dependencies.deduplicatePreviewPairs(makePreviewPairs(from: entries)))
    }

    func resolvedBucketConflicts(
        _ entries: [ScanFreeTextReviewEntry]
    ) -> [ScanFreeTextReviewEntry] {
        let contextSourceKeys = Set(
            entries
                .filter { $0.category == .recognizedText }
                .map { dependencies.normalizedLookupText($0.sourceText) }
                .filter { !$0.isEmpty }
        )
        let grammarSourceKeys = Set(
            entries
                .filter { $0.category == .grammar }
                .map { dependencies.normalizedLookupText($0.sourceText) }
                .filter { !$0.isEmpty }
        )

        return entries.filter { entry in
            let sourceKey = dependencies.normalizedLookupText(entry.sourceText)
            guard !sourceKey.isEmpty else { return false }

            switch entry.category {
            case .recognizedText:
                return true
            case .phrases:
                if grammarSourceKeys.contains(sourceKey) && !isLikelyPosterLearningPhrase(entry.sourceText) {
                    return false
                }

                if contextSourceKeys.contains(sourceKey) {
                    let wordCount = dependencies.normalizedWords(entry.sourceText).count
                    return isLikelyPosterLearningPhrase(entry.sourceText) || wordCount <= 4
                }

                return true
            case .verbs:
                return !contextSourceKeys.contains(sourceKey)
            case .grammar:
                return true
            }
        }
    }

    func reviewEntry(
        from previewPair: ImportPreviewPair,
        defaultCategory: ScanLearningCategory? = nil,
        defaultNote: String? = nil,
        defaultImportable: Bool? = nil
    ) -> ScanFreeTextReviewEntry {
        ScanFreeTextReviewEntry(
            id: previewPair.id,
            sourceText: previewPair.french,
            targetText: previewPair.german,
            cardType: previewPair.cardType,
            category: previewPair.learningCategory ?? defaultCategory ?? inferredCategory(for: previewPair),
            note: previewPair.note ?? defaultNote,
            isImportable: defaultImportable ?? previewPair.isImportable
        )
    }

    func inferredCategory(for previewPair: ImportPreviewPair) -> ScanLearningCategory {
        previewPair.cardType == .phrases ? .phrases : .verbs
    }

    func detectedVerbCandidates(
        in text: String,
        sourceLanguage: StudyLanguage
    ) -> [(surface: String, lemma: String?)] {
        guard let language = nlLanguage(for: sourceLanguage), !text.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = text
        tagger.setLanguage(language, range: text.startIndex..<text.endIndex)

        var candidates: [(surface: String, lemma: String?)] = []
        let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .joinNames]

        tagger.enumerateTags(
            in: text.startIndex..<text.endIndex,
            unit: .word,
            scheme: .lexicalClass,
            options: options
        ) { tag, tokenRange in
            guard tag == .verb else { return true }

            let surface = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let lemmaTag = tagger.tag(
                at: tokenRange.lowerBound,
                unit: .word,
                scheme: .lemma
            ).0
            let lemma = lemmaTag?.rawValue
            let normalizedSurface = dependencies.normalizedLookupText(surface)
            let normalizedLemma = dependencies.normalizedLookupText(lemma ?? "")

            guard !surface.isEmpty else { return true }
            guard !isLowValueFreeTextVerb(surface: normalizedSurface, lemma: normalizedLemma) else { return true }

            let cleanedLemma = lemma?.trimmingCharacters(in: .whitespacesAndNewlines)
            candidates.append((surface, cleanedLemma?.isEmpty == false ? cleanedLemma : nil))
            return true
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = dependencies.normalizedLookupText(candidate.lemma ?? candidate.surface)
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
    }

    func nlLanguage(for sourceLanguage: StudyLanguage) -> NLLanguage? {
        switch sourceLanguage {
        case .french:
            return .french
        case .english:
            return .english
        }
    }

    func isLowValueFreeTextVerb(surface: String, lemma: String) -> Bool {
        let candidate = !lemma.isEmpty ? lemma : surface
        let trivialVerbs: Set<String> = [
            "etre", "est", "es", "suis", "sommes", "etes", "sont",
            "avoir", "ai", "as", "a", "avons", "avez", "ont",
            "aller", "vais", "va", "allons", "allez", "vont",
            "faire", "fais", "fait",
            "et", "ou", "je", "tu", "il", "elle", "nous", "vous"
        ]
        return candidate.count <= 2 || trivialVerbs.contains(candidate)
    }

    func isSentenceLikeReviewEntry(_ entry: ScanFreeTextReviewEntry) -> Bool {
        let source = dependencies.extractDisplayTerm(entry.sourceText)
        let wordCount = dependencies.normalizedWords(source).count
        return wordCount >= 6 || source.contains("?") || source.contains("!") || source.contains(".")
    }

    func isSentenceLikePreviewPair(_ pair: ImportPreviewPair) -> Bool {
        let source = dependencies.extractDisplayTerm(pair.french)
        let wordCount = dependencies.normalizedWords(source).count
        return wordCount >= 6 || source.contains("?") || source.contains("!") || source.contains(".")
    }
}
