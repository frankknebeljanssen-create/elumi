import SwiftUI
import Foundation

enum QuizQuestionCountOption: Int, CaseIterable, Identifiable {
    case five = 5
    case ten = 10

    var id: Int { rawValue }

    var title: String {
        "\(rawValue) Fragen"
    }
}

struct QuizMultipleChoiceQuestion: Identifiable, Hashable {
    let id = UUID()
    let prompt: String
    let correctAnswer: String
    let options: [String]
    let category: String
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

    var id: UUID {
        switch self {
        case .multipleChoice(let question):
            return question.id
        case .matching(let question):
            return question.id
        }
    }

    var category: String {
        switch self {
        case .multipleChoice(let question):
            return question.category
        case .matching(let question):
            return question.category
        }
    }
}

