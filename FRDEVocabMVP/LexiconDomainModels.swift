import SwiftUI
import Foundation

struct LexiconEntry: Identifiable, Hashable {
    let id: String
    let sourceTerm: String
    let targetTerm: String
    let sourceLanguage: StudyLanguage
    let cardType: CardType
    let frenchGender: LexiconGenderInfo?
    let germanGender: LexiconGenderInfo?

    var letterKey: String {
        let folded = sourceTerm
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
            .uppercased()

        guard let first = folded.first, first.isLetter else { return "#" }
        return String(first)
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
