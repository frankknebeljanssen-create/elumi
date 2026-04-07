import Foundation
import SwiftUI

@MainActor
final class AppRuntimeContainer: ObservableObject {
    @Published private(set) var speechController: SpeechController?
    @Published private(set) var speaker: Speaker?
    @Published private(set) var feedbackPlayer: FeedbackPlayer?
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

        listWarmupTask?.cancel()
        flashcardWarmupTask?.cancel()
        homePreparationTask?.cancel()
        listWarmupTask = Task.detached(priority: .utility) {
            DataStore.prewarmBuiltInLaunchData()
            vocabularyListRepository.prewarmStoredStateIfNeeded(
                customListsKey: "FRDEVocabMVP.customLists.v2",
                selectedListKey: "FRDEVocabMVP.selectedListID.v2",
                sampleListsSeededKey: "FRDEVocabMVP.sampleListsSeeded.v1",
                builtInListID: VocabularyListStore.builtInListID,
                sampleSeeds: sampleVocabularyListSeeds
            )
        }

        flashcardWarmupTask = Task.detached(priority: .utility) {
            DataStore.prewarmFlashcardLaunchData()
            flashcardSessionRepository.prewarmStoredStateIfNeeded(
                defaultDeckID: DataStore.flashcardDecks.first?.id ?? "flashcards-1",
                selectedDeckKey: "FRDEVocabMVP.flashcardDeck.v1",
                selectedDirectionKey: appDirectionKey,
                sessionKey: "FRDEVocabMVP.flashcardSession.v1"
            )
        }

        homePreparationTask = Task { [weak self] in
            guard let self else { return }
            await self.awaitListWarmupIfNeeded()
            guard !Task.isCancelled else { return }
            self.prepareHomeStudyDependenciesIfNeeded()
        }
    }

    func ensureDependenciesReady(markFlashcardsOpenTiming: ((String) -> Void)? = nil) async {
        ensureHomeShellDependenciesReady()
        await ensureStudyDependenciesReady(markFlashcardsOpenTiming: markFlashcardsOpenTiming)
    }

    func ensureStudyDependenciesReady(markFlashcardsOpenTiming: ((String) -> Void)? = nil) async {
        await awaitListWarmupIfNeeded()

        if listStore == nil {
            let start = CFAbsoluteTimeGetCurrent()
            listStore = makeListStore()
            let elapsedMS = Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded())
            markFlashcardsOpenTiming?("init_listStore \(elapsedMS)ms")
        }

        if speechController == nil {
            let start = CFAbsoluteTimeGetCurrent()
            speechController = SpeechController()
            let elapsedMS = Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded())
            markFlashcardsOpenTiming?("init_speechController \(elapsedMS)ms")
        }

        if speaker == nil {
            let start = CFAbsoluteTimeGetCurrent()
            speaker = Speaker()
            let elapsedMS = Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded())
            markFlashcardsOpenTiming?("init_speaker \(elapsedMS)ms")
        }

        if flashcardSessionStore == nil {
            await awaitFlashcardWarmupIfNeeded()
            let start = CFAbsoluteTimeGetCurrent()
            flashcardSessionStore = makeFlashcardSessionStore()
            let elapsedMS = Int(((CFAbsoluteTimeGetCurrent() - start) * 1000).rounded())
            markFlashcardsOpenTiming?("init_flashcardSessionStore \(elapsedMS)ms")
        }
    }

    func ensureTrainingDependenciesReady() async {
        ensureHomeShellDependenciesReady()
        await awaitListWarmupIfNeeded()
        prepareHomeStudyDependenciesIfNeeded()
    }

    func ensureQuizDependenciesReady() async {
        ensureHomeShellDependenciesReady()
        await awaitListWarmupIfNeeded()
        if listStore == nil {
            listStore = makeListStore()
        }
    }

    func ensureListDrivenDependenciesReady() async {
        ensureHomeShellDependenciesReady()
        await awaitListWarmupIfNeeded()
        if listStore == nil {
            listStore = makeListStore()
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

    private func awaitListWarmupIfNeeded() async {
        let task = listWarmupTask
        await task?.value
    }

    private func awaitFlashcardWarmupIfNeeded() async {
        let task = flashcardWarmupTask
        await task?.value
    }

    private func prepareHomeStudyDependenciesIfNeeded() {
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
}
