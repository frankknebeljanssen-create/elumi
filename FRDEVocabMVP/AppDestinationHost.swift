import SwiftUI

struct AppDestinationHost: View {
    let screen: AppScreen
    @ObservedObject var runtime: AppRuntimeContainer
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let navigate: (AppScreen) -> Void
    /// **Stufe 3 (2026-05-01, Branch `feature/training-session-flow`)** —
    /// Push-with-Replace fürs Chain-Advance-Pattern (siehe
    /// `AppNavigationCoordinator.replaceTopWith`). Wird vom Host als
    /// Closure in `appChainAdvanceAction`-Environment installiert,
    /// damit der NavigationStack während einer Chain konstant tief
    /// bleibt. RootContentView wired diesen Param an
    /// `coordinator.replaceTopWith(_:)`.
    let replaceTop: (AppScreen) -> Void
    let markFlashcardsOpenTiming: (String) -> Void

    /// **Stufe 3 Helper**: zentrale Closure, die bei einem Modul-Chain-
    /// Done-CTA-Tap aufgerufen wird. Kümmert sich um: Outcome
    /// einsammeln (`TrainingChainStore.advanceChain(...)`), nächstes
    /// Ziel berechnen, dann via `replaceTop(...)` pushen. Wird per
    /// `.environment(\.appChainAdvanceAction, …)` an die Modul-Cases
    /// gebunden, damit der Modul-Code keine Kenntnis vom Chain-Store
    /// oder der Navigation-Coordinator-Mechanik braucht.
    private func chainAdvanceClosure() -> (SessionRewardOutcome?) -> Void {
        { outcome in
            if let next = TrainingChainStore.shared.advanceChain(recordedOutcome: outcome) {
                replaceTop(next)
            }
        }
    }

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
                    // **Stufe 3 (2026-05-01)** — Index-0-Restart bei
                    // Re-Entry. Wenn der User nach „Back aus Modul N"
                    // wieder auf dem Pre-Screen landet, ist die
                    // `chainStore.currentChain.currentIndex` ggf. > 0
                    // (durch advance-Calls aus den Modulen). Der
                    // Pre-Screen hält aber die ORIGINAL-Chain via
                    // Navigation-Route (frozen bei Index 0). `start(chain)`
                    // re-initialisiert den Store mit der frischen
                    // (Index-0-)Chain — gleichzeitig werden
                    // `stepOutcomes` geleert. Semantik: Pre-Screen-
                    // Re-Entry = neue Session, kein Pause-Resume.
                    // Beim Erst-Eintritt ist das ein No-Op (Store
                    // wurde von ElumiTab.startTraining schon mit
                    // derselben Chain initialisiert).
                    TrainingChainStore.shared.start(chain)
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
        case .trainingChainComplete:
            // **Stufe 5 (2026-05-02)** — End-Summary-View für die
            // abgeschlossene Trainings-Chain. Aggregiert
            // `TrainingChainStore.shared.stepOutcomes` (XP, Korrekt-
            // Quote, Streak, Level-Up) plus Slot-Tickets aus
            // `chain.sourceCenterSymbolKinds`. Konfetti + Sound +
            // Haptik on appear. Primary „Noch eine Runde" pulsiert
            // und führt zurück zur Slot-Machine (`.elumi`-Tab),
            // Secondary „Zur Startseite" → Home.
            //
            // Chain-Cleanup: `goHome()` räumt seit dem Hot-Fix vom
            // 2026-05-02 (Commit `e859491`) den `TrainingChainStore`
            // automatisch ab — kein expliziter `clear()` nötig.
            TrainingChainCompleteSummaryView(
                feedbackPlayer: feedbackPlayer,
                onPlayAgain: {
                    goHome()
                    navigate(.elumi)
                },
                onGoHome: goHome,
                openSettings: openSettings
            )
        case .trainingHub:
            // **2026-05-06 Home-Refactor (Hybrid γ v3)** — Sub-Screen
            // mit Vokabeln (Allgemein) + Nomen/Verben/Artikel/Verbformen
            // (Spezial 2×2) + Akzente quer. Erreichbar via „Training"-
            // Card auf Home. Routing zu den Modul-Cards läuft über das
            // injizierte `navigate`-Closure (analog GameHubView).
            TrainingHubView(
                feedbackPlayer: feedbackPlayer,
                openScreen: navigate,
                goHome: goHome,
                openSettings: openSettings
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
            // **Stufe 3 R4-Safety (2026-05-01)** — `id(...)` erzwingt
            // beim Wechsel zwischen zwei `.train`-Modi (z. B. Vokabeln
            // → Verben in derselben Chain) ein Fresh-Re-Mount. SwiftUI
            // sollte das durch unterschiedliche AppScreen-Hashable-
            // Werte schon tun; der explizite ID-Trigger ist defensives
            // Net, falls SwiftUI bei replaceTopWith differential reuse
            // wählt. ID-Quelle: TrainingMode-RawValue + Chain-Index
            // (eindeutig pro Step im Chain-Verlauf).
            let modeKey = launchContext?.preferredMode?.rawValue ?? "train"
            let chainIdx = launchContext?.chainContext?.currentIndex ?? -1
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
            .id("train:\(modeKey):\(chainIdx)")
            .environment(\.appChainAdvanceAction, chainAdvanceClosure())
            .modifier(ChainTimerOverlayModifier())
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
            .environment(\.appChainAdvanceAction, chainAdvanceClosure())
            .modifier(ChainTimerOverlayModifier())
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
            .environment(\.appChainAdvanceAction, chainAdvanceClosure())
            .modifier(ChainTimerOverlayModifier())
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
            .environment(\.appChainAdvanceAction, chainAdvanceClosure())
            // **Stufe 4b-Modal-Refactor (2026-05-02)** — Chain-Timer-
            // Overlay-Mount für Akzente sitzt **nicht mehr hier**: die
            // tatsächliche Session läuft in einem `.fullScreenCover` der
            // EntryView, ein Modifier auf der EntryView wäre hinter dem
            // Cover gerendert (visuell unsichtbar). Stattdessen mountet
            // `AccentsSessionView` (= Cover-Content) den Modifier selbst,
            // damit die Timer-Bar und das Cutoff-Modal über dem
            // tatsächlichen Session-Content erscheinen. Closure-
            // Registration für „Jetzt weiter" liegt dort am gleichen Ort
            // mit Engine-Zugriff.
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
