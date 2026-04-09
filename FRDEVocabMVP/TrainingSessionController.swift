import Foundation
import SwiftUI

@MainActor
final class TrainingSessionController: ObservableObject {
    @Published var selectedTrainingListID: UUID?
    @Published var selectedTrainingListIDs: Set<UUID> = [] {
        didSet { persistSelectedListIDs() }
    }
    @Published var direction: Direction = .frenchToGerman
    @Published var cardType: CardType = .words
    @Published var trainingMode: TrainingMode = .vocabulary
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
    @Published var showingTrainingListPicker = false
    @Published var selectedDictionaryLearningLevel: DictionaryLearningLevel = .beginner
    @Published var loadedDictionaryTrainingList: VocabularyList?

    struct DictionaryTrainingLoadContext: Equatable {
        let learningLevel: DictionaryLearningLevel
        let language: StudyLanguage
    }

    var dictionaryTrainingLoadGeneration = 0
    var loadedDictionaryContext: DictionaryTrainingLoadContext?

    func restoreSelectedListIDs() {
        guard let data = UserDefaults.standard.data(forKey: appTrainingSelectedListIDsKey),
              let ids = try? JSONDecoder().decode(Set<UUID>.self, from: data),
              !ids.isEmpty else { return }
        selectedTrainingListIDs = ids
    }

    private func persistSelectedListIDs() {
        guard let data = try? JSONEncoder().encode(selectedTrainingListIDs) else { return }
        UserDefaults.standard.set(data, forKey: appTrainingSelectedListIDsKey)
    }
}
