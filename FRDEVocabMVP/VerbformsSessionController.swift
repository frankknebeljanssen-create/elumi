import Foundation
import SwiftUI

@MainActor
final class VerbformsSessionController: ObservableObject {
    @Published var mode: VerbformsMode = .multipleChoice
    @Published var selectedTenses: Set<VerbformsTense> = [.present]
    @Published var currentQuestion: VerbformsQuestion?
    @Published var currentOptions: [String] = []
    @Published var score: Int = 0
    @Published var totalAsked: Int = 0
    @Published var isActive: Bool = false
    @Published var isFinished: Bool = false

    // MC state
    @Published var selectedOption: String?
    @Published var isLocked: Bool = false

    // Typing state
    @Published var typedAnswer: String = ""
    @Published var typingResult: TypingResult?

    // Available tenses (loaded from DB)
    @Published var availableTenses: Set<VerbformsTense> = [.present]

    // Speed Round
    @Published var isSpeedRound: Bool = false
    @Published var speedRoundTimeRemaining: Int = 45
    var speedRoundTimer: Timer?

    var isSpeedRoundTimerExpired: Bool {
        isSpeedRound && speedRoundTimeRemaining <= 0
    }

    enum TypingResult {
        case correct
        case incorrect(correctAnswer: String)
    }

    private var questions: [VerbformsQuestion] = []
    private var allInflections: [VerbformsEngine.VerbInflections] = []
    private var questionIndex: Int = 0

    var progressText: String {
        if isSpeedRound {
            return "\(score) richtig"
        }
        return "\(min(questionIndex + 1, questions.count))/\(questions.count)"
    }

    var totalQuestions: Int { questions.count }

    func start(with questions: [VerbformsQuestion], inflections: [VerbformsEngine.VerbInflections], speedRound: Bool) {
        self.questions = questions
        self.allInflections = inflections
        self.questionIndex = 0
        self.score = 0
        self.totalAsked = 0
        self.isActive = true
        self.isFinished = false
        self.isSpeedRound = speedRound
        if speedRound {
            speedRoundTimeRemaining = 45
        }
        advanceToNext()
    }

    // Tracks which options were wrong for current question (orange highlight)
    @Published var wrongOptions: Set<String> = []

    func submitMC(_ option: String) {
        guard !isLocked, let question = currentQuestion else { return }
        selectedOption = option

        let isCorrect = option.lowercased() == question.correctAnswer.lowercased()

        if isSpeedRound {
            // Speed round: lock immediately, auto-advance
            isLocked = true
            if isCorrect { score += 1 }
            totalAsked += 1
            DispatchQueue.main.asyncAfter(deadline: .now() + (isCorrect ? 0.3 : 0.6)) { [weak self] in
                self?.nextSpeedRound()
            }
        } else if isCorrect {
            // Normal: correct → lock + show "Weiter"
            isLocked = true
            if wrongOptions.isEmpty { score += 1 } // nur Punkt wenn beim ersten Versuch richtig
            totalAsked += 1
        } else {
            // Normal: wrong → mark orange, keep trying
            wrongOptions.insert(option.lowercased())
            selectedOption = nil
        }
    }

    func submitTyping() {
        guard let question = currentQuestion else { return }
        let answer = typedAnswer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let correct = question.correctAnswer.lowercased()

        let isCorrect = answer == correct ||
            answer == stripPronoun(correct) ||
            stripPronoun(answer) == stripPronoun(correct)

        if isCorrect {
            score += 1
            typingResult = .correct
        } else {
            typingResult = .incorrect(correctAnswer: question.correctAnswer)
        }
        totalAsked += 1
        isLocked = true

        // Speed round: auto-advance
        if isSpeedRound {
            DispatchQueue.main.asyncAfter(deadline: .now() + (isCorrect ? 0.3 : 0.8)) { [weak self] in
                self?.nextSpeedRound()
            }
        }
    }

    func next() {
        questionIndex += 1
        if questionIndex >= questions.count {
            isFinished = true
            isActive = false
            currentQuestion = nil
            stopSpeedRoundTimer()
        } else {
            advanceToNext()
        }
    }

    private func nextSpeedRound() {
        guard isSpeedRound, !isSpeedRoundTimerExpired else { return }
        // Generate a new question on the fly for endless speed round
        if let newQ = VerbformsEngine.generateQuestions(from: allInflections, tenses: selectedTenses, count: 1).first {
            questions.append(newQ)
            questionIndex = questions.count - 1
            advanceToNext()
        }
    }

    func finishSpeedRound() {
        stopSpeedRoundTimer()
        isFinished = true
        isActive = false
        currentQuestion = nil
    }

    func startSpeedRoundTimer(feedbackPlayer: FeedbackPlayer) {
        speedRoundTimeRemaining = 45
        speedRoundTimer?.invalidate()
        speedRoundTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.speedRoundTimeRemaining -= 1
                if self.speedRoundTimeRemaining <= 5, self.speedRoundTimeRemaining > 0 {
                    feedbackPlayer.playToggle()
                }
                if self.speedRoundTimeRemaining <= 0 {
                    feedbackPlayer.playRoundClear()
                    self.finishSpeedRound()
                }
            }
        }
    }

    func stopSpeedRoundTimer() {
        speedRoundTimer?.invalidate()
        speedRoundTimer = nil
    }

    func reset() {
        stopSpeedRoundTimer()
        isActive = false
        isFinished = false
        isSpeedRound = false
        currentQuestion = nil
        questions = []
        allInflections = []
        questionIndex = 0
        score = 0
        totalAsked = 0
    }

    private func advanceToNext() {
        guard questionIndex < questions.count else {
            isFinished = true
            isActive = false
            return
        }
        currentQuestion = questions[questionIndex]
        currentOptions = questions[questionIndex].allOptions
        selectedOption = nil
        wrongOptions = []
        isLocked = false
        typedAnswer = ""
        typingResult = nil
    }

    private func stripPronoun(_ text: String) -> String {
        let prefixes = ["je ", "j'", "j\u{2019}", "tu ", "il ", "elle ", "nous ", "vous ", "ils ", "elles "]
        let lower = text.lowercased()
        for p in prefixes {
            if lower.hasPrefix(p) {
                return String(lower.dropFirst(p.count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return lower
    }
}
