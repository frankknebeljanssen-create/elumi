import SwiftUI

struct AppDestinationHost: View {
    let screen: AppScreen
    @ObservedObject var runtime: AppRuntimeContainer
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let navigate: (AppScreen) -> Void
    let markFlashcardsOpenTiming: (String) -> Void

    var body: some View {
        switch screen {
        case .train(let launchContext):
            trainDestination(launchContext: launchContext)
        case .flashcards(let launchContext):
            flashcardsDestination(launchContext: launchContext)
        case .quiz(let launchContext):
            quizDestination(launchContext: launchContext)
        case .hearts:
            heartsDestination
        case .gameHub:
            GameHubView(
                feedbackPlayer: feedbackPlayer,
                goHome: goHome,
                openSettings: openSettings,
                openInfo: openInfo
            )
        case .arcade(let autoStart):
            // Arcade als echte Navigation-Destination — Footer bleibt
            // während des Start-Overlays sichtbar, verschwindet erst,
            // wenn das Spiel tatsächlich beginnt (via Immersive-Flag).
            ElumiArcadeGameView(feedbackPlayer: feedbackPlayer, autoStart: autoStart)
        case .lists(let launchContext):
            listsDestination(launchContext: launchContext)
        case .lexicon:
            lexiconDestination
        case .scan:
            scanDestination
        case .settings:
            SettingsView(
                feedbackPlayer: feedbackPlayer,
                goHome: goHome,
                openInfo: openInfo
            )
        case .account:
            // `.account`-Route zeigt jetzt die neue ProfileView — das
            // alte AccountView.swift bleibt als Legacy-Datei im Repo,
            // wird aber von nirgendwo mehr geöffnet.
            ProfileView(
                feedbackPlayer: feedbackPlayer,
                goHome: goHome,
                openSettings: openSettings,
                openInfo: openInfo
            )
        case .info:
            InfoView(
                feedbackPlayer: feedbackPlayer,
                goHome: goHome,
                openSettings: openSettings
            )
        }
    }

    @ViewBuilder
    private func loadingDestinationView(
        _ title: String,
        onPrepare: (@Sendable () async -> Void)? = nil
    ) -> some View {
        VStack(spacing: 14) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(AppTheme.Colors.primary)

            Text(title)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textPrimary)

            Text("Bitte einen kurzen Moment.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(AppTheme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appScreenBackground(.home)
        .task {
            if let onPrepare {
                await onPrepare()
            } else {
                await Task.yield()
                await runtime.ensureDependenciesReady(markFlashcardsOpenTiming: markFlashcardsOpenTiming)
            }
        }
    }

    @ViewBuilder
    private func trainDestination(launchContext: TrainingLaunchContext?) -> some View {
        if let listStore = runtime.listStore {
            TrainingView(
                listStore: listStore,
                runtimeSpeechController: runtime.speechController,
                runtimeSpeaker: runtime.speaker,
                feedbackPlayer: feedbackPlayer,
                launchContext: launchContext,
                goHome: goHome,
                openSettings: openSettings,
                openInfo: openInfo,
                ensureAudioDependenciesReady: {
                    await runtime.ensureTrainingDependenciesReady()
                }
            )
        } else {
            loadingDestinationView("Trainieren wird vorbereitet") {
                await runtime.ensureTrainingDependenciesReady()
            }
        }
    }

    @ViewBuilder
    private func flashcardsDestination(launchContext: FlashcardLaunchContext?) -> some View {
        if let flashcardSessionStore = runtime.flashcardSessionStore,
           let listStore = runtime.listStore,
           let speechController = runtime.speechController,
           let speaker = runtime.speaker {
            let _ = markFlashcardsOpenTiming("destination_ready_with_dependencies")
            FlashcardsView(
                sessionStore: flashcardSessionStore,
                listStore: listStore,
                speechController: speechController,
                speaker: speaker,
                feedbackPlayer: feedbackPlayer,
                launchContext: launchContext,
                goHome: goHome,
                openSettings: openSettings,
                openInfo: openInfo
            )
        } else {
            let _ = markFlashcardsOpenTiming("destination_showing_loader")
            loadingDestinationView("Karteikarten werden vorbereitet") {
                markFlashcardsOpenTiming("loader_task_started")
                await runtime.ensureDependenciesReady(markFlashcardsOpenTiming: markFlashcardsOpenTiming)
            }
        }
    }

    @ViewBuilder
    private func quizDestination(launchContext: QuizLaunchContext?) -> some View {
        if let listStore = runtime.listStore {
            QuizView(
                listStore: listStore,
                feedbackPlayer: feedbackPlayer,
                launchContext: launchContext,
                goHome: goHome,
                openSettings: openSettings,
                openInfo: openInfo
            )
        } else {
            loadingDestinationView("Quiz wird vorbereitet") {
                await runtime.ensureQuizDependenciesReady()
            }
        }
    }

    @ViewBuilder
    private var heartsDestination: some View {
        if let listStore = runtime.listStore {
            HeartsView(
                feedbackPlayer: feedbackPlayer,
                listStore: listStore,
                goHome: goHome,
                openSettings: openSettings
            )
        } else {
            loadingDestinationView("Sammlung wird vorbereitet") {
                await runtime.ensureListDrivenDependenciesReady()
            }
        }
    }

    @ViewBuilder
    private func listsDestination(launchContext: ListLaunchContext?) -> some View {
        if let listStore = runtime.listStore {
            ListsView(
                feedbackPlayer: feedbackPlayer,
                listStore: listStore,
                launchContext: launchContext,
                goHome: goHome,
                openSettings: openSettings,
                openInfo: openInfo
            )
        } else {
            loadingDestinationView("Listen werden vorbereitet") {
                await runtime.ensureListDrivenDependenciesReady()
            }
        }
    }

    @ViewBuilder
    private var lexiconDestination: some View {
        if let listStore = runtime.listStore {
            LexiconView(
                feedbackPlayer: feedbackPlayer,
                listStore: listStore,
                goHome: goHome,
                openSettings: openSettings,
                openInfo: openInfo
            )
        } else {
            loadingDestinationView("Wörterbuch wird vorbereitet") {
                await runtime.ensureListDrivenDependenciesReady()
            }
        }
    }

    private var scanDestination: some View {
        ScanImportView(
            feedbackPlayer: feedbackPlayer,
            listStore: runtime.listStore,
            ensureListStoreReady: { runtime.ensureListStoreReady() },
            goHome: goHome,
            openSettings: openSettings,
            openInfo: openInfo,
            navigate: navigate
        )
    }
}
