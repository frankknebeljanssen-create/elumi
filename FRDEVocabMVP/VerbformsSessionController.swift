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

    // MARK: - Matching (Drag & Drop) State

    /// Aktuelle Matching-Runde (MC-Modus); bei Typing-Modus bleibt nil.
    @Published var currentMatching: VerbformsMatchingRound?
    /// Personen-Targets, deren Form bereits korrekt zugeordnet wurde (grün + gelockt).
    @Published var matchedPersons: Set<VerbformsPerson> = []
    /// Pronomen-Karten, die schon platziert sind (optisch ausgegraut/verborgen).
    @Published var usedPronouns: Set<VerbformsPerson> = []
    /// Welche Form flasht gerade orange (falscher Drop, ~0.6s).
    @Published var wrongFlashTarget: VerbformsPerson?

    var isMatchingRoundComplete: Bool {
        currentMatching != nil && matchedPersons.count == 6
    }

    // MARK: - Runden-Tracking (analog zu „Verben trainieren")

    /// Zähler für den Runden-Durchlauf (1 = erste Runde, inkrementiert bei Wiederholung).
    @Published var completedRound: Int = 1
    /// Wird nach Abschluss aller Matching-Runden / Fragen gesetzt und triggert den
    /// Round-Complete-Screen (Wiederholungsangebot + „Fertig").
    @Published var isShowingRoundComplete: Bool = false

    // MARK: - Matching: Shuffled Display Order

    /// Reihenfolge der 6 Pronomen-Chips im Grid — pro Runde neu gemischt,
    /// damit die Position der Lösung nicht erkennbar ist.
    @Published var shuffledPronouns: [VerbformsPerson] = VerbformsPerson.allCases
    /// Reihenfolge der 6 Form-Karten im Grid — separat gemischt.
    @Published var shuffledForms: [VerbformsPerson] = VerbformsPerson.allCases
    /// Reihenfolge der Prompt-Sequenz (welche Person als nächstes „dran" ist).
    /// Pro Runde gemischt, damit nicht immer mit „1. Person Singular" begonnen wird.
    @Published var promptOrder: [VerbformsPerson] = VerbformsPerson.allCases

    /// Nächste noch ungematchte Person (für Prompt in der Fragekarte,
    /// z.B. „1. Person Plural"). Folgt der gemischten promptOrder-Reihenfolge.
    var nextTargetPerson: VerbformsPerson? {
        promptOrder.first(where: { !matchedPersons.contains($0) })
    }

    private var questions: [VerbformsQuestion] = []
    private var matchingRounds: [VerbformsMatchingRound] = []
    private var allInflections: [VerbformsEngine.VerbInflections] = []
    private var questionIndex: Int = 0

    var progressText: String {
        if isSpeedRound {
            return "\(score) richtig"
        }
        if mode == .multipleChoice {
            return "\(min(questionIndex + 1, matchingRounds.count))/\(matchingRounds.count)"
        }
        return "\(min(questionIndex + 1, questions.count))/\(questions.count)"
    }

    var totalQuestions: Int {
        mode == .multipleChoice ? matchingRounds.count : questions.count
    }

    func start(with questions: [VerbformsQuestion], inflections: [VerbformsEngine.VerbInflections], speedRound: Bool) {
        self.questions = questions
        self.matchingRounds = []
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

    /// Start für Drag-and-Drop-Matching-Modus.
    func startMatching(with rounds: [VerbformsMatchingRound], inflections: [VerbformsEngine.VerbInflections], speedRound: Bool) {
        self.questions = []
        self.matchingRounds = rounds
        self.allInflections = inflections
        self.questionIndex = 0
        self.score = 0
        self.totalAsked = 0
        self.isActive = true
        self.isFinished = false
        self.isSpeedRound = speedRound
        self.completedRound = 1
        self.isShowingRoundComplete = false
        if speedRound {
            speedRoundTimeRemaining = 45
        }
        advanceToNextMatching()
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
        if mode == .multipleChoice {
            nextMatching()
            return
        }
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

    // MARK: - Matching Flow

    /// User hat Pronomen-Karte auf Form-Target abgelegt. Prüft Paar.
    /// Gibt zurück, ob der Drop gepasst hat.
    @discardableResult
    func dropPronoun(_ pronoun: VerbformsPerson, onForm target: VerbformsPerson) -> Bool {
        guard !matchedPersons.contains(target) else { return false }
        guard !usedPronouns.contains(pronoun) else { return false }

        if pronoun == target {
            matchedPersons.insert(target)
            usedPronouns.insert(pronoun)
            totalAsked += 1
            if wrongFlashTarget == target { wrongFlashTarget = nil }
            // Score: 1 Punkt pro korrekt zugeordnetem Paar
            score += 1
            return true
        } else {
            totalAsked += 1
            wrongFlashTarget = target
            // Orange-Flash kurz anzeigen, dann zurücksetzen
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                guard let self, self.wrongFlashTarget == target else { return }
                self.wrongFlashTarget = nil
            }
            return false
        }
    }

    func nextMatching() {
        questionIndex += 1
        if questionIndex >= matchingRounds.count {
            // Im Speed-Round bleibt die alte Logik (Timer läuft, Session ends auf Timer=0).
            // Im Normalmodus: Runde abgeschlossen → Round-Complete-Screen,
            // User entscheidet ob er weiter macht (continueToNextRound) oder fertig ist.
            if isSpeedRound {
                isFinished = true
                isActive = false
                currentMatching = nil
                stopSpeedRoundTimer()
            } else {
                isShowingRoundComplete = true
                currentMatching = nil
            }
        } else {
            advanceToNextMatching()
        }
    }

    /// Startet die nächste Runde mit derselben Lemma-Basis — Matching-Rounds
    /// werden neu gemischt, Runden-Zähler erhöht. Analog zu
    /// `TrainingSessionController.continueNextRound()` im Verben-Modul.
    func continueToNextRound() {
        isShowingRoundComplete = false
        completedRound += 1
        questionIndex = 0
        matchingRounds.shuffle()
        advanceToNextMatching()
    }

    /// Beendet die Session manuell (z.B. wenn User nach dem Round-Complete-Screen
    /// „Fertig" wählt). Triggert den Result-Screen.
    func finishTraining() {
        isFinished = true
        isActive = false
        isShowingRoundComplete = false
        currentMatching = nil
        stopSpeedRoundTimer()
    }

    private func advanceToNextMatching() {
        guard questionIndex < matchingRounds.count else {
            isFinished = true
            isActive = false
            return
        }
        currentMatching = matchingRounds[questionIndex]
        matchedPersons = []
        usedPronouns = []
        wrongFlashTarget = nil
        isLocked = false
        // Pronomen-, Formen- und Prompt-Reihenfolge pro Runde UNABHÄNGIG mischen,
        // damit weder Position noch Reihenfolge die Lösung ablesbar machen.
        shuffledPronouns = VerbformsPerson.allCases.shuffled()
        shuffledForms = VerbformsPerson.allCases.shuffled()
        promptOrder = VerbformsPerson.allCases.shuffled()
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
        currentMatching = nil
        matchedPersons = []
        usedPronouns = []
        wrongFlashTarget = nil
        questions = []
        matchingRounds = []
        allInflections = []
        questionIndex = 0
        score = 0
        totalAsked = 0
        completedRound = 1
        isShowingRoundComplete = false
    }

    private func advanceToNext() {
        guard questionIndex < questions.count else {
            isFinished = true
            isActive = false
            return
        }
        let question = questions[questionIndex]
        currentQuestion = question

        // Optionen frisch aufbauen: 1× richtige Antwort + alle Distraktoren (dedupliziert),
        // dann shufflen. Safety-Check garantiert, dass die korrekte Antwort IMMER enthalten ist
        // (verhindert den Fall, dass in Runde 2 das Lösungswort fehlt).
        var optionSet: [String] = []
        var seen = Set<String>()
        for candidate in [question.correctAnswer] + question.distractors {
            let key = candidate.lowercased()
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            optionSet.append(candidate)
        }
        if !optionSet.contains(where: { $0.lowercased() == question.correctAnswer.lowercased() }) {
            optionSet.append(question.correctAnswer)
        }
        currentOptions = optionSet.shuffled()

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
