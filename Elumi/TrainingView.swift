import SwiftUI

struct TrainingView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.appUsesGlobalChrome) var usesGlobalChrome
    /// **Stufe 3 (2026-05-01)** — Chain-Advance-Closure (siehe
    /// FlashcardsView.swift:Doc). Wird sowohl im
    /// `trainingSummaryScreen` als auch `verbformsResultScreen`
    /// gelesen, weil beide Done-CTAs das Chain-Pattern unterstützen.
    @Environment(\.appChainAdvanceAction) var chainAdvance
    /// **Daily Drop Modul 2.8 (2026-05-23)** — bewiesener Chat-Keyboard-
    /// Mechanismus: bei Tippfeld-Fokus blenden wir den globalen Footer
    /// (root-`safeAreaInset(.bottom)` in RootContentView) aus, damit die
    /// Tastatur die View nicht hochschiebt. Reset bei Blur + onDisappear
    /// (sonst bleibt der Footer auf Folge-Screens weg). Env-Name ist
    /// chat-historisch, der Mechanismus generisch.
    @Environment(\.appSetChatKeyboardActiveAction) var setKeyboardChromeHidden
    /// **Daily Drop Modul 2.5 (2026-05-23)** — Count-Modus-Chain-Step?
    /// Dann nahtloser Auto-Advance statt Zwischen-Summary. False bei
    /// Zeit-Chain (Summary+CTA) und im isolierten Modul-1-Test (kein
    /// chainContext).
    var isCountChainStep: Bool {
        launchContext?.chainContext?.isCountMode == true
    }
    @AppStorage(appDirectionKey) var selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
    @AppStorage(appArcadeCreditsKey) var arcadeCredits = 0
    /// Globale Speed-Round-Dauer — liest aus dem gemeinsamen App-Storage-
    /// Key, den auch Verbformen / Akzente / Settings nutzen. Änderungen
    /// in den Settings aktualisieren die Setup-Card-Subtitle live.
    @AppStorage(appSpeedRoundDurationKey) var speedRoundDurationSeconds: Int = SpeedRoundDuration.defaultDuration.rawValue
    /// **Sweep C — AnswerMode (2026-05-07)** — Persistierter Sprechen/
    /// Tippen-Modus für **Nomen**. Schreibt durch zu UserDefaults
    /// (`appAnswerModeNomenKey`); der `TrainingSessionController` liest
    /// denselben Key in seinem `nounAnswerMode`-Initializer. Setup-
    /// Screen + Slot-launched Sessions sehen damit denselben Stand.
    @AppStorage(appAnswerModeNomenKey) var nomenAnswerModeRaw: String = AnswerMode.speech.rawValue
    /// Binding-Bridge zwischen `@AppStorage`-String und der typsicheren
    /// `AnswerMode`-Enum für den `AnswerModeSelector`. Setter schreibt
    /// die Persistierung **und** synchronisiert den Live-Session-State
    /// (`session.nounAnswerMode`), damit das Render-Branch in der
    /// laufenden Setup-View ohne Round-Trip greift.
    var nomenAnswerModeBinding: Binding<AnswerMode> {
        Binding(
            get: { AnswerMode(rawValue: self.nomenAnswerModeRaw) ?? .speech },
            set: { newValue in
                self.nomenAnswerModeRaw = newValue.rawValue
                self.session.nounAnswerMode = newValue
            }
        )
    }

    /// **Sweep C — AnswerMode (2026-05-07)** — Persistierter Sprechen/
    /// Tippen-Modus für **Vokabeln**. Analog zu `nomenAnswerModeRaw`.
    @AppStorage(appAnswerModeVokabelnKey) var vokabelnAnswerModeRaw: String = AnswerMode.speech.rawValue
    var vokabelnAnswerModeBinding: Binding<AnswerMode> {
        Binding(
            get: { AnswerMode(rawValue: self.vokabelnAnswerModeRaw) ?? .speech },
            set: { newValue in
                self.vokabelnAnswerModeRaw = newValue.rawValue
                self.session.vokabelnAnswerMode = newValue
            }
        )
    }
    @ObservedObject var listStore: VocabularyListStore
    let runtimeSpeechController: SpeechController?
    let runtimeSpeaker: Speaker?
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let launchContext: TrainingLaunchContext?
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let ensureAudioDependenciesReady: () async -> Void
    var sectionStyle: AppSectionStyle {
        switch session.trainingMode {
        case .vocabulary: return .train
        case .nouns: return .trainNouns
        case .articles: return .trainArticles
        case .verbs: return .trainVerbs
        case .verbforms: return .trainVerbforms
        }
    }

    @StateObject var session = TrainingSessionController()
    /// **Stufe 4b-Modal-Refactor (2026-05-02)** — Token der aktuellen
    /// `TrainingChainStore`-Force-Advance-Handler-Registration. Siehe
    /// `FlashcardsView.forceAdvanceHandlerToken` für Doc.
    @State var forceAdvanceHandlerToken: UUID?
    @State var lastResult: ScoreResult?
    @State var shouldEvaluateAfterStop = false
    @State var pendingFeedbackTask: DispatchWorkItem?
    @State var typedAnswer = ""
    @State var showingTypedAnswerInput = false
    /// **Daily Drop Modul 2.12 (2026-05-23)** — Weiter-Button-Flow im
    /// Count-Modus (Vokabel): nach dem Check wartet die Karte auf den
    /// expliziten „Weiter"-Tap statt auf den 2.6-Auto-Advance. EIN Versuch
    /// pro Karte (kein Retry). `vokabelPendingCorrect` hält das gemerkte
    /// Ergebnis, `vokabelCheckedAnswer` die geprüfte/erkannte Antwort für
    /// die Feedback-Card. Nur Count-Modus; normales Training nutzt sie nie.
    @State var vokabelAwaitingWeiter = false
    @State var vokabelPendingCorrect: Bool?
    @State var vokabelCheckedAnswer = ""
    @State var hasTriggeredAudioPreparation = false
    @State var isPreparingAudioDependencies = false
    @State var wasSpeakerSpeaking = false
    @State var wasRecording = false
    /// **2026-08-06, Bug-Fix** — treibt den Mikrofon-Puls
    /// (`appListeningPulse`). Vorher las der Puls-Aufruf direkt
    /// `isSpeechRecording`, eine reine `computed property` auf
    /// `runtimeSpeechController?.isRecording` — ein `let`, kein
    /// `@ObservedObject`. Karteikarten hält den Controller dagegen
    /// direkt als `@ObservedObject`, weshalb dort jede `isRecording`-
    /// Änderung automatisch neu rendert. In Training gab es zwar schon
    /// eine `.onReceive`-Bridge auf `$isRecording` (siehe
    /// `TrainingView+Layout`), aber `handleTrainingRecordingPulseChange`
    /// — die genau dafür gedacht war — war eine leere Hülle ohne Body
    /// (User-Report: „das Mikrofon blinkt in Training nicht, in
    /// Karteikarten schon"). Dieser State-Wert wird jetzt dort gesetzt
    /// und treibt den Puls, statt der nie aktualisierten computed
    /// property.
    @State var isMicPulseActive = false
    @State var articleAnswer: String?
    @State var articleLocked = false
    @State var showingArticleTranslation = false
    @State var verbMCOptions: [String] = []
    @State var verbMCSelected: String?
    @State var verbMCLocked = false
    @State var showingVerbTranslation = false
    // Nomen-Modus „Wortauswahl" — analog zum Verben-MC-Grid, aber
    // Distraktoren werden aus `wordClass == "noun"` gezogen. Aktiv nur,
    // wenn `session.nounAnswerMode == .choice` und Speed Round aus ist
    // (siehe `isNounChoiceMode`). Speech-Pfad (ohne Wortauswahl) bleibt
    // unverändert — keiner dieser States wird dann je mit Wert belegt.
    @State var nounMCOptions: [String] = []
    @State var nounMCSelected: String?
    @State var nounMCLocked = false
    @State var vocabularyListPickerActive: Bool = false

    // Verbformen
    @StateObject var verbformsSession = VerbformsSessionController()
    @State var verbformsInflections: [VerbformsEngine.VerbInflections] = []
    /// **2026-05-06** — Phase-Enum statt `Int?`. Verbformen nutzt
    /// jetzt den geteilten `SpeedRoundCountdownSequencer`; das State-
    /// Property hält die aktuelle Phase (Achtung… / 3 / 2 / 1 / Los
    /// geht's!) und steuert das Overlay-Render in TrainingView+Layout.
    @State var verbformsCountdownPhase: SpeedCountdownPhase? = nil

    /// **2026-05-06 Cancel-Fix** — Aktive Countdown-Tasks. Werden
    /// beim Cleanup (View-Disappear, dismissToHome, Reset-Pfade)
    /// gecancelt, damit pending DispatchWorkItems der Intro-Sequenz
    /// nicht im Hintergrund weiterlaufen (Audio-Ticks + finaler
    /// Engine-Start-Trigger). User-Bug-Report 2026-05-06: Speed
    /// Round lief nach Home-Tap weiter.
    @State var trainingCountdownTask: SpeedRoundCountdownTask? = nil
    @State var verbformsCountdownTask: SpeedRoundCountdownTask? = nil

    // Session-Summary-Outcomes — werden beim Reward-Vergeben gesetzt und
    // steuern die Anzeige der zentralen `SessionSummaryView`. Für Training
    // als Overlay (nach `handleTopBarBack`), für Verbformen ersetzt das
    // Outcome den bisherigen Result-Screen komplett.
    @State var trainingSessionOutcome: SessionRewardOutcome?
    @State var verbformsSessionOutcome: SessionRewardOutcome?
    /// **2026-08-04** — Anzahl der Wörter, die während der jeweiligen
    /// Session von „Wackelkandidat" zu „Stark" gewechselt sind. Gesetzt
    /// zusammen mit den Outcomes oben (`awardTrainingXPIfNeeded()` /
    /// `awardVerbformsXPIfNeeded()`).
    @State var trainingWackelkandidatenCleared: Int = 0
    @State var verbformsWackelkandidatenCleared: Int = 0

    /// Zentrale Session-End-Prüfung — wahr, sobald
    ///   (a) die Speed-Round-Zeit abgelaufen ist **und** eine Speed Round
    ///       tatsächlich lief, oder
    ///   (b) bereits ein Outcome erzeugt wurde (Summary sichtbar).
    /// Wird von allen MC-Submit-Handlern als Guard verwendet, damit
    /// verzögerte Tap-Events oder Race Conditions zwischen Timer-Ende
    /// und letzter Antwort keine State-Mutationen mehr durchlassen.
    var isTrainingSessionEnded: Bool {
        if trainingSessionOutcome != nil { return true }
        if session.isSpeedRound && session.hasStartedTraining && session.speedRoundTimeRemaining <= 0 {
            return true
        }
        return false
    }
    @ObservedObject var progressStore = ProgressStore.shared

    // Verbformen Drag-and-Drop (Quiz-Stil: DragGesture + Frame-Tracking,
    // KEIN Long-Press wie bei `.draggable`)
    @State var verbformsDraggingPronoun: VerbformsPerson?
    @State var verbformsDragOffset: CGSize = .zero
    @State var verbformsPronounFrames: [VerbformsPerson: CGRect] = [:]
    @State var verbformsFormFrames: [VerbformsPerson: CGRect] = [:]
    @State var verbformsHoveredForm: VerbformsPerson?

    // Verbformen Listen-Picker Sheet (separates Sheet auf der custom Listen-Card)
    @State var verbformsListPickerActive: Bool = false
    // Verbformen Verb-Lemma-Detail-Sheet (geöffnet via „X Verben"-Tap)
    @State var verbformsVerbDetailActive: Bool = false

    // Verben-Modul Listen-Picker / Lemma-Detail (eigene Sheet-States, damit
    // die Custom-Card im Verben-Setup unabhängig von Verbformen funktioniert)
    @State var verbsListPickerActive: Bool = false
    @State var verbsVerbDetailActive: Bool = false

    // Nomen + Artikel: jeweils eigener Listen-Picker (gleicher Stil wie Verben)
    @State var nounsListPickerActive: Bool = false
    @State var articlesListPickerActive: Bool = false

    // Empty-Pool-Hint (2026-04-29): Toast für den Last-Line-of-Defense-Pfad
    // im Setup, wenn `canStartTraining` (Pre-Tap-Defense) `true` lieferte,
    // aber `buildTrainingDeck()` dann doch leer baut (Cache-Stale-Edge-Case
    // — typisch bei .verbs-Mode mit kürzlich geänderter `lernjahrMax`-
    // Filter-Konfiguration). Pattern analog `ListsView`-Toast: optional
    // String hält die Message, DispatchWorkItem treibt das Auto-Dismiss.
    @State var emptyPoolToastMessage: String? = nil
    @State var emptyPoolToastDismissWorkItem: DispatchWorkItem? = nil

    // Cache: Lemma-Liste für die aktuelle Setup-Card. Wird bei Selection- oder
    // Mode-Wechsel via onChange neu berechnet, NICHT bei jedem Render — sonst
    // hängt die App ab ~4 großen Listen (verbformsLemmasFromSelectedLists ist
    // teuer wegen FrenchListStatisticsAggregator).
    @State var setupCardLemmas: [String] = []
    /// Gecachter „kann Training starten"-Flag für die Modi mit teurer
    /// Analyse-Pipeline (verbs/verbforms/nouns/articles). Wird im selben
    /// Background-Task gesetzt wie `setupCardLemmas`.
    @State var setupCanStartCached: Bool = false

    /// **2026-05-06** — Phase-Enum statt `Int?`. Training (Vokabeln/
    /// Nomen/Artikel/Verben) nutzt den geteilten Countdown-Sequencer;
    /// State-Property hält die aktuelle Phase und steuert das Overlay-
    /// Render in TrainingView+Layout.
    @State var speedCountdownPhase: SpeedCountdownPhase? = nil
    @FocusState var typedAnswerFieldFocused: Bool

    var speechController: SpeechController? {
        runtimeSpeechController
    }

    var speaker: Speaker? {
        runtimeSpeaker
    }

    var trainingListSummary: String {
        "\(trainingListName)\n\(trainingListCount)"
    }

    var trainingListName: String {
        let ids = session.selectedTrainingListIDs
        if ids.isEmpty { return "Lernlisten wählen" }
        let allAvailable = availableTrainingLists
        let selected = allAvailable.filter { ids.contains($0.id) }
        if selected.count == 1, let first = selected.first {
            return first.name
        }
        return "\(selected.count) Lernlisten"
    }

    /// Master-Session-Setup-Estimate für die verpflichtende Gamification-Bar
    /// oberhalb des Training-CTA. Item-Count = effektive aktive Items der
    /// gewählten Liste(n). Modul variiert je nach Training-Typ, damit die
    /// Dauer-Schätzung stimmt (Verbformen kürzer als Vokabel-Training,
    /// Speed-Round nochmal deutlich kürzer).
    @MainActor
    var trainingSessionEstimate: SessionEstimate {
        let items = activeItems.count
        // In Verbformen / Speed-Round rechnet eine Session nicht durch alle
        // Items, sondern durch eine Teilmenge. Als Preview-Schätzung kappen
        // wir auf einen realistischen Session-Umfang — ProgressService liefert
        // am Ende die exakten Werte, aber hier wollen wir Orientierung.
        let estimatedItemCount: Int
        let module: SessionConfig.Module
        if isVerbformsMode {
            module = session.isSpeedRound ? .speedRound : .verbforms
            estimatedItemCount = session.isSpeedRound ? min(items, 20) : min(items, 12)
        } else if session.isSpeedRound {
            module = .speedRound
            estimatedItemCount = min(items, 20)
        } else {
            module = .training
            estimatedItemCount = min(items, 15)
        }
        let config = SessionConfig(module: module, itemCount: estimatedItemCount)
        return SessionSetupEstimator.estimate(
            for: config,
            progress: progressStore.progress,
            dailyChallenge: DailyChallengeStore.shared.challenge
        )
    }

    /// Speed-Round-Preview-Estimate — **immer** mit Speed-Round-Annahme
    /// gerechnet, unabhängig vom aktuell gewählten Modus. Wird im Vokabel-
    /// Setup inline in der „Speed Round"-Mode-Card angezeigt („+225 XP ·
    /// ~3 min · +4"), damit der Nutzer schon **vor** dem Modus-Wechsel
    /// sieht, was ihn bei Speed Round erwartet. Ersetzt die globale
    /// Gamification-Bar am Screen-Bottom, die für den Vokabel-Setup
    /// wegfällt.
    @MainActor
    var speedRoundPreviewEstimate: SessionEstimate {
        let items = activeItems.count
        let config = SessionConfig(module: .speedRound, itemCount: min(items, 20))
        return SessionSetupEstimator.estimate(
            for: config,
            progress: progressStore.progress,
            dailyChallenge: DailyChallengeStore.shared.challenge
        )
    }

    var trainingListCount: String {
        let ids = session.selectedTrainingListIDs
        if ids.isEmpty { return "" }

        // Use activeItems count — same filtering as actual training
        let count = activeItems.count
        if count == 0 {
            let allAvailable = availableTrainingLists
            let selected = allAvailable.filter { ids.contains($0.id) }
            let totalItems = selected.reduce(0) { $0 + $1.items.count }
            return "\(totalItems) Eintr\u{00E4}ge"
        }

        if isVerbMode || isVerbformsMode {
            return "\(count) Verben"
        } else if isArticleMode || isNounMode {
            return "\(count) Nomen"
        } else {
            return "\(count) Eintr\u{00E4}ge"
        }
    }

    var activeItems: [VocabularyItem] {
        session.activeItems(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )
    }

    var currentCard: FlashCard? {
        session.currentTrainingItem?.card(for: session.direction)
    }

    var isNounMode: Bool {
        session.trainingMode == .nouns
    }

    var isArticleMode: Bool {
        session.trainingMode == .articles
    }

    var articlePromptText: String? {
        guard isArticleMode, let item = session.currentTrainingItem else { return nil }
        // Prompt zeigt den **Lernkern** aus dem `ArticleModeClassifier`.
        // „mon ami" → „ami", „la fille" → „fille". So entsteht nie eine
        // sprachlich falsche Kombination wie „le mon ami". Wenn der
        // Classifier den Eintrag als ungültig markiert, sind wir hier
        // nicht — der `.articles`-Item-Filter (siehe
        // `TrainingSessionController+DictionarySelection.swift`) hält
        // ungültige Items erst gar nicht in den Trainings-Pool hinein.
        return ArticleModeClassifier.classify(item).noyauLexical
    }

    var correctArticle: String? {
        guard isArticleMode, let item = session.currentTrainingItem else { return nil }
        // Erwartete Antwort kommt **aus dem Classifier** — nicht mehr aus
        // `determineFrenchArticle(item)` direkt. Der Classifier berechnet
        // die Antwort auf Basis des Lernkerns + Genus + Vokal-Anfang; das
        // alte `determineFrenchArticle` würde bei „mon ami" den Rohtext
        // verwerten und je nach Fallback-Pfad eine falsche Antwort bauen.
        return ArticleModeClassifier.classify(item).reponseAttendueArticle
    }

    var isVerbMode: Bool {
        session.trainingMode == .verbs
    }

    var isVerbformsMode: Bool {
        session.trainingMode == .verbforms
    }

    var ownListCount: Int {
        availableTrainingLists.filter { !$0.isBuiltIn || $0.isAggregateVocabulary }.count
    }
    var levelListCount: Int {
        availableTrainingLists.filter { $0.collectionPreset == .standardLevel }.count
    }
    var topicListCount: Int {
        availableTrainingLists.filter { $0.collectionPreset == .standardTopic }.count
    }
    var allInOneCount: Int { 1 }

    var verbPromptText: String {
        guard let item = session.currentTrainingItem else { return "" }
        let isFRtoDe = selectedAppDirection == .frenchToGerman || selectedAppDirection == .englishToGerman
        return isFRtoDe ? item.french : item.german
    }

    var verbCorrectAnswer: String {
        guard let item = session.currentTrainingItem else { return "" }
        let isFRtoDe = selectedAppDirection == .frenchToGerman || selectedAppDirection == .englishToGerman
        return isFRtoDe ? item.german : item.french
    }

    /// `true`, wenn das Nomen-Modul gerade im 8er-Wortauswahl-Grid läuft.
    /// Orthogonal zu Speed Round — dort greift die eigene Antwort-Mechanik,
    /// nicht der MC-Grid. Außerhalb von Nomen immer `false`.
    var isNounChoiceMode: Bool {
        // **AnswerMode-Migration 2026-05-07** — `.choice` heißt jetzt
        // `.tap` (Sweep C). Semantisch identisch: Tap ↔ 8er-Grid statt
        // Mikrofon.
        isNounMode && session.nounAnswerMode == .tap && !session.isSpeedRound
    }

    /// **Sweep C — AnswerMode (2026-05-07)** — `true`, wenn Vokabeln
    /// im Tippen-Modus läuft: Mikro/Speaker-Row entfällt, die
    /// Typed-Answer-Card wird primäre Eingabe (`actionButtons` und
    /// `typedAnswerControl` branchen darauf). Speed-Round greift
    /// orthogonal — wenn `isSpeedRound == true`, ignorieren wir den
    /// Answer-Mode (Speed-Mechanik hat eigene Antwort-Logik).
    var isVokabelnTapMode: Bool {
        session.trainingMode == .vocabulary
            && session.vokabelnAnswerMode == .tap
            && !session.isSpeedRound
    }

    /// Lösungswort im Wortauswahl-Modus — identisch zur Logik in
    /// `verbCorrectAnswer`, aber getrennt gehalten für die klarere
    /// Trennung der Module. Pro Richtung wird die Ziel-Sprache genommen.
    var nounCorrectAnswer: String {
        guard let item = session.currentTrainingItem else { return "" }
        let isFRtoDe = selectedAppDirection == .frenchToGerman || selectedAppDirection == .englishToGerman
        return isFRtoDe ? item.german : item.french
    }

    var dictionaryTrainingList: VocabularyList? {
        session.dictionaryTrainingList()
    }

    var shouldPrepareDictionaryTrainingList: Bool {
        session.shouldPrepareDictionaryTrainingList(launchContext: launchContext)
    }

    var availableTrainingLists: [VocabularyList] {
        session.availableTrainingLists(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )
    }

    var selectedTrainingList: VocabularyList? {
        session.selectedTrainingList(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )
    }

    var selectedAppDirection: Direction {
        (Direction(rawValue: selectedAppDirectionRaw) ?? .frenchToGerman).sanitizedForFrenchOnly
    }

    var selectedTrainingListLanguages: [StudyLanguage] {
        session.selectedTrainingListLanguages(
            from: listStore,
            selectedAppDirection: selectedAppDirection,
            launchContext: launchContext
        )
    }

    var isDictionaryTrainingSelected: Bool {
        session.isDictionaryTrainingSelected()
    }

    var localeIdentifierForRecognition: String {
        session.direction.recognitionLocaleIdentifier
    }

    var actionButtonHeight: CGFloat {
        AppTheme.Layout.buttonHeight
    }

    var trainingSessionCardInset: CGFloat {
        8
    }

    var recordingSymbolName: String {
        isSpeechRecording ? "stop.fill" : "mic.fill"
    }

    var showsRetryOnlyMessage: Bool {
        lastResult?.label.hasPrefix("Falsch") == true
    }

    var showsNotRecognizedMessage: Bool {
        lastResult?.label == "Nicht erkannt"
    }

    var showsSuccessOnlyMessage: Bool {
        lastResult?.label == "Richtig 🙂"
    }

    var showsSolutionMessage: Bool {
        lastResult?.label == "Lösung"
    }

    var solutionUnlockThreshold: Int {
        0
    }

    var canRevealSolution: Bool {
        session.hasStartedTraining && currentCard != nil && session.failedAttemptsOnCurrentCard >= solutionUnlockThreshold
    }

    var recordingButtonColor: Color {
        if showsSuccessOnlyMessage {
            return AppTheme.Colors.success
        }

        if showsRetryOnlyMessage {
            return Color(red: 0.9, green: 0.3, blue: 0.15)
        }

        return trainingActionTint
    }

    var listeningButtonColor: Color {
        trainingActionTint
    }

    var trainingActionTint: Color {
        sectionStyle.accent
    }

    var isAudioModeEnabled: Bool {
        feedbackPlayer.areSoundsEnabled
    }

    var canUseSpeechRecognition: Bool {
        guard let speechController else { return false }
        return speechController.authorizationStatus != .denied && speechController.authorizationStatus != .restricted
    }

    var solutionButtonTitle: String {
        if canRevealSolution {
            return "Lösung"
        }
        return "Lösung \(session.failedAttemptsOnCurrentCard)/\(solutionUnlockThreshold)"
    }

    var nextCardTitle: String {
        session.cardType == .phrases ? "Nächste Phrase" : "Nächstes Wort"
    }

    var sessionCardMinHeight: CGFloat {
        session.cardType == .phrases ? 152 : 118
    }

    var sessionPromptFont: Font {
        .system(size: session.cardType == .phrases ? 20 : 28, weight: .bold, design: .rounded)
    }

    var trainingItemLabel: String {
        if isVerbMode { return "Verben" }
        if isNounMode || isArticleMode { return "Nomen" }
        return "Eintr\u{00E4}ge"
    }

    var canStartTraining: Bool {
        // Vocabulary nutzt simple cardType-Filterung (kein analyze) — fast.
        // Verbs/Verbforms/Nouns/Articles laufen über teure Pipeline und werden
        // im setupCanStartCached gehalten (per onChange aktualisiert).
        switch session.trainingMode {
        case .vocabulary:
            return !activeItems.isEmpty
        case .verbs, .verbforms, .nouns, .articles:
            return setupCanStartCached
        }
    }

    var isSpeechRecording: Bool {
        speechController?.isRecording == true
    }

    var isSpeakerSpeaking: Bool {
        speaker?.isSpeaking == true
    }

    var startHintText: String {
        if isDictionaryTrainingSelected {
            return "Wähle ein anderen Lernstand oder eine andere Quelle."
        }
        if availableTrainingLists.isEmpty {
            return "Lege zuerst eine Lernliste mit Vokabeln an."
        }
        // Verben sollen sprachlich identisch zu Verbformen („keine Verben
        // erkannt") klingen — statt der generischen „Für diesen Typ…"-
        // Zeile. Alle anderen Modi (Nomen, Artikel, Vokabeln) behalten
        // den allgemeinen Fallback-Text.
        if session.trainingMode == .verbs {
            return "In der gewählten Lernliste wurden keine Verben erkannt."
        }
        return "Für diesen Typ gibt es in der gewählten Lernliste noch keine Einträge."
    }

    /// Hint, der **in** der GamificationBar (Preview-Card über dem CTA)
    /// gerendert werden soll, statt als lose Text-Zeile unter den
    /// Optionen. Aktiv für die beiden Verb-Module (Verben/Verbformen),
    /// wenn der jeweilige Start-Guard negativ ist — die XP-Zahl in der
    /// Bar wird dabei automatisch ausgeblendet und der Hinweis rückt an
    /// die prominenteste Stelle direkt neben „Los geht's!". Alle anderen
    /// Modi (Nomen/Artikel/Vokabeln) bleiben beim Inline-Hint-Pattern.
    var trainingGamificationHintText: String? {
        if session.trainingMode == .verbforms, !verbformsCanStart {
            return verbformsStartHint
        }
        if session.trainingMode == .verbs, !canStartTraining {
            return startHintText
        }
        return nil
    }
}
