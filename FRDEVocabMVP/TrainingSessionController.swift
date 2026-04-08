import Foundation
import SwiftUI

@MainActor
final class TrainingSessionController: ObservableObject {
    @Published var selectedTrainingListID: UUID?
    @Published var direction: Direction = .frenchToGerman
    @Published var cardType: CardType = .words
    @Published var trainingMode: TrainingMode = .vocabulary
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
}
