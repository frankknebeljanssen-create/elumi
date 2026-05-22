import Foundation
import SwiftUI

@MainActor
final class AppRuntimeContainer: ObservableObject {
    @Published private(set) var speechController: SpeechController?
    @Published private(set) var speaker: Speaker?
    @Published private(set) var feedbackPlayer: FeedbackPlayer? = FeedbackPlayer()
    @Published private(set) var listStore: VocabularyListStore?
    @Published private(set) var flashcardSessionStore: FlashcardSessionStore?

    /// Referenz auf den App-weiten Singleton — die HomeView-Bar und Module
    /// können den Store auch direkt via `ProgressStore.shared` lesen, aber
    /// die explizite Container-Property macht die Abhängigkeit sichtbar.
    let progressStore: ProgressStore = .shared
    /// High-Level-Service für `record(session:)`. Single Source of Truth.
    let progressService: ProgressService = .shared

    private let vocabularyListRepository = VocabularyListStoreRepository()
    private let flashcardSessionRepository = FlashcardSessionRepository()
    private var didBootstrapDependencies = false
    private var listWarmupTask: Task<Void, Never>?
    private var flashcardWarmupTask: Task<Void, Never>?
    private var homePreparationTask: Task<Void, Never>?

    init() {
        let player = FeedbackPlayer()
        feedbackPlayer = player
        // `FeedbackEngine` bekommt einen globalen Player — dadurch können
        // alle Streak-/Milestone-Events zentral ertönen, ohne dass jede
        // Call-Site den Player durchreichen muss. Der Engine hält eine
        // `weak`-Referenz; wenn der Container den Player später ersetzt
        // (z. B. nach Permission-Wechsel), reicht `attach` erneut.
        FeedbackEngine.shared.attach(feedbackPlayer: player)
        // Hinweis: Die alte Test-Reset-Logik („immer 3 Credits beim Start")
        // wurde entfernt. Ab jetzt lebt Credits-Verwaltung im ProgressStore
        // und wird über echte Sessions verdient/ausgegeben.
    }

    var isHomeShellReady: Bool {
        feedbackPlayer != nil
    }

    func ensureHomeShellDependenciesReady() {
        if feedbackPlayer == nil {
            let player = FeedbackPlayer()
            feedbackPlayer = player
            // Bei Re-Creation den Engine erneut attachen — sonst hält
            // er eine nil-weak-Ref auf den alten Player.
            FeedbackEngine.shared.attach(feedbackPlayer: player)
        }
    }

