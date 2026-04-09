import SwiftUI
import Foundation

struct LexiconEntry: Identifiable {
    let id: String
    let sourceTerm: String
    let targetTerm: String
    let sourceLanguage: StudyLanguage
    let cardType: CardType
    let frenchGender: LexiconGenderInfo?
    let germanGender: LexiconGenderInfo?
    let isGermanNoun: Bool
    let sourceSortKey: String
    let targetSortKey: String

    init(
        id: String,
        sourceTerm: String,
        targetTerm: String,
        sourceLanguage: StudyLanguage,
        cardType: CardType,
        frenchGender: LexiconGenderInfo? = nil,
        germanGender: LexiconGenderInfo? = nil,
        isGermanNoun: Bool? = nil
    ) {
        self.id = id
        self.sourceTerm = sourceTerm
        self.targetTerm = targetTerm
        self.sourceLanguage = sourceLanguage
        self.cardType = cardType
        self.frenchGender = frenchGender
        self.germanGender = germanGender
        self.isGermanNoun = isGermanNoun ?? false
        self.sourceSortKey = sourceTerm.folding(options: .diacriticInsensitive, locale: .current).lowercased()
        self.targetSortKey = targetTerm.lowercased()
    }

    var letterKey: String {
        guard let first = sourceSortKey.first, first.isLetter else { return "#" }
        return String(first).uppercased()
    }
}

extension LexiconEntry: Hashable {
    static func == (lhs: LexiconEntry, rhs: LexiconEntry) -> Bool {
        lhs.id == rhs.id &&
        lhs.sourceTerm == rhs.sourceTerm &&
        lhs.targetTerm == rhs.targetTerm &&
        lhs.sourceLanguage == rhs.sourceLanguage &&
        lhs.cardType == rhs.cardType &&
        lhs.frenchGender == rhs.frenchGender &&
        lhs.germanGender == rhs.germanGender &&
        lhs.isGermanNoun == rhs.isGermanNoun
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(sourceTerm)
        hasher.combine(targetTerm)
    }
}

struct TranslationLookupEntry {
    let key: String
    let compactKey: String
    let suggestions: [String]
    let length: Int
    let compactLength: Int
    let firstCharacter: Character?
}

struct CuratedLexiconEntriesCacheKey: Hashable {
    let itemCount: Int
    let fingerprint: Int
}
