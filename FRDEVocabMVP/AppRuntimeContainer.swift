import Foundation
import SwiftUI

@MainActor
final class AppRuntimeContainer: ObservableObject {
    @Published private(set) var speechController: SpeechController?
    @Published private(set) var speaker: Speaker?
    @Published private(set) var feedbackPlayer: FeedbackPlayer? = FeedbackPlayer()
    @Published private(set) var listStore: VocabularyListStore?
    @Published private(set) var flashcardSessionStore: FlashcardSessionStore?

    private let vocabularyListRepository = VocabularyListStoreRepository()
    private let flashcardSessionRepository = FlashcardSessionRepository()
    private var didBootstrapDependencies = false
    private var listWarmupTask: Task<Void, Never>?
    private var flashcardWarmupTask: Task<Void, Never>?
    private var homePreparationTask: Task<Void, Never>?

    init() {
        feedbackPlayer = FeedbackPlayer()

        // Always reset to 3 starter credits (testing)
        UserDefaults.standard.set(3, forKey: appArcadeCreditsKey)
    }

    var isHomeShellReady: Bool {
        feedbackPlayer != nil
    }

    func ensureHomeShellDependenciesReady() {
        if feedbackPlayer == nil {
            feedbackPlayer = FeedbackPlayer()
        }
    }

    func bootstrapDependenciesIfNeeded() {
        guard !didBootstrapDependencies else { return }
        didBootstrapDependencies = true
        ensureHomeShellDependenciesReady()

        let vocabularyListRepository = self.vocabularyListRepository
        let flashcardSessionRepository = self.flashcardSessionRepository

        // Phase 1: Create listStore IMMEDIATELY with built-in data only (0ms)
        let emptySnapshot = VocabularyListStoreSnapshot(
            customLists: [],
            selectedListID: VocabularyListStore.builtInListID
        )
        let store = VocabularyListStore(repository: vocabularyListRepository, snapshot: emptySnapshot)
        listStore = store
        speechController = SpeechController()
        speaker = Speaker()
        print("⏱ [Bootstrap] listStore + speech + speaker created instantly")

        // Phase 2: Load custom lists in background, update store when ready
        listWarmupTask?.cancel()
        flashcardWarmupTask?.cancel()
        homePreparationTask?.cancel()

        listWarmupTask = Task.detached(priority: .userInitiated) {
            let totalStart = CFAbsoluteTimeGetCurrent()
            DataStore.prewarmBuiltInLaunchData()

            var start = CFAbsoluteTimeGetCurrent()
            vocabularyListRepository.prewarmStoredStateIfNeeded(
                customListsKey: "FRDEVocabMVP.customLists.v2",
                selectedListKey: "FRDEVocabMVP.selectedListID.v2",
                sampleListsSeededKey: "FRDEVocabMVP.sampleListsSeeded.v1",
                builtInListID: VocabularyListStore.builtInListID,
                sampleSeeds: sampleVocabularyListSeeds
            )
            print("⏱ [Warmup:List] prewarmStored: \(Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded()))ms")

            let snapshot = vocabularyListRepository.cachedSnapshot()
            if let snapshot {
                await MainActor.run {
                    store.apply(snapshot: snapshot)
                    print("⏱ [Warmup:List] applied snapshot → \(store.customLists.count) custom lists")
                }
            }
            print("⏱ [Warmup:List] TOTAL: \(Int(((CFAbsoluteTimeGetCurrent() - totalStart) * 1000).rounded()))ms")
        }

        flashcardWarmupTask = Task.detached(priority: .userInitiated) {
            let totalStart = CFAbsoluteTimeGetCurrent()
            DataStore.prewarmFlashcardLaunchData()
            flashcardSessionRepository.prewarmStoredStateIfNeeded(
                defaultDeckID: DataStore.flashcardDecks.first?.id ?? "flashcards-1",
                selectedDeckKey: "FRDEVocabMVP.flashcardDeck.v1",
                selectedDirectionKey: appDirectionKey,
                sessionKey: "FRDEVocabMVP.flashcardSession.v1"
            )
            print("⏱ [Warmup:Flashcard] TOTAL: \(Int(((CFAbsoluteTimeGetCurrent() - totalStart) * 1000).rounded()))ms")
        }
    }

    func ensureDependenciesReady(markFlashcardsOpenTiming: ((String) -> Void)? = nil) async {
        ensureHomeShellDependenciesReady()
        ensureBaseDependenciesReady()

        if flashcardSessionStore == nil {
            await awaitFlashcardWarmupIfNeeded()
            let start = CFAbsoluteTimeGetCurrent()
            flashcardSessionStore = makeFlashcardSessionStore()
            let elapsedMS = ms(since: start)
            markFlashcardsOpenTiming?("init_flashcardSessionStore \(elapsedMS)ms")
        }
    }

    func ensureTrainingDependenciesReady() async {
        ensureHomeShellDependenciesReady()
        ensureBaseDependenciesReady()
    }

    func ensureQuizDependenciesReady() async {
        ensureHomeShellDependenciesReady()
        ensureBaseDependenciesReady()
    }

    func ensureListDrivenDependenciesReady() async {
        ensureHomeShellDependenciesReady()
        ensureBaseDependenciesReady()
    }

    private func ensureBaseDependenciesReady() {
        if listStore == nil {
            listStore = makeListStore()
        }
        if speechController == nil {
            speechController = SpeechController()
        }
        if speaker == nil {
            speaker = Speaker()
        }
    }

    @discardableResult
    func ensureListStoreReady() -> VocabularyListStore {
        if let listStore {
            return listStore
        }

        let store = makeListStore()
        listStore = store
        return store
    }

    private func makeListStore() -> VocabularyListStore {
        VocabularyListStore(
            repository: vocabularyListRepository,
            snapshot: vocabularyListRepository.cachedSnapshot()
        )
    }

    private func makeFlashcardSessionStore() -> FlashcardSessionStore {
        FlashcardSessionStore(
            repository: flashcardSessionRepository,
            snapshot: flashcardSessionRepository.cachedSnapshot()
        )
    }

    private func awaitFlashcardWarmupIfNeeded() async {
        let task = flashcardWarmupTask
        await task?.value
    }

    private func ms(since start: CFAbsoluteTime) -> Int {
        Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded())
    }
}
