import Foundation
import SwiftUI

@MainActor
final class FlashcardsSetupController: ObservableObject {
    @Published var selectedSetupDirection: Direction = .frenchToGerman
    @Published var selectedSetupContent: FlashcardContentSelection = .mixed
    @Published var isUsingAllCardCount = true
    @Published var customCardCountText = ""
    @Published var isShowingSetup = true
    @Published var shouldAutoStartFromLaunch = false
    @Published var selectedStackListIDs: Set<UUID> = []
    @Published var selectedStackDictionaryLearningLevel: DictionaryLearningLevel = .beginner
    @Published var showingStackComposer = false
    @Published var loadedDictionaryStackList: VocabularyList?

    struct DictionaryStackLoadContext: Equatable {
        let learningLevel: DictionaryLearningLevel
        let language: StudyLanguage
    }

    var dictionaryStackLoadGeneration = 0
    var loadedDictionaryContext: DictionaryStackLoadContext?
    var preferredLaunchItemIDs: Set<UUID> = []
}
