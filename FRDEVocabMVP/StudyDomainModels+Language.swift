import Foundation

struct FlashCard: Identifiable, Equatable {
    // `let id: UUID` statt `let id = UUID()` — symmetrisch zur Konvention
    // der Quiz-Domain-Models (`QuizMultipleChoiceQuestion` & Co.) nach dem
    // Codable-Refactor. Wenn `FlashCard` je persistiert oder kopiert wird,
    // bleibt die ID über Init-Grenzen hinweg stabil; der Default-Parameter
    // verhindert, dass Call-Sites angepasst werden müssen.
    let id: UUID
    let prompt: String
    let answer: String
    let promptLanguageCode: String
    let answerLanguageCode: String
    let category: String
    let wordClass: String?

    init(
        id: UUID = UUID(),
        prompt: String,
        answer: String,
        promptLanguageCode: String,
        answerLanguageCode: String,
        category: String,
        wordClass: String? = nil
    ) {
        self.id = id
        self.prompt = prompt
        self.answer = answer
        self.promptLanguageCode = promptLanguageCode
        self.answerLanguageCode = answerLanguageCode
        self.category = category
        self.wordClass = wordClass
    }

    /// Word class label localized for the given language code
    func wordClassLabel(for languageCode: String) -> String? {
        guard let wordClass, !wordClass.isEmpty else { return nil }
        let isFrench = languageCode.hasPrefix("fr")
        switch wordClass.lowercased() {
        case "noun":         return isFrench ? "nom"         : "Nomen"
        case "verb":         return isFrench ? "verbe"       : "Verb"
        case "adjective":    return isFrench ? "adjectif"    : "Adjektiv"
        case "adverb":       return isFrench ? "adverbe"     : "Adverb"
        case "pronoun":      return isFrench ? "pronom"      : "Pronomen"
        case "preposition":  return isFrench ? "préposition" : "Präposition"
        case "conjunction":  return isFrench ? "conjonction" : "Konjunktion"
        case "interjection": return isFrench ? "interjection": "Interjektion"
        case "phrase":       return isFrench ? "expression"  : "Wendung"
        default:             return wordClass
        }
    }
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
    case nouns = "Nomen"
    case articles = "Artikel"
    case verbs = "Verben"
    case verbforms = "Verbformen"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .vocabulary: return "book.fill"
        case .nouns: return "textformat"
        case .articles: return "textformat.abc.dottedunderline"
        case .verbs: return "arrow.triangle.branch"
        case .verbforms: return "text.line.first.and.arrowtriangle.forward"
        }
    }

    var iconLabel: String {
        switch self {
        case .vocabulary: return "📖"
        case .nouns: return "📝"
        case .articles: return "le, la"
        case .verbs: return "🔄"
        case .verbforms: return "✏️"
        }
    }

    /// Sprachunabhängiger, stabiler Identifier für Persistenz-Keys (UserDefaults).
    /// Separat vom anzeige-orientierten `rawValue`, damit UI-Umbenennungen keine
    /// Datenverluste auslösen.
    var storageKey: String {
        switch self {
        case .vocabulary: return "vocabulary"
        case .nouns:      return "nouns"
        case .articles:   return "articles"
        case .verbs:      return "verbs"
        case .verbforms:  return "verbforms"
        }
    }
}

/// Antwort-Eingabeform im **Nomen-Modus** — bereitet die Architektur
/// für zwei alternative Input-Layer vor, die auf denselben Trainings-
/// Kern aufsetzen:
///
///   • `.speech`  – User spricht das gesuchte Wort ein (aktueller Default,
///                  schon vollständig verdrahtet über `SpeechController`).
///   • `.choice`  – User wählt aus einem 8er-Grid von Vorschlägen (1 korrekt,
///                  7 Distraktoren). Die eigentliche Matching-Logik ist
///                  **noch nicht** implementiert — dieser Case existiert,
///                  damit die Setup-UI ihn schon jetzt anbieten kann und
///                  die spätere Erweiterung kein UI-Refactor mehr braucht.
///
/// Orthogonal zu `TrainingSessionController.isSpeedRound`: im Speed-Round-
/// Modus wird der Answer-Mode ignoriert — Speed Round hat seine eigene
/// Antwort-Mechanik (schnelle Abfolge, keine 8er-Auswahl).
enum NounAnswerMode: String, CaseIterable, Identifiable, Hashable, Codable {
    case speech = "Spracheingabe"
    case choice = "Wortauswahl"

    var id: String { rawValue }
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
