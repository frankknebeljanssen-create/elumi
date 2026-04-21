import SwiftUI
import Foundation

enum QuizQuestionCountOption: Int, CaseIterable, Identifiable {
    case five = 5
    case ten = 10
    case fifteen = 15
    case twenty = 20
    case twentyFive = 25
    case thirty = 30

    var id: Int { rawValue }

    var title: String {
        "\(rawValue)"
    }
}

// Codable-Konformität: Alle vier Frage-Typen + `QuizQuestion` können seit
// Swift 5.5 automatisch Codable sein (auch das Enum mit Associated Values),
// weil alle Felder Codable-Primitive sind. Damit lassen sich generierte
// Quizfragen für Session-Resume 1:1 auf die Platte schreiben.

struct QuizMultipleChoiceQuestion: Identifiable, Hashable, Codable {
    let id: UUID
    let prompt: String
    let correctAnswer: String
    let options: [String]
    let category: String

    init(id: UUID = UUID(), prompt: String, correctAnswer: String, options: [String], category: String) {
        self.id = id
        self.prompt = prompt
        self.correctAnswer = correctAnswer
        self.options = options
        self.category = category
    }
}

struct QuizTypingQuestion: Identifiable, Hashable, Codable {
    let id: UUID
    let prompt: String
    let correctAnswer: String
    let category: String
    let promptLanguageCode: String
    let answerLanguageCode: String

    init(
        id: UUID = UUID(),
        prompt: String,
        correctAnswer: String,
        category: String,
        promptLanguageCode: String,
        answerLanguageCode: String
    ) {
        self.id = id
        self.prompt = prompt
        self.correctAnswer = correctAnswer
        self.category = category
        self.promptLanguageCode = promptLanguageCode
        self.answerLanguageCode = answerLanguageCode
    }
}

struct QuizMatchingPair: Identifiable, Hashable, Codable {
    let id: UUID
    let prompt: String
    let answer: String

    init(id: UUID = UUID(), prompt: String, answer: String) {
        self.id = id
        self.prompt = prompt
        self.answer = answer
    }
}

struct QuizMatchingQuestion: Identifiable, Hashable, Codable {
    let id: UUID
    let pairs: [QuizMatchingPair]
    let shuffledAnswers: [QuizMatchingPair]
    let category: String
    let isWordCombo: Bool

    init(
        id: UUID = UUID(),
        pairs: [QuizMatchingPair],
        shuffledAnswers: [QuizMatchingPair],
        category: String,
        isWordCombo: Bool = false
    ) {
        self.id = id
        self.pairs = pairs
        self.shuffledAnswers = shuffledAnswers
        self.category = category
        self.isWordCombo = isWordCombo
    }
}

struct QuizFillBlanksQuestion: Identifiable, Hashable, Codable {
    let id: UUID
    let sentenceWithBlank: String
    let fullSentence: String
    let translationHint: String
    let correctAnswer: String
    let options: [String]
    let category: String

    init(
        id: UUID = UUID(),
        sentenceWithBlank: String,
        fullSentence: String,
        translationHint: String,
        correctAnswer: String,
        options: [String],
        category: String
    ) {
        self.id = id
        self.sentenceWithBlank = sentenceWithBlank
        self.fullSentence = fullSentence
        self.translationHint = translationHint
        self.correctAnswer = correctAnswer
        self.options = options
        self.category = category
    }
}

struct QuizPromptFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

struct QuizAnswerFramePreferenceKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] = [:]

    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

enum QuizQuestion: Identifiable, Hashable, Codable {
    case multipleChoice(QuizMultipleChoiceQuestion)
    case matching(QuizMatchingQuestion)
    case typing(QuizTypingQuestion)
    case fillBlanks(QuizFillBlanksQuestion)

    var id: UUID {
        switch self {
        case .multipleChoice(let q): return q.id
        case .matching(let q): return q.id
        case .typing(let q): return q.id
        case .fillBlanks(let q): return q.id
        }
    }

    var category: String {
        switch self {
        case .multipleChoice(let q): return q.category
        case .matching(let q): return q.category
        case .typing(let q): return q.category
        case .fillBlanks(let q): return q.category
        }
    }
}

