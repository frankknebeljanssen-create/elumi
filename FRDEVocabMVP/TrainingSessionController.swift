import Foundation
import SwiftUI

@MainActor
final class TrainingSessionController: ObservableObject {
    @Published var selectedTrainingListID: UUID?
    @Published var selectedTrainingListIDs: Set<UUID> = [] {
        didSet {
            guard !isRestoringSelectedListIDs else { return }
            persistSelectedListIDs()
        }
    }
    @Published var direction: Direction = .frenchToGerman
    @Published var cardType: CardType = .words
    @Published var trainingMode: TrainingMode = .vocabulary {
        didSet {
            guard oldValue != trainingMode else { return }
            // Beim Modul-Wechsel die zuletzt aktiven Listen des neuen Moduls laden.
            // Damit bleibt die Auswahl pro Modul stabil (Vokabeln ≠ Verben ≠ Nomen …).
            loadSelectedListIDsForCurrentMode()
        }
    }
    /// Verhindert, dass `restore`-Flows das eigene Schreiben triggern.
    private var isRestoringSelectedListIDs = false
    @Published var isSpeedRound = false
    @Published var speedRoundScore = 0
    @Published var speedRoundTimeRemaining: Int = 60
    var speedRoundTimer: Timer?
    @Published var currentTrainingItem: VocabularyItem?
    @Published var hasStartedTraining = false
    @Published var failedAttemptsOnCurrentCard = 0
    @Published var remainingTrainingItems: [VocabularyItem] = []
    @Published var preparedTrainingItems: [VocabularyItem] = []
    @Published var isShowingSetup = true
    @Published var completedRound: Int = 0
    @Published var isShowingRoundComplete = false
    @Published var showingTrainingListPicker = false
    @Published var selectedDictionaryLearningLevel: DictionaryLearningLevel = .beginner
    @Published var loadedDictionaryTrainingList: VocabularyList?

    struct DictionaryTrainingLoadContext: Equatable {
        let learningLevel: DictionaryLearningLevel
        let language: StudyLanguage
    }

    var dictionaryTrainingLoadGeneration = 0
    var loadedDictionaryContext: DictionaryTrainingLoadContext?

    /// Combo-Tracking für ProgressService-Bonus. Reset bei Session-Start
    /// und bei falscher Antwort. Eine Session entspricht hier einer Runde
    /// (bis `isShowingRoundComplete`).
    var sessionCurrentCombo: Int = 0
    var sessionLongestCombo: Int = 0
    /// Anzahl richtig beantworteter Einheiten in der aktuellen Runde.
    var sessionCorrectCount: Int = 0
    /// Anzahl falscher Antworten in der aktuellen Runde.
    var sessionWrongCount: Int = 0
    /// Schutz vor doppelter Reward-Vergabe pro Session/Runde.
    var sessionRewardConsumed: Bool = false

    /// Zählt eine Antwort für Combo + Reward-Logik. Wird vom Training-
    /// Answer-Flow aufgerufen.
    func recordAnswer(correct: Bool) {
        if correct {
            sessionCurrentCombo += 1
            sessionLongestCombo = max(sessionLongestCombo, sessionCurrentCombo)
            sessionCorrectCount += 1
            GamificationFeedbackPresenter.shared.noteComboProgress(currentCombo: sessionCurrentCombo)
        } else {
            sessionCurrentCombo = 0
            sessionWrongCount += 1
        }
    }

    func resetGamificationCounters() {
        sessionCurrentCombo = 0
        sessionLongestCombo = 0
        sessionCorrectCount = 0
        sessionWrongCount = 0
        sessionRewardConsumed = false
    }

    func restoreSelectedListIDs() {
        loadSelectedListIDsForCurrentMode()
    }

    /// Lädt die persistierte Listenauswahl für den aktuellen `trainingMode`.
    /// Fällt zurück auf den Legacy-Key (`appTrainingSelectedListIDsKey`), falls für
    /// diesen Modus noch nie eine Auswahl gespeichert wurde — damit Bestandsnutzer
    /// ihren bisherigen Zustand behalten.
    private func loadSelectedListIDsForCurrentMode() {
        let modeKey = trainingSelectedListIDsKey(for: trainingMode.storageKey)
        let defaults = UserDefaults.standard
        let restoredIDs: Set<UUID>?
        if let data = defaults.data(forKey: modeKey),
           let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            restoredIDs = ids
        } else if let legacy = defaults.data(forKey: appTrainingSelectedListIDsKey),
                  let ids = try? JSONDecoder().decode(Set<UUID>.self, from: legacy),
                  !ids.isEmpty {
            restoredIDs = ids
        } else {
            restoredIDs = nil
        }
        guard let restored = restoredIDs else {
            // Kein persistierter Zustand → aktuelle Auswahl leeren, sonst bleibt
            // beim Modus-Wechsel fälschlich die vorherige Auswahl stehen.
            if !selectedTrainingListIDs.isEmpty {
                isRestoringSelectedListIDs = true
                selectedTrainingListIDs = []
                isRestoringSelectedListIDs = false
            }
            return
        }
        isRestoringSelectedListIDs = true
        selectedTrainingListIDs = restored
        isRestoringSelectedListIDs = false
    }

    private func persistSelectedListIDs() {
        guard let data = try? JSONEncoder().encode(selectedTrainingListIDs) else { return }
        let modeKey = trainingSelectedListIDsKey(for: trainingMode.storageKey)
        UserDefaults.standard.set(data, forKey: modeKey)
    }
}
