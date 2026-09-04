import SwiftUI

struct QuizView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.appUsesGlobalChrome) var usesGlobalChrome
    /// **Stufe 3 (2026-05-01)** — Chain-Advance-Closure (siehe
    /// FlashcardsView.swift:Doc).
    @Environment(\.appChainAdvanceAction) var chainAdvance
    /// **Daily Drop Modul 2.8 (2026-05-23)** — siehe TrainingView: bei
    /// Tippfeld-Fokus den globalen Footer ausblenden (bewiesener Chat-
    /// Keyboard-Mechanismus), Reset bei Blur + onDisappear.
    @Environment(\.appSetChatKeyboardActiveAction) var setKeyboardChromeHidden
    @AppStorage(appDirectionKey) var selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
    @AppStorage(appQuizHeartsKey) var collectedWorms = 0
    @AppStorage(appElumiWaterflohKey) var collectedWaterfloh = 0
    @AppStorage(appElumiAlgenkugelKey) var collectedAlgenkugel = 0
    @AppStorage(appElumiXPKey) var collectedXP = 0
    @AppStorage(appElumiCurrentStreakKey) var currentStreak = 0
    @AppStorage(appElumiBestStreakKey) var bestStreak = 0
    @AppStorage(appElumiLastRewardDayIndexKey) var lastRewardDayIndex = 0
    @AppStorage(appArcadeCreditsKey) var arcadeCredits = 0
    @ObservedObject var listStore: VocabularyListStore
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let launchContext: QuizLaunchContext?
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let sectionStyle: AppSectionStyle = .quiz

    @StateObject var session = QuizSessionController()
    /// **Stufe 4b-Modal-Refactor (2026-05-02)** — Token der aktuellen
    /// `TrainingChainStore`-Force-Advance-Handler-Registration. Siehe
    /// `FlashcardsView.forceAdvanceHandlerToken` für Doc.
    @State var forceAdvanceHandlerToken: UUID?
    @State var selectedMultipleChoiceOption: String?
    @State var multipleChoiceLocked = false
    @State var selectedPromptID: UUID?
    @State var selectedAnswerID: UUID?
    @State var matchedPairIDs: Set<UUID> = []
    @State var matchingHadMistake = false
    @State var flashingPromptID: UUID?
    @State var flashingAnswerID: UUID?
    @State var draggingPromptID: UUID?
    @State var dragOffset: CGSize = .zero
    @State var hoveredAnswerID: UUID?
    @State var answerFrames: [UUID: CGRect] = [:]
    @State var promptFrames: [UUID: CGRect] = [:]
    @State var fillBlanksSelected: String?
    @State var fillBlanksLocked = false
    @State var fillBlanksHadMistake = false
    @State var fillBlanksWrongOptions: Set<String> = []
    @State var fillBlanksFlashWrong: String?
    @State var comboSelectedVerbID: UUID?
    @State var comboMatchedIDs: Set<UUID> = []
    @State var comboHadMistake = false
    @State var comboFlashVerbID: UUID?
    @State var comboFlashNounID: UUID?
    @State var awardedHearts = 0
    @State var awardedWaterfloh = 0
    @State var awardedAlgenkugel = 0
    @State var unlockedRewardLevels: [ElumiLevelTier] = []
    @State var didPersistHearts = false
    /// Outcome aus dem zentralen `ProgressService` — wird in `persistHeartsIfNeeded`
    /// gesetzt und speist die `SessionSummaryView` im Ergebnis-Screen.
    @State var quizSessionOutcome: SessionRewardOutcome?
    /// **2026-08-04** — Wackelkandidaten-Snapshot bei Quiz-Start
    /// (`startQuiz()`) und die daraus in `persistHeartsIfNeeded()`
    /// berechnete Anzahl frisch „stark" gewordener Wörter.
    @State var quizWackelkandidatenSnapshot: Set<String> = []
    @State var quizWackelkandidatenCleared: Int = 0
    @ObservedObject var progressStore = ProgressStore.shared
    @State var advanceTask: DispatchWorkItem?
    @State var typingInput = ""
    @State var typingLocked = false

    /// **2026-06-09** — War die getippte Antwort richtig? Färbt das
    /// Eingabefeld grün, sobald geprüft wurde.
    ///
    /// Vorher gab es diese Bestätigung nur im Daily-Drop-Modus (wo auf
    /// „Weiter" gewartet wird); im normalen Quiz schaltete die Frage
    /// kommentarlos weiter. Alle anderen Fragetypen (Multiple Choice,
    /// Lückentext, Zuordnen) zeigen ihren Treffer grün — Tippen war die
    /// Ausnahme.
    @State var typingWasCorrect = false
    @State var typingShowCorrectAnswer: String?
    /// **Daily Drop Modul 2.12 (2026-05-23)** — Weiter-Button-Flow im
    /// Count-Modus: nach dem Check (Antwort geprüft, Feedback sichtbar)
    /// wartet die Frage auf den expliziten „Weiter"-Tap statt auf den
    /// 2.6-Auto-Advance. `quizPendingCorrect` hält das gemerkte Ergebnis
    /// bis Weiter es an `completeCurrentQuestion(correct:)` weiterreicht.
    /// Nur Count-Modus; normales Quiz/Zeit-Chain nutzt die States nie.
    @State var quizAwaitingWeiter = false
    @State var quizPendingCorrect: Bool?
    /// **Gruppe-3-Migration (2026-05-22)** — Push-State für den
    /// `UnifiedListCategoryPicker`. Getriggert via `onTap` in der
    /// `ListCategoryPickerView`-Card im `quizSetupScreen`.
    /// `.navigationDestination` sitzt im `body`-Modifier-Chain.
    /// Ersetzt den toten `showingQuizListPicker`-State (war nie true).
    @State var quizListPickerActive: Bool = false
    @FocusState var isTypingFieldFocused: Bool

    /// **Daily Drop Modul 2.5 (2026-05-23)** — Läuft dieser Quiz-Step in
    /// einer Count-Modus-Chain? Dann nahtloser Auto-Advance statt
    /// Zwischen-Summary. False bei Zeit-Chain (Summary+CTA) und im
    /// isolierten Modul-1-Test (kein chainContext).
    var isCountChainStep: Bool {
        launchContext?.chainContext?.isCountMode == true
    }

    var selectedAppDirection: Direction {
        (Direction(rawValue: selectedAppDirectionRaw) ?? .frenchToGerman).sanitizedForFrenchOnly
    }

    var quizListSummary: String {
        let ids = session.selectedListIDs
        if ids.isEmpty { return "Lernlisten wählen" }
        let selected = availableQuizLists.filter { ids.contains($0.id) }
        // **V1b (2026-04-28)** — Setup-Counts respektieren den globalen
        // Lernjahr-Filter; konsistent zu dem was nach „Quiz starten"
        // tatsächlich in den Question-Pool einfließt.
        let lernjahrMax = VocabularyListSelectionResolver.currentLernjahrMax()
        if selected.count == 1, let first = selected.first {
            let cnt = VocabularyListSelectionResolver.effectiveItems(
                for: first, lernjahrMax: lernjahrMax
            ).count
            return "\(first.name) · \(cnt) Einträge"
        }
        let total = selected.reduce(0) { acc, list in
            acc + VocabularyListSelectionResolver.effectiveItems(
                for: list, lernjahrMax: lernjahrMax
            ).count
        }
        return "\(selected.count) Lernlisten · \(total) Einträge"
    }

    var availableQuizLists: [VocabularyList] {
        var lists: [VocabularyList] = []
        if let aggregateList = listStore.allCustomVocabularyList {
            lists.append(aggregateList)
        }
        lists.append(contentsOf: listStore.sortedCustomLists)
        lists.append(contentsOf: StandardVocabularyLoader.levelLists)
        lists.append(contentsOf: StandardVocabularyLoader.topicLists)
        return lists
    }

    var selectedQuizLists: [VocabularyList] {
        // **2026-08-06** — verwaiste IDs abfangen (entfallene C1/C2-
        // Lernlisten); siehe `VocabularyListSelectionResolver.
        // prunedSelectedListIDs`. Ohne das ergäbe eine alte C2-Auswahl
        // eine leere Liste und damit ein nicht startbares Quiz.
        guard !session.selectedListIDs.isEmpty else { return [] }
        let usableIDs = VocabularyListSelectionResolver.prunedSelectedListIDs(
            session.selectedListIDs,
            knownListIDs: Set(availableQuizLists.map(\.id))
        )
        return availableQuizLists.filter { usableIDs.contains($0.id) }
    }

    var canStartQuiz: Bool {
        session.canStartQuiz
    }

    /// Master-Session-Setup-Estimate für die Gamification-Bar.
    /// Berechnet aus der aktuellen Quiz-Config (Fragenzahl) + zentralen Werten.
    @MainActor
    var quizSessionEstimate: SessionEstimate {
        let config = SessionConfig(module: .quiz, itemCount: session.questionCountOption.rawValue)
        return SessionSetupEstimator.estimate(
            for: config,
            progress: progressStore.progress,
            dailyChallenge: DailyChallengeStore.shared.challenge
        )
    }

    var currentQuestion: QuizQuestion? {
        session.currentQuestion
    }

    var displayedQuestionCount: Int {
        session.displayedQuestionCount
    }

    var correctCount: Int {
        session.correctCount
    }

    var wrongCount: Int {
        session.wrongCount
    }

    var resultHeadline: String {
        if !unlockedRewardLevels.isEmpty {
            return "Level-Up!"
        }

        if wrongCount == 0, !session.answeredResults.isEmpty {
            return "Perfekte Lektion!"
        }

        switch correctCount {
        case 8...:
            return "Excellent !"
        case 5...:
            return "Très bien !"
        case 1...:
            return "Bien joué !"
        default:
            return "Continue !"
        }
    }

    var currentLevelAfterRewards: ElumiLevelTier {
        elumiLevelTier(for: collectedXP)
    }

    var isPerfectQuiz: Bool {
        wrongCount == 0 && !session.answeredResults.isEmpty
    }

    var totalRewardCount: Int {
        awardedHearts + awardedWaterfloh + awardedAlgenkugel
    }

    /// **Snack-Rewards für die Standard-Summary (2026-05-22)** — baut die
    /// kompakten Snack-Chips (Würmchen/Wasserfloh/Algenkugel) für den
    /// `snackRewards`-Block der `SessionSummaryView`. Nur Posten > 0.
    var quizSnackRewards: [SessionSummaryView.SnackReward] {
        var rewards: [SessionSummaryView.SnackReward] = []
        if awardedHearts > 0 {
            rewards.append(.init(kind: .wuermchen, count: awardedHearts))
        }
        if awardedWaterfloh > 0 {
            rewards.append(.init(kind: .wasserfloh, count: awardedWaterfloh))
        }
        if awardedAlgenkugel > 0 {
            rewards.append(.init(kind: .algenkugel, count: awardedAlgenkugel))
        }
        return rewards
    }

    var quizTopBarSpacing: CGFloat {
        AppLayout.topBarInsetTop + AppTheme.Spacing.xs
    }

    var quizBottomBarSpacing: CGFloat {
        AppLayout.bottomBarInsetBottom + AppTheme.Spacing.sm
    }

    var quizSetupCardInset: CGFloat {
        8
    }
}
