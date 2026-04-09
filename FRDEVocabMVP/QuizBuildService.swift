import Foundation

struct ImmediateQuizStartResult {
    let question: QuizQuestion
    let plannedQuestionCount: Int
}

struct QuizCandidate: Identifiable, Hashable {
    let id: String
    let prompt: String
    let answer: String
    let category: String
    let promptLanguageCode: String
    let answerLanguageCode: String
    let promptKey: String
    let answerKey: String
    let promptWordCount: Int
    let answerWordCount: Int
    let answerCharacterCount: Int
    let answerHasArticle: Bool
    let answerLeadingArticle: String?
    let answerInitial: String
    let isPhrase: Bool
}

enum QuizQuestionKind {
    case multipleChoice
    case matching
    case typing
}

struct QuizMergedItemsCacheKey: Hashable {
    let direction: Direction
    let listIDs: [UUID]
}

enum QuizMergedItemsCache {
    private static let lock = NSLock()
    private static var storage: [QuizMergedItemsCacheKey: [VocabularyItem]] = [:]

    static func mergedItems(from lists: [VocabularyList], direction: Direction) -> [VocabularyItem] {
        let key = QuizMergedItemsCacheKey(
            direction: direction,
            listIDs: lists.map(\.id).sorted { $0.uuidString < $1.uuidString }
        )

        lock.lock()
        if let cached = storage[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let mergedItems = QuizBuildService.makeMergedItems(from: lists, direction: direction)

        lock.lock()
        storage[key] = mergedItems
        lock.unlock()
        return mergedItems
    }

    static func clear() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}

enum QuizBuildService {
    static func clearMergedItemsCache() {
        QuizMergedItemsCache.clear()
    }

    static func mergedItems(from lists: [VocabularyList], direction: Direction) -> [VocabularyItem] {
        QuizMergedItemsCache.mergedItems(from: lists, direction: direction)
    }

    static func availableCandidateIDs(from items: [VocabularyItem], direction: Direction) -> Set<String> {
        Set(makeQuizCandidates(from: items, direction: direction).map(\.id))
    }

    static func consumedCandidateIDs(from questions: [QuizQuestion]) -> Set<String> {
        Set(questions.flatMap(consumedCandidateIDs))
    }

    static func consumedCandidateIDs(from question: QuizQuestion) -> Set<String> {
        switch question {
        case .multipleChoice(let multipleChoice):
            let promptKey = QuizBuildService.fastKey(multipleChoice.prompt)
            let answerKey = QuizBuildService.fastKey(multipleChoice.correctAnswer)
            let categoryKey = QuizBuildService.fastKey(multipleChoice.category)
            return [[promptKey, answerKey, categoryKey].joined(separator: "|")]
        case .matching(let matching):
            return Set(matching.pairs.map {
                [
                    QuizBuildService.fastKey($0.prompt),
                    QuizBuildService.fastKey($0.answer),
                    QuizBuildService.fastKey(matching.category)
                ].joined(separator: "|")
            })
        case .typing(let typing):
            let promptKey = QuizBuildService.fastKey(typing.prompt)
            let answerKey = QuizBuildService.fastKey(typing.correctAnswer)
            let categoryKey = QuizBuildService.fastKey(typing.category)
            return [[promptKey, answerKey, categoryKey].joined(separator: "|")]
        case .fillBlanks(let fill):
            return [[QuizBuildService.fastKey(fill.fullSentence), QuizBuildService.fastKey(fill.correctAnswer)].joined(separator: "|")]
        }
    }

    static func signature(_ question: QuizQuestion) -> String {
        switch question {
        case .multipleChoice(let multipleChoice):
            return [
                "mc",
                QuizBuildService.fastKey(multipleChoice.prompt),
                QuizBuildService.fastKey(multipleChoice.correctAnswer),
                QuizBuildService.fastKey(multipleChoice.category)
            ].joined(separator: "|")
        case .matching(let matching):
            let pairSignature = matching.pairs
                .map {
                    [
                        QuizBuildService.fastKey($0.prompt),
                        QuizBuildService.fastKey($0.answer)
                    ].joined(separator: "->")
                }
                .sorted()
                .joined(separator: "||")
            return [
                "match",
                QuizBuildService.fastKey(matching.category),
                pairSignature
            ].joined(separator: "|")
        case .typing(let typing):
            return [
                "typing",
                QuizBuildService.fastKey(typing.prompt),
                QuizBuildService.fastKey(typing.correctAnswer),
                QuizBuildService.fastKey(typing.category)
            ].joined(separator: "|")
        case .fillBlanks(let fill):
            return [
                "fill",
                QuizBuildService.fastKey(fill.fullSentence),
                QuizBuildService.fastKey(fill.correctAnswer)
            ].joined(separator: "|")
        }
    }

    static func fastKey(_ text: String) -> String {
        text.folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
