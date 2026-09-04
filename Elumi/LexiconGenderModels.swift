import Foundation

enum LexiconNounGender: String, Hashable {
    case masculine = "m."
    case feminine = "f."
    case neuter = "n."
    case plural = "pl."
}

struct LexiconGenderInfo: Hashable {
    let gender: LexiconNounGender
    let article: String?
    let isHeuristic: Bool

    var compactLabel: String {
        gender.rawValue
    }

    var detailLabel: String {
        if let article, !article.isEmpty {
            return "\(gender.rawValue) · \(article)"
        }
        return gender.rawValue
    }
}

struct OfflineFrenchGermanLexiconRecord: Hashable {
    let sourceTerm: String
    let targetTerm: String
    let cardType: CardType
    let sourceLookupKey: String
    let sourceCompactKey: String
    let sourceLookupVariants: [String]
    let sourceCompactVariants: [String]
    let targetLookupKey: String
    let targetCompactKey: String
    let isGermanNoun: Bool
    let isFrenchQuestion: Bool
    let sourceGender: LexiconNounGender?
    let targetGender: LexiconNounGender?
    let sourceArticle: String?
    let targetLeadingArticle: String?

    var normalizedSourceKey: String {
        sourceLookupKey
    }

    var normalizedTargetKey: String {
        targetLookupKey
    }
}
