import SwiftUI
import Foundation

enum QuizQuestionCountOption: Int, CaseIterable, Identifiable {
    case five = 5
    case ten = 10
    case fifteen = 15
    case twenty = 20

    var id: Int { rawValue }

    var title: String {
        "\(rawValue)"
    }
}

struct QuizMultipleChoiceQuestion: Identifiable, Hashable {
    let id = UUID()
    let prompt: String
    let correctAnswer: String
    let options: [String]
    let category: String
}

struct QuizTypingQuestion: Identifiable, Hashable {
    let id = UUID()
    let prompt: String
    let correctAnswer: String
    let category: String
    let promptLanguageCode: String
    let answerLanguageCode: String
}

struct QuizMatchingPair: Identifiable, Hashable {
    let id = UUID()
    let prompt: String
    let answer: String
}

struct QuizMatchingQuestion: Identifiable, Hashable {
    let id = UUID()
    let pairs: [QuizMatchingPair]
    let shuffledAnswers: [QuizMatchingPair]
    let category: String
    let isWordCombo: Bool

    init(pairs: [QuizMatchingPair], shuffledAnswers: [QuizMatchingPair], category: String, isWordCombo: Bool = false) {
        self.pairs = pairs
        self.shuffledAnswers = shuffledAnswers
        self.category = category
        self.isWordCombo = isWordCombo
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

enum QuizQuestion: Identifiable, Hashable {
    case multipleChoice(QuizMultipleChoiceQuestion)
    case matching(QuizMatchingQuestion)
    case typing(QuizTypingQuestion)
    var id: UUID {
        switch self {
        case .multipleChoice(let q): return q.id
        case .matching(let q): return q.id
        case .typing(let q): return q.id
        }
    }

    var category: String {
        switch self {
        case .multipleChoice(let q): return q.category
        case .matching(let q): return q.category
        case .typing(let q): return q.category
        }
    }
}

