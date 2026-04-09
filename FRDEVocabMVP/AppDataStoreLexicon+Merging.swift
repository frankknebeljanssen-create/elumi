import Foundation

extension DataStoreLexiconSupport {
    static func mergeLexiconEntries(_ entries: [LexiconEntry]) -> [LexiconEntry] {
        var mergedByID: [String: LexiconEntry] = [:]

        for entry in entries {
            guard isMeaningfulLexiconEntry(entry) else { continue }

            if let existing = mergedByID[entry.id] {
                mergedByID[entry.id] = LexiconEntry(
                    id: existing.id,
                    sourceTerm: existing.sourceTerm,
                    targetTerm: existing.targetTerm.isEmpty ? entry.targetTerm : existing.targetTerm,
                    sourceLanguage: existing.sourceLanguage,
                    cardType: existing.cardType,
                    frenchGender: preferredLexiconGenderInfo(existing.frenchGender, entry.frenchGender),
                    germanGender: preferredLexiconGenderInfo(existing.germanGender, entry.germanGender),
                    isGermanNoun: existing.isGermanNoun || entry.isGermanNoun
                )
            } else {
                mergedByID[entry.id] = entry
            }
        }

        return propagateSharedLexiconGenderInfo(Array(mergedByID.values))
    }

    static func isMeaningfulLexiconEntry(_ entry: LexiconEntry) -> Bool {
        let source = cleanedQuizDisplayText(entry.sourceTerm)
        let target = cleanedQuizDisplayText(entry.targetTerm)

        guard !source.isEmpty else { return false }
        guard !target.isEmpty || entry.sourceLanguage == .french else { return false }

        if isLikelyOrdinalOrNumericNoise(source) && isLikelyOrdinalOrNumericNoise(target) {
            return false
        }

        let sourceDigits = digitsOnlyLexiconText(source)
        let targetDigits = digitsOnlyLexiconText(target)
        if !sourceDigits.isEmpty, sourceDigits == targetDigits,
           (isLikelyOrdinalOrNumericNoise(source) || isLikelyOrdinalOrNumericNoise(target)) {
            return false
        }

        if isLikelyPlaceNameLexiconEntry(entry) {
            return false
        }

        return true
    }

    static func isLikelyOrdinalOrNumericNoise(_ text: String) -> Bool {
        let normalized = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: String.CompareOptions.diacriticInsensitive, locale: Locale.current)
            .lowercased()

        guard !normalized.isEmpty else { return false }

        let ordinalPattern = #"^\d{1,4}(?:er|re|e|eme)?$"#
        let numericPattern = #"^\d{1,4}(?:[.,]\d+)?$"#

        return normalized.range(of: ordinalPattern, options: .regularExpression) != nil ||
            normalized.range(of: numericPattern, options: .regularExpression) != nil
    }

    static func digitsOnlyLexiconText(_ text: String) -> String {
        text.unicodeScalars
            .filter { CharacterSet.decimalDigits.contains($0) }
            .map(String.init)
            .joined()
    }

    static func propagateSharedLexiconGenderInfo(_ entries: [LexiconEntry]) -> [LexiconEntry] {
        var frenchGenderBySourceKey: [String: LexiconGenderInfo] = [:]
        var germanGenderByTargetKey: [String: LexiconGenderInfo] = [:]

        for entry in entries where entry.cardType == .words {
            let sourceKey = normalizedLookupText(strippingLeadingFrenchArticle(from: entry.sourceTerm))
            if !sourceKey.isEmpty {
                frenchGenderBySourceKey[sourceKey] = preferredLexiconGenderInfo(
                    frenchGenderBySourceKey[sourceKey],
                    entry.frenchGender
                )
            }

            let targetKey = normalizedLookupText(strippingLeadingGermanArticle(from: entry.targetTerm))
            if !targetKey.isEmpty {
                germanGenderByTargetKey[targetKey] = preferredLexiconGenderInfo(
                    germanGenderByTargetKey[targetKey],
                    entry.germanGender
                )
            }
        }

        return entries.map { entry in
            guard entry.cardType == .words else { return entry }

            let sourceKey = normalizedLookupText(strippingLeadingFrenchArticle(from: entry.sourceTerm))
            let targetKey = normalizedLookupText(strippingLeadingGermanArticle(from: entry.targetTerm))

            return LexiconEntry(
                id: entry.id,
                sourceTerm: entry.sourceTerm,
                targetTerm: entry.targetTerm,
                sourceLanguage: entry.sourceLanguage,
                cardType: entry.cardType,
                frenchGender: preferredLexiconGenderInfo(
                    entry.frenchGender,
                    frenchGenderBySourceKey[sourceKey]
                ),
                germanGender: preferredLexiconGenderInfo(
                    entry.germanGender,
                    germanGenderByTargetKey[targetKey]
                )
            )
        }
    }
}
