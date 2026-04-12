import SwiftUI

struct FlashcardsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.appUsesGlobalChrome) var usesGlobalChrome
    @AppStorage(appDirectionKey) var selectedAppDirectionRaw = Direction.frenchToGerman.rawValue
    @AppStorage(appArcadeCreditsKey) var arcadeCredits = 0
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
    @State var isWaitingToStart = false
    @FocusState var isTypedAnswerFocused: Bool
    @FocusState var isCardCountFieldFocused: Bool
    let flashcardCountInputScrollID = "flashcardCountInput"

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
        152
    }

    var recordingSymbolName: String {
        speechController.isRecording ? "stop.fill" : "mic.fill"
    }

    var progressText: String {
        let mastered = sessionStore.masteredCount
        let almost = sessionStore.almostMasteredCount
        let open = sessionStore.openCount
        if mastered == 0 && almost == 0 {
            return "\(sessionStore.totalCount) Karten · Los geht's!"
        }
        var parts: [String] = []
        if mastered > 0 { parts.append("\(mastered) sicher") }
        if almost > 0 { parts.append("\(almost) fast") }
        if open > 0 { parts.append("\(open) offen") }
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

    var showsSuccessOnlyMessage: Bool {
        interaction.lastResult?.label == "Korrekt! 🙂"
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
        return sectionStyle.accent
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
