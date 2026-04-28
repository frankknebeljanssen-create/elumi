import Foundation
import SwiftUI

@MainActor
final class QuizSessionController: ObservableObject {
    @Published var selectedListIDs: Set<UUID> = [] {
        didSet { scheduleListIDsPersistence() }
    }

    /// Debounce-Token für `persistSelectedListIDs`. Bei Multi-Select
    /// (mehrere Listen schnell antippen) kollabiert das 5–6 UserDefaults-
    /// Writes auf einen — verhindert kleine Tap-Laggs im Quiz-Setup.
    private var pendingListIDsPersist: DispatchWorkItem?
    @Published var questionCountOption: QuizQuestionCountOption = .five
    @Published var questions: [QuizQuestion] = []
    @Published var cachedMergedItems: [VocabularyItem] = []
    @Published var cachedCandidates: [QuizCandidate] = []
    @Published var currentQuestionIndex = 0
    @Published var answeredResults: [Bool] = []
    @Published var isShowingResult = false
    @Published var isPreparingQuiz = false
    @Published var preparedQuestions: [QuizQuestion] = []
    @Published var plannedQuestionCount = 0
    @Published var isLoadingRemainingQuestions = false

    var quizPreparationGeneration = 0
    var questionPrebuildGeneration = 0
    var quizMergeGeneration = 0
    var reusedCandidateIDs: Set<String> = []
    var lastMergedItemsRequest: MergeRequest?

    /// Combo-Tracking für den ProgressService-Bonus (alle 5 richtig in Folge).
    /// Reset bei `resetToSetup()` und bei falscher Antwort. Läuft zentral
    /// über `SessionStreak` (siehe `SessionStreak.swift`) — Matching/Fill-
    /// Blanks nutzen bereits „any mistake"-Flags, d. h. `firstAttempt` wird
    /// hier implizit über das aufrufende `completeCurrentQuestion` transportiert.
    // Nicht `private(set)` — der Antwort-Pfad lebt in
    // `QuizSessionController+Progress.swift` (eigene File-Extension) und
    // muss den Streak mutieren können.
    var streak = SessionStreak()
    var sessionCurrentCombo: Int { streak.current }
    var sessionLongestCombo: Int { streak.longest }
    /// Schutz gegen doppelte Reward-Vergabe — analog zum Flashcard-Flow.
    var sessionRewardConsumed: Bool = false

    /// **V1b (2026-04-28)** — `lernjahrMax` ist Teil des Equality-Vergleichs.
    /// `refreshMergedItemsIfNeeded` blockiert den Rebuild, wenn die letzte
    /// MergeRequest gleich der aktuellen ist; ohne `lernjahrMax`-Komponente
    /// würde ein Filter-Wechsel (gleiche Listen + gleiche Direction)
    /// fälschlich als „nichts zu tun" durchgewinkt → Stale Pool.
    struct MergeRequest: Equatable {
        let listIDs: [UUID]
        let direction: Direction
        let lernjahrMax: Int?
    }

    func restoreSelectedListIDs() {
        guard let data = UserDefaults.standard.data(forKey: appQuizSelectedListIDsKey),
              let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data),
              !ids.isEmpty else { return }
        selectedListIDs = ids
    }

    private func persistSelectedListIDs() {
        guard let data = try? JSONEncoder().encode(selectedListIDs) else { return }
        UserDefaults.standard.set(data, forKey: appQuizSelectedListIDsKey)
    }

    /// Debounce-Wrapper für `persistSelectedListIDs`. Der eigentliche
    /// UserDefaults-Write läuft auf einer Utility-Queue (150 ms
    /// debounce), ohne den Main-Thread zu blockieren. Snapshot der IDs
    /// wird **beim Planen** genommen, damit der spätere Task auf einem
    /// konsistenten Wert arbeitet.
    private func scheduleListIDsPersistence() {
        pendingListIDsPersist?.cancel()
        let snapshot = selectedListIDs
        let item = DispatchWorkItem {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            UserDefaults.standard.set(data, forKey: appQuizSelectedListIDsKey)
        }
        pendingListIDsPersist = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.15, execute: item)
    }
}
