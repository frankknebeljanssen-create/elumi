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
        case .lernstatus:
            LernstatusView(
                feedbackPlayer: feedbackPlayer,
                goHome: goHome,
                openSettings: openSettings
            )
        case .gameHub:
            GameHubView(
                feedbackPlayer: feedbackPlayer,
                listStore: runtime.listStore,
                goHome: goHome,
                openSettings: openSettings,
                openInfo: openInfo,
                navigate: navigate
            )
        case .arcade(let autoStart):
            // Arcade als echte Navigation-Destination — Footer bleibt
            // während des Start-Overlays sichtbar, verschwindet erst,
            // wenn das Spiel tatsächlich beginnt (via Immersive-Flag).
            //
            // **Quick-Fix 2026-04-30 (`v2-elumi-gameover-cta-home`)** —
            // `goHome` wird durchgereicht, damit die „Lernen starten"-
            // CTAs in den Overlays direkt zur Startseite zurückkehren
            // statt nur eine Stack-Ebene zu poppen (= zum GameHub).
            ElumiArcadeGameView(
                feedbackPlayer: feedbackPlayer,
                autoStart: autoStart,
                goHome: goHome
            )
        case .wordRunner:
            // Word Runner als echte Nav-Destination (Phase 7.5) — der
            // globale Footer bleibt während des Start-Screens sichtbar;
            // Immersive-Modus wird erst im Run aktiviert, analog
            // Arcade. Listen-Store + Go-To-Lists-Callback kommen aus
            // dem Runtime-Container / der Navigation-Coordinator-Schicht.
            WordRunnerGameView(
                listStore: runtime.listStore,
                onClose: goHome,
                onGoToLists: { navigate(.lists(nil)) }
            )
        case .lists(let launchContext):
            listsDestination(launchContext: launchContext)
        case .lexicon:
            lexiconDestination
        case .scan:
            scanDestination
        case .accents(let launchContext):
            // Akzent-Modul — nutzt den runtime.listStore für die Listen-
            // Auswahl, analog zu Quiz/Train. Bei Erst-Start kann der
            // Store noch laden → Loader-Screen mit ensure-Call.
            accentsDestination(launchContext: launchContext)
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
        case .trophy:
            // Pokal-Tab — sammelt die ausführlichen Status-Cards, die
            // früher dominant auf Home lagen (Streak, Level/XP,
            // Lernstatus). Home zeigt jetzt nur eine kompakte Status-
            // Card; Detail lebt hier.
            TrophyView(
                feedbackPlayer: feedbackPlayer,
                goHome: goHome,
                openSettings: openSettings,
                openInfo: openInfo,
                navigate: navigate
            )
        case .trainingChainOverview(let chain):
            // **Trainings-Chain Pre-Screen** (Stufe 2, 2026-04-30,
            // Branch `feature/training-session-flow`). Zwischen Slot-
            // Reveal und erstem Modul-Open gepusht. Render-Logik in
            // `TrainingChainOverviewView`.
            //
            // **`onStartTraining`** baut den AppScreen für den ersten
            // Chain-Step (über `HomeHeroModule.chainScreen(chainContext:)`)
            // und pusht ihn — der User wechselt vom Pre-Screen zur
            // ersten Modul-Session. Bei Jackpot (`chain.isJackpot`)
            // ist der CTA in der View selbst disabled, Closure wird
            // nicht aufgerufen.
            //
            // **`onBack`** ruft `TrainingChainStore.shared.clear()` —
            // Pre-Screen-Eigene `dismiss()` (via @Environment) pop-t
            // den Stack. `lastSpinResult` im ElumiTab bleibt
            // unangetastet (R12-Spec).
            TrainingChainOverviewView(
                chain: chain,
                onStartTraining: { [chain] in
                    guard let firstStep = chain.currentStep else { return }
                    navigate(firstStep.chainScreen(chainContext: chain))
                },
                onBack: {
                    TrainingChainStore.shared.clear()
                },
                goHome: goHome,
                openSettings: openSettings,
                openInfo: openInfo,
                feedbackPlayer: feedbackPlayer
            )
        case .elumi:
            // **Elumi-Tab** (Phase 8) — persönlicher Begleiter-Screen:
            // Begrüßung + Axolotl, eine Empfehlungs-Card (V1 Karteikarten),
            // kompakter Streak/Level/XP-Status. Bewusst schlank, klar
            // abgegrenzt von Home/Spielen/Fortschritt/Wörterbuch.
            //
            // **Stufe 1c (2026-04-30)**: `listStore` durchgereicht für
            // die Listen-Auswahl-Card im Setup-Modal (Multi-Select-Sheet
            // schreibt in die globale Listen-Auswahl). Während Warmup
            // kann `runtime.listStore` theoretisch noch nil sein — wir
            // entscheiden uns hier defensiv für einen leeren Fallback,
            // damit der Tab nicht crasht; das Setup-Modal zeigt dann
            // nur „Keine Listen verfügbar" bis der Store ready ist.
            if let listStore = runtime.listStore {
                ElumiTabView(
                    feedbackPlayer: feedbackPlayer,
                    goHome: goHome,
                    openSettings: openSettings,
                    openInfo: openInfo,
                    navigate: navigate,
                    listStore: listStore
                )
            } else {
                Color.clear
                    .onAppear { _ = runtime.ensureListStoreReady() }
            }
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

    @ViewBuilder
    private func accentsDestination(launchContext: AccentsLaunchContext?) -> some View {
        if let listStore = runtime.listStore, let speaker = runtime.speaker {
            AccentsEntryView(
                listStore: listStore,
                feedbackPlayer: feedbackPlayer,
                speaker: speaker,
                goHome: goHome,
                openSettings: openSettings,
                launchContext: launchContext
            )
        } else {
            loadingDestinationView("Akzente wird vorbereitet") {
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
