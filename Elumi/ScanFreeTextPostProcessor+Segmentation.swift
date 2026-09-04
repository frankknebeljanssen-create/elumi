import Foundation

extension ScanFreeTextPostProcessor {
    func freeTextMeaningUnits(from lines: [String]) -> [String] {
        var units: [String] = []

        for rawLine in lines {
            let line = dependencies.extractDisplayTerm(rawLine)
            guard !line.isEmpty else { continue }

            if isLikelyFreeTextScheduleOrMetaLine(line) {
                units.append(line)
                continue
            }

            if let last = units.last,
               shouldMergeFreeTextLine(previous: last, current: line) {
                units[units.count - 1] = dependencies.extractDisplayTerm(last + " " + line)
            } else {
                units.append(line)
            }
        }

        return units
    }

    func shouldMergeFreeTextLine(previous: String, current: String) -> Bool {
        let previousWords = dependencies.normalizedWords(previous)
        let currentWords = dependencies.normalizedWords(current)
        guard !previousWords.isEmpty, !currentWords.isEmpty else { return false }

        if previous.hasSuffix(".") || previous.hasSuffix("!") || previous.hasSuffix("?") {
            return false
        }

        let previousLast = previousWords.last ?? ""
        let mergeTailWords: Set<String> = [
            "de", "du", "des", "d", "dans", "pour", "par", "avec", "sans",
            "en", "sur", "sous", "au", "aux", "a", "la", "le", "les", "un", "une"
        ]

        if mergeTailWords.contains(previousLast) {
            return true
        }

        if previousWords.count <= 3 || currentWords.count <= 2 {
            return true
        }

        let currentStartsLowercase = current.first.map { String($0) == String($0).lowercased() } ?? false
        return currentStartsLowercase
    }

    func isLikelyFreeTextScheduleOrMetaLine(_ text: String) -> Bool {
        let trimmedOriginal = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return true }

        if dependencies.isLikelyHeadingOrMetaLine(cleaned) {
            return true
        }

        let schedulePatterns = [
            #"\b(lundi|mardi|mercredi|jeudi|vendredi|samedi|dimanche)\b"#,
            #"\b\d{1,2}h(\d{2})?\b"#,
            #"\b\d{1,2}:\d{2}\b"#,
            #"\b(offices?|messe|horaires?|semaine|dominical|dominicaux)\b"#
        ]

        if schedulePatterns.contains(where: { cleaned.range(of: $0, options: .regularExpression) != nil }) {
            return true
        }

        let words = dependencies.normalizedWords(cleaned)
        let letterScalars = trimmedOriginal.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let uppercaseScalars = trimmedOriginal.unicodeScalars.filter { CharacterSet.uppercaseLetters.contains($0) }
        if !letterScalars.isEmpty,
           words.count <= 4,
           uppercaseScalars.count >= max(3, Int(Double(letterScalars.count) * 0.7)) {
            return true
        }

        let digitCount = cleaned.filter(\.isNumber).count
        if digitCount >= 3 && words.count <= 8 {
            return true
        }

        return false
    }

    func isMeaningfulContextSentence(_ text: String) -> Bool {
        let cleaned = dependencies.extractDisplayTerm(text)
        let wordCount = dependencies.normalizedWords(cleaned).count

        guard wordCount >= 2 else { return false }
        guard !isLikelyFreeTextScheduleOrMetaLine(cleaned) else { return false }

        if isLikelyPosterLearningPhrase(cleaned), wordCount <= 4 {
            return false
        }

        return wordCount >= 4 || cleaned.contains("?") || cleaned.contains("!") || cleaned.contains(".")
    }

    func isLikelyPosterLearningPhrase(_ text: String) -> Bool {
        let cleaned = text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let keywords = [
            "bienvenue",
            "merci de",
            "pas de",
            "silence",
            "priere",
            "recueillement",
            "interdit",
            "defense",
            "attention"
        ]

        return keywords.contains { cleaned.contains($0) }
    }
}