    func bootstrapDependenciesIfNeeded() {
        guard !didBootstrapDependencies else { return }
        didBootstrapDependencies = true
        ensureHomeShellDependenciesReady()

        let vocabularyListRepository = self.vocabularyListRepository
        let flashcardSessionRepository = self.flashcardSessionRepository

        // **Struktur-Fix (2026-05-21)** — VocabularyListStore lädt jetzt
        // SYNCHRON im init (snapshot: nil → `loadState()`), analog
        // `ScanDraftStore.shared`. Vorher: leerer Placeholder + deferred
        // Warmup-`loadState` → Race-Fenster, in dem ein init-Migrations-
        // Leer-Save die scoped Datei überschreiben konnte (Custom-Listen-
        // Verlust nach Deploy). Der teure Built-in-Katalog bleibt off-main
        // (Warmup-Task unten); der Custom-Listen-JSON ist klein → der
        // synchrone Read kostet nur wenige ms. init-Migrationen laufen
        // dadurch auf den ECHTEN geladenen Daten statt auf leerem Store.
        let store = VocabularyListStore(repository: vocabularyListRepository)
        listStore = store
        speechController = SpeechController()
        speaker = Speaker()
        appDebugLog("⏱ [Bootstrap] listStore + speech + speaker created instantly")
        // **Spielstand-Sichtprüfung beim Bootstrap**: Bei jedem App-
        // Start sehen wir auf einen Blick, was an persistierten Daten
        // geladen wurde. Wichtig für die User-Frage „bleibt mein
        // Spielstand erhalten?". Wenn die Zahlen nach einem Build
        // unerwartet auf 0 stehen, ist die Sandbox vom Simulator/
        // Device weggewechselt — kein Code-seitiger Auto-Reset.
        let progress = ProgressStore.shared.progress
        let stats = DailyStatsStore.shared
        appDebugLog("📦 [Bootstrap] persisted state — " +
              "XP=\(progress.totalXP) " +
              "streakCurrent=\(progress.currentStreak) " +
              "streakBest=\(progress.bestStreak) " +
              "credits=\(progress.arcadeCredits) " +
              "actionsToday=\(stats.actionsToday)")

        // Phase 2: Load custom lists in background, update store when ready
        listWarmupTask?.cancel()
        flashcardWarmupTask?.cancel()
        homePreparationTask?.cancel()

        listWarmupTask = Task.detached(priority: .userInitiated) {
            let totalStart = CFAbsoluteTimeGetCurrent()
            // **Struktur-Fix (2026-05-21)** — Custom-Listen sind bereits
            // SYNCHRON im Store-init geladen. Hier nur noch den teuren
            // Built-in-Katalog off-main materialisieren — KEIN deferred
            // `loadState` mehr (das alte Race-Fenster ist damit zu).
            DataStore.prewarmBuiltInLaunchData()
            appDebugLog("⏱ [Warmup:List] builtin prewarm: \(Int(((CFAbsoluteTimeGetCurrent() - totalStart) * 1000).rounded()))ms")
        }

        flashcardWarmupTask = Task.detached(priority: .userInitiated) { [weak self] in
            let totalStart = CFAbsoluteTimeGetCurrent()
            DataStore.prewarmFlashcardLaunchData()
            flashcardSessionRepository.prewarmStoredStateIfNeeded(
                defaultDeckID: DataStore.flashcardDecks.first?.id ?? "flashcards-1",
                selectedDeckKey: "FRDEVocabMVP.flashcardDeck.v1",
                selectedDirectionKey: appDirectionKey,
                sessionKey: "FRDEVocabMVP.flashcardSession.v1"
            )
            appDebugLog("⏱ [Warmup:Flashcard] TOTAL: \(Int(((CFAbsoluteTimeGetCurrent() - totalStart) * 1000).rounded()))ms")

            // **Preload (2026-05-22)** — den FlashcardSessionStore direkt am
            // Warmup-Ende bauen (der Snapshot ist jetzt frisch geprewarmt →
            // billiger Init), damit beim ersten KK-Öffnen
            // `flashcardSessionStore != nil` ist und der „Karteikarten werden
            // vorbereitet"-Loader gar nicht erst triggert. nil-Guard: hat der
            // User VOR dem Warmup-Ende getippt, baut `ensureDependenciesReady`
            // den Store → kein Doppel-Bau. App-Start bleibt unberührt (Task ist
            // detached; nur der billige Store-Init kommt ans Task-Ende).
            await MainActor.run {
                guard let self, self.flashcardSessionStore == nil else { return }
                self.flashcardSessionStore = self.makeFlashcardSessionStore()
                appDebugLog("⏱ [Warmup:Flashcard] flashcardSessionStore preloaded")
            }
        }

        // Lexicon-Prewarm entfernt: der alte Task.detached hat im
        // Hintergrund ~11 s verbraucht (`[CuratedLexicon]
        // enrichMissingGenderInfo: 6758ms` + `internalLexiconEntries:
        // 3876ms`). Die teure `enrichMissingGenderInfo`-Pass wird
        // **ausschließlich** vom Lexicon-View (Wörterbuch-Browser) und
        // dessen Suche konsumiert — Home, Training, Flashcards, Quiz
        // und Artikel-Modus (nutzt separates `StandardVocabularyLoader`-
        // Gender-Backend) kommen ohne sie aus.
        //
        // Stattdessen läuft der Compute jetzt **lazy** beim ersten
        // Öffnen des Lexicon-Views: die statische
        // `curatedInternalLexiconEntries`-Property initialisiert sich
        // on-demand, und `LexiconViewModel.reloadEntries(...)` hat
        // bereits den Async-Pfad mit `isLoadingLexiconEntries`-Spinner
        // — der User bekommt also auf der ersten Öffnung eine klare
        // Ladestand-Anzeige statt eines kryptischen ~11 s-Bootstrap-
        // Stalls. Folge-Öffnungen sind instant (Swift cached den
        // statischen Let).
    }

    func ensureDependenciesReady(markFlashcardsOpenTiming: ((String) -> Void)? = nil) async {
        ensureHomeShellDependenciesReady()
        ensureBaseDependenciesReady()

        if flashcardSessionStore == nil {
            await awaitFlashcardWarmupIfNeeded()
            // Re-Check nach dem await: der Warmup-Preload (am Task-Ende) kann
            // den Store inzwischen gebaut haben — dann nicht überschreiben /
            // doppelt bauen.
            if flashcardSessionStore == nil {
                let start = CFAbsoluteTimeGetCurrent()
                flashcardSessionStore = makeFlashcardSessionStore()
                let elapsedMS = ms(since: start)
                markFlashcardsOpenTiming?("init_flashcardSessionStore \(elapsedMS)ms")
            }
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
