import SwiftUI

struct FlashcardsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.appUsesGlobalChrome) var usesGlobalChrome
    /// **Stufe 3 (2026-05-01, Branch `feature/training-session-flow`)** —
    /// Chain-Advance-Closure aus dem `AppDestinationHost`-Wiring. Wenn
    /// `nil` → kein Chain-Modus, Bestand-CTA-Pfad. Sonst: Modul-Done-
    /// CTA ruft den Closure mit dem Session-Outcome auf, der Host
    /// kümmert sich um Outcome-Aggregation + nächsten Step pushen.
    @Environment(\.appChainAdvanceAction) var chainAdvance
    // **Personal-Deck-Teardown (Phase 8)**: Scene-Phase in der Hand, um
    // den Stapel-Fortschritt beim Übergang Background/Inactive abzusichern.
    @Environment(\.scenePhase) var scenePhase
    @AppStorage(appDirectionKey) var selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
    @AppStorage(appArcadeCreditsKey) var arcadeCredits = 0
    /// **Sweep C — AnswerMode (2026-05-07)** — Persistierter Sprechen/
    /// Tippen-Modus für **Karteikarten**. Schreibt durch zu UserDefaults
    /// (`appAnswerModeKarteikartenKey`); der `FlashcardsSessionController`
    /// liest denselben Key, damit Setup-Screen + Slot-launched Sessions
    /// synchron laufen.
    @AppStorage(appAnswerModeKarteikartenKey) var karteikartenAnswerModeRaw: String = AnswerMode.speech.rawValue
    /// Binding-Bridge zwischen `@AppStorage`-String und der typsicheren
    /// `AnswerMode`-Enum für den `AnswerModeSelector`. Setter schreibt
    /// die Persistierung **und** synchronisiert den Live-Session-State
    /// (`interaction.answerMode`).
    var karteikartenAnswerModeBinding: Binding<AnswerMode> {
        Binding(
            get: { AnswerMode(rawValue: self.karteikartenAnswerModeRaw) ?? .speech },
            set: { newValue in
                self.karteikartenAnswerModeRaw = newValue.rawValue
                self.interaction.answerMode = newValue
            }
        )
    }
    @ObservedObject var sessionStore: FlashcardSessionStore
    @ObservedObject var listStore: VocabularyListStore
    @ObservedObject var speechController: SpeechController
    @ObservedObject var speaker: Speaker
    @ObservedObject var feedbackPlayer: FeedbackPlayer
    let launchContext: FlashcardLaunchContext?
    let goHome: () -> Void
    let openSettings: () -> Void
    let openInfo: () -> Void
    let sectionStyle: AppSectionStyle = .flashcards

    @StateObject var setup = FlashcardsSetupController()
    @StateObject var interaction = FlashcardsSessionController()
    @ObservedObject var progressStore = ProgressStore.shared
    @State var isWaitingToStart = false
    /// Cached Reward-Outcome der gerade abgeschlossenen Session — wird
    /// für die Session-Summary-Card (`flashcardCompletionCard`) gebraucht.
    /// Gesetzt von `consumeFlashcardSessionReward()`.
    @State var flashcardSessionOutcome: SessionRewardOutcome?
    @FocusState var isTypedAnswerFocused: Bool
    @FocusState var isCardCountFieldFocused: Bool
    let flashcardCountInputScrollID = "flashcardCountInput"

    // Listen-Picker-Sheet für die custom Listen-Card im Speed-Round-Stil
    // **Cleanup 2026-05-08** — `stackListPickerActive` State entfernt:
    // gehörte zum legacy `flashcardsListSelectionCard`-Pfad, der mit
    // der Master-Migration durch `ListCategoryPickerView` +
    // `GlobalListPickerSheet` ersetzt wurde.

    /// **Karteikarten Pre-Screen-Pop-up (2026-05-09)** — Sichtbarkeit
    /// des Pre-Screen-Modals (Slot-Style nachgebaut), das KARTEN-Slider
    /// + SCHWIERIGKEIT-Buttons vor dem eigentlichen Setup-Screen zeigt.
    /// Auto-Trigger via `.onAppear` (gated über `hasAutoTriggeredAmountPopup`),
    /// manueller Re-Trigger via Tap auf die Mengen-Anzeige-Card im
    /// Setup-Body.
    @State var isShowingAmountPopup: Bool = false
    /// Verhindert dass das Pre-Screen-Pop-up bei jedem `.onAppear`-Cycle
    /// erneut auto-feuert (z. B. nach Sheet-Cancel). Auto-Trigger feuert
    /// genau einmal pro Navigation-Push; danach nur noch manuelle Tap-
    /// Trigger über die Mengen-Anzeige-Card. Reset passiert automatisch
    /// wenn FlashcardsView neu instanziiert wird (jeder Push erstellt
    /// frisches @State).
    @State var hasAutoTriggeredAmountPopup: Bool = false

    // MARK: - Persönlicher Trainingsmodus (Phase 8)
    //
    // Separater State-Block für den neuen „MEINE STAPEL"-Setup-Block +
    // Create-/Rename-/Delete-Sheets. Komplett unabhängig vom bestehenden
    // Setup-Flow — so bleibt die reguläre Session-Logik unberührt.
    @StateObject var personalDeckStore = PersonalDeckStore.shared
    /// **Phase 8.2 Entry-Button-Refactor**: Subscreen für Meine Stapel.
    /// Create/Edit/Delete-Sheets + Alerts leben jetzt IN der
    /// `PersonalDecksView`, nicht mehr im Setup-Parent — der Setup-
    /// Parent pusht nur noch die View an und trägt die Session-Start-
    /// Callback nach oben zurück.
    @State var isShowingPersonalDecksScreen: Bool = false

    /// **User-Revision 2026-04-22 (Bug-Fix)**: Schutzschild gegen den
    /// Auto-Switch in `handleFlashcardsAppear`. SwiftUI feuert
    /// `.onAppear` auch beim Pop einer NavigationDestination — wenn
    /// der User aus dem Meine-Stapel-Subscreen zurück kommt, würde
    /// der Auto-Switch ihn in die laufende Session werfen, obwohl
    /// er ins Setup zurück möchte. Flag wird beim ERSTEN Appear
    /// gesetzt; danach läuft der Auto-Switch nicht mehr.
    @State var hasHandledInitialFlashcardsAppear: Bool = false

    /// **Stufe 4b-Modal-Refactor (2026-05-02)** — Token der aktuellen
    /// `TrainingChainStore`-Force-Advance-Handler-Registration. Wird
    /// im `.onAppear` gesetzt und im `.onDisappear` zum sicheren
    /// Unregister benutzt — verhindert Lifecycle-Race bei Chain-Step-
    /// Transitions, wo eine neue View-Instance vor dem `.onDisappear`
    /// der alten mountet.
    @State var forceAdvanceHandlerToken: UUID?

    var currentCard: FlashcardDeckCard? {
        sessionStore.currentCard
    }

    var currentFlashCard: FlashCard? {
        interaction.currentFlashCard
    }

    var isSessionReady: Bool {
        sessionStore.hasActiveSession && currentCard != nil
    }

    var isFlashcardSessionCompleted: Bool {
        sessionStore.session?.isCompleted == true
    }

    var actionButtonHeight: CGFloat {
        54
    }

    var flashcardSessionCardInset: CGFloat {
        8
    }

    var flashcardSecondaryActionHeight: CGFloat {
        38
    }

    var flashcardFaceHeight: CGFloat {
        // **Karteikarten-Design Phase 8.4** (User-Revision „etwas größer"):
        // 320×210 pt — gleiche Ratio (~1.524), 6,5 % größer. Container-
        // Höhe für den Flip-ZStack + umliegende Layout-Berechnungen.
        210
    }

    var recordingSymbolName: String {
        speechController.isRecording ? "stop.fill" : "mic.fill"
    }

    var progressText: String {
        let mastered = sessionStore.masteredCount
        let almost = sessionStore.almostMasteredCount
        let open = sessionStore.openCount
        let wrongTotal = sessionStore.wrongCount
        if mastered == 0 && almost == 0 && wrongTotal == 0 {
            return "\(sessionStore.totalCount) Karten · Los geht's!"
        }
        // Labels passen sich an den gewählten Mastery-Schwellenwert an:
        // • 1× richtig → „richtig" (keine Zwischen-Stufe, Karte fällt sofort raus)
        // • 2×/3× richtig → „sicher" mit Zwischen-Stufe „fast" für Karten, die
        //   schon einmal richtig waren, aber die Schwelle noch nicht erreicht haben.
        // „X falsch" zählt alle falschen Antworten insgesamt (Gesamtzähler),
        // unabhängig davon, ob die Karte später noch richtig gelöst wurde.
        let threshold = sessionStore.masteryThreshold
        let masteredLabel = threshold <= 1 ? "richtig" : "sicher"
        var parts: [String] = []
        if mastered > 0 { parts.append("\(mastered) \(masteredLabel)") }
        if almost > 0 { parts.append("\(almost) fast") }
        if open > 0 { parts.append("\(open) offen") }
        if wrongTotal > 0 { parts.append("\(wrongTotal) falsch") }
        return parts.joined(separator: " · ")
    }

    var selectedAppDirection: Direction {
        Direction(rawValue: selectedAppDirectionRaw) ?? .frenchToGerman
    }

    var availableStackLists: [VocabularyList] {
        setup.availableStackLists(from: listStore, selectedAppDirection: selectedAppDirection)
    }

    var selectedStackLists: [VocabularyList] {
        setup.selectedStackLists(from: listStore, selectedAppDirection: selectedAppDirection)
    }

    var selectedStackCardCount: Int {
        setup.selectedStackCardCount(from: listStore, selectedAppDirection: selectedAppDirection)
    }

    var effectiveSelectedCardCount: Int {
        setup.effectiveSelectedCardCount(for: selectedStackCardCount)
    }

    var selectedCardCountForSetup: Int {
        setup.selectedCardCountForSetup(selectedStackCardCount: selectedStackCardCount)
    }

    var selectedStackSummary: String {
        let listCount = selectedStackLists.count
        let totalCards = selectedStackCardCount

        if listCount == 0 {
            return "Liste wählen"
        }

        if listCount == 1, let firstList = selectedStackLists.first {
            return "\(flashcardListDisplayName(firstList)) · \(countLabel(totalCards, singular: "Karte", plural: "Karten"))"
        }

        return "\(countLabel(listCount, singular: "Liste", plural: "Listen")) · \(countLabel(totalCards, singular: "Karte", plural: "Karten"))"
    }

    var isDictionarySelectedInStack: Bool {
        setup.isDictionarySelectedInStack()
    }

    var canStartSetup: Bool {
        selectedCardCountForSetup > 0
    }

    /// Master-Session-Setup-Estimate für die verpflichtende Gamification-Bar
    /// oberhalb des Setup-CTA. itemCount = effektive Karten-Anzahl,
    /// roundMultiplier = Mastery-Threshold (1×/2×/3× richtige Antworten
    /// bevor die Karte aus dem Stapel fällt).
    @MainActor
    var flashcardsSessionEstimate: SessionEstimate {
        let config = SessionConfig(
            module: .flashcards,
            itemCount: flashcardEffectiveCardCount,
            roundMultiplier: setup.masteryThreshold
        )
        return SessionSetupEstimator.estimate(
            for: config,
            progress: progressStore.progress,
            dailyChallenge: DailyChallengeStore.shared.challenge
        )
    }

    var showsSuccessOnlyMessage: Bool {
        interaction.lastResult?.label == "Richtig 🙂"
    }

    var showsWrongOnlyMessage: Bool {
        interaction.lastResult?.label.hasPrefix("Falsch") == true
    }

    var flashcardRecordingButtonColor: Color {
        if showsSuccessOnlyMessage {
            return AppTheme.Colors.success
        }
        if showsWrongOnlyMessage {
            return Color(red: 0.9, green: 0.3, blue: 0.15)
        }
        // Dezenter Accent-Ton: der Mikro-/Stop-Button soll optisch hinter der
        // Karteikarte zurücktreten (sie hat jetzt einen kräftigeren Accent-
        // Hintergrund). `secondarySurface` bleibt die dunkle Basisfarbe, die
        // eigentliche Akzentuierung übernimmt das Icon selbst.
        return AppTheme.Colors.secondarySurface
    }

    var isAudioModeEnabled: Bool {
        feedbackPlayer.areSoundsEnabled
    }

    var canUseSpeechRecognition: Bool {
        speechController.authorizationStatus != .denied && speechController.authorizationStatus != .restricted
    }

    var canRestorePreviousFlashcard: Bool {
        interaction.canRestorePreviousFlashcard && !setup.isShowingSetup
    }

    var flashcardTopBarSpacing: CGFloat {
        AppLayout.topBarInsetTop + AppTheme.Spacing.xs
    }

    var flashcardBottomBarSpacing: CGFloat {
        AppLayout.bottomBarInsetBottom + AppTheme.Spacing.sm
    }
}
