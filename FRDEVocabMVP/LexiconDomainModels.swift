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
    /// DB entry_id (nur für supplement-Einträge aus der SQLite-DB; `nil` für curated/custom).
    /// Wird für Beispiel-Lookups via `SupplementalFreeDictLexicon.examples(forEntryID:)` verwendet.
    let entryID: Int?
    /// DB word_class String („noun", „verb", „adjective", „phrase", „pronoun", …)
    /// Direkt aus dem Master-Export. Wird vom zentralen `FrenchLemmaFormatter`
    /// als bevorzugte Wortart-Quelle verwendet, wenn vorhanden.
    let wordClass: String?

    init(
        id: String,
        sourceTerm: String,
        targetTerm: String,
        sourceLanguage: StudyLanguage,
        cardType: CardType,
        frenchGender: LexiconGenderInfo? = nil,
        germanGender: LexiconGenderInfo? = nil,
        isGermanNoun: Bool? = nil,
        entryID: Int? = nil,
        wordClass: String? = nil
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
        // Fallback: entry_id aus der id-Komponente extrahieren
        // (Format: language|cardType|srcKey|tgtKey|entryId)
        if let explicit = entryID {
            self.entryID = explicit
        } else {
            let parts = id.split(separator: "|")
            if let last = parts.last, let parsed = Int(last) {
                self.entryID = parsed
            } else {
                self.entryID = nil
            }
        }
        self.wordClass = wordClass?.isEmpty == true ? nil : wordClass
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
