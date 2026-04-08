import Foundation

struct FlashCard: Identifiable, Equatable {
    let id = UUID()
    let prompt: String
    let answer: String
    let promptLanguageCode: String
    let answerLanguageCode: String
    let category: String
}

enum StudyLanguage: String, CaseIterable, Identifiable, Codable {
    case french = "Französisch"
    case english = "Englisch"

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .french:
            return "fr-FR"
        case .english:
            return "en-US"
        }
    }

    var shortCode: String {
        switch self {
        case .french:
            return "FR"
        case .english:
            return "EN"
        }
    }

    var defaultDirectionToGerman: Direction {
        switch self {
        case .french:
            return .frenchToGerman
        case .english:
            return .englishToGerman
        }
    }
}

enum Direction: String, CaseIterable, Identifiable, Codable {
    case frenchToGerman = "Französisch → Deutsch"
    case germanToFrench = "Deutsch → Französisch"
    case englishToGerman = "Englisch → Deutsch"
    case germanToEnglish = "Deutsch → Englisch"

    var id: String { rawValue }

    static var frenchOnlyCases: [Direction] {
        [.frenchToGerman, .germanToFrench]
    }

    var sanitizedForFrenchOnly: Direction {
        switch self {
        case .frenchToGerman, .germanToFrench:
            return self
        case .englishToGerman:
            return .frenchToGerman
        case .germanToEnglish:
            return .germanToFrench
        }
    }

    var sourceLanguage: StudyLanguage {
        switch self {
        case .frenchToGerman, .germanToFrench:
            return .french
        case .englishToGerman, .germanToEnglish:
            return .english
        }
    }

    var pairFlag: String {
        switch self {
        case .frenchToGerman:
            return "🇫🇷 -> 🇩🇪"
        case .germanToFrench:
            return "🇩🇪 -> 🇫🇷"
        case .englishToGerman:
            return "🇬🇧 -> 🇩🇪"
        case .germanToEnglish:
            return "🇩🇪 -> 🇬🇧"
        }
    }

    var compactLabel: String {
        switch self {
        case .frenchToGerman:
            return "F → D"
        case .germanToFrench:
            return "D → F"
        case .englishToGerman:
            return "E → D"
        case .germanToEnglish:
            return "D → E"
        }
    }

    var sourceFlag: String {
        switch self {
        case .frenchToGerman:
            return "🇫🇷"
        case .germanToFrench:
            return "🇩🇪"
        case .englishToGerman:
            return "🇬🇧"
        case .germanToEnglish:
            return "🇩🇪"
        }
    }

    var targetFlag: String {
        switch self {
        case .frenchToGerman:
            return "🇩🇪"
        case .germanToFrench:
            return "🇫🇷"
        case .englishToGerman:
            return "🇩🇪"
        case .germanToEnglish:
            return "🇬🇧"
        }
    }

    var homeLanguageFlag: String {
        switch sourceLanguage {
        case .french:
            return "🇫🇷"
        case .english:
            return "🇬🇧"
        }
    }

    var recognitionLocaleIdentifier: String {
        switch self {
        case .frenchToGerman, .englishToGerman:
            return "de-DE"
        case .germanToFrench:
            return "fr-FR"
        case .germanToEnglish:
            return "en-US"
        }
    }

    static func directions(for language: StudyLanguage) -> [Direction] {
        switch language {
        case .french:
            return [.frenchToGerman, .germanToFrench]
        case .english:
            return [.englishToGerman, .germanToEnglish]
        }
    }
}

enum TrainingMode: String, CaseIterable, Identifiable, Hashable {
    case vocabulary = "Vokabeln"
    case articles = "Artikel"
    case verbs = "Verben"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .vocabulary: return "book.fill"
        case .articles: return "textformat"
        case .verbs: return "arrow.triangle.branch"
        }
    }

    var iconLabel: String {
        switch self {
        case .vocabulary: return "📖"
        case .articles: return "le, la"
        case .verbs: return "🔄"
        }
    }
}

enum CardType: String, CaseIterable, Identifiable, Codable {
    case words = "Wörter"
    case phrases = "Phrasen"

    var id: String { rawValue }

    var categoryName: String {
        switch self {
        case .words:
            return "Wort"
        case .phrases:
            return "Phrase"
        }
    }
}

enum FlashcardContentSelection: String, CaseIterable, Identifiable {
    case words = "Wörter"
    case phrases = "Phrasen"
    case mixed = "Wörter + Phrasen"

    var id: String { rawValue }

    var preferredCardType: CardType? {
        switch self {
        case .words:
            return .words
        case .phrases:
            return .phrases
        case .mixed:
            return nil
        }
    }
}

enum VocabularyLevel: String, CaseIterable, Identifiable, Codable {
    case beginner = "Anfänger"
    case intermediate = "Mittel"
    case advanced = "Fortgeschritten"

    var id: String { rawValue }

    var rank: Int {
        switch self {
        case .beginner:
            return 1
        case .intermediate:
            return 2
        case .advanced:
            return 3
        }
    }
}

enum DictionaryLearningLevel: String, CaseIterable, Identifiable {
    case beginner = "Anfänger"
    case intermediate = "Mittel"
    case advanced = "Fortgeschritten"
    case all = "Alle"

    var id: String { rawValue }

    var title: String { rawValue }

    func matches(_ level: VocabularyLevel) -> Bool {
        switch self {
        case .beginner:
            return level == .beginner
        case .intermediate:
            return level == .intermediate
        case .advanced:
            return level == .advanced
        case .all:
            return true
        }
    }
}

enum TrainingSource: String, CaseIterable, Identifiable {
    case curriculum = "Standard"
    case customList = "Eigene Liste"

    var id: String { rawValue }
}

enum ListCollectionGroup: String, CaseIterable, Codable, Identifiable {
    case books = "Bücher"
    case ownVocabulary = "Eigene Vokabeln"
    case standardLevel = "Wortschatz nach Niveau"
    case standardTopic = "Wortschatz nach Thema"
    case other = "Sonstiges"

    var id: String { rawValue }

    var sortOrder: Int {
        switch self {
        case .books:
            return 0
        case .ownVocabulary:
            return 1
        case .standardLevel:
            return 2
        case .standardTopic:
            return 3
        case .other:
            return 4
        }
    }
}

enum ListCollectionPreset: String, CaseIterable, Codable, Identifiable {
    case schoolbook = "Schulbuch"
    case grammarNotebook = "Grammatikheft"
    case vocabularyNotebook = "Vokabelheft"
    case worksheets = "Arbeitsblätter"
    case standardLevel = "Niveau"
    case standardTopic = "Thema"
    case other = "Sonstiges"

    var id: String { rawValue }

    var group: ListCollectionGroup {
        switch self {
        case .schoolbook, .grammarNotebook:
            return .books
        case .vocabularyNotebook, .worksheets:
            return .ownVocabulary
        case .standardLevel:
            return .standardLevel
        case .standardTopic:
            return .standardTopic
        case .other:
            return .other
        }
    }

    var displayPath: String {
        "\(group.rawValue) · \(rawValue)"
    }

    var sortOrder: Int {
        switch self {
        case .schoolbook:
            return 0
        case .grammarNotebook:
            return 1
        case .vocabularyNotebook:
            return 2
        case .worksheets:
            return 3
        case .standardLevel:
            return 4
        case .standardTopic:
            return 5
        case .other:
            return 6
        }
    }
}
