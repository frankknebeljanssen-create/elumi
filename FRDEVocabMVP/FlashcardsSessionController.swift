import Foundation
import SwiftUI

@MainActor
final class FlashcardsSessionController: ObservableObject {
    @Published var lastResult: ScoreResult?
    @Published var showingSolution = false
    @Published var isFlashcardFlipped = false
    @Published var cardFlyOutOffset: CGFloat = 0
    @Published var cardFlyOutRotation: Double = 0
    @Published var cardFlyOutOpacity = 1.0
    @Published var typedAnswer = ""
    @Published var showingTypedAnswerInput = false
    @Published var isMicPulseVisible = false
    @Published var displayedFlashCard: FlashCard?

    /// Live-Offset, während der User die Karte mit dem Finger zieht.
    /// 0 = Ruheposition. Negativer Wert = nach links (Weiter), positiv = rechts (Zurück).
    @Published var swipeDragOffset: CGFloat = 0
    /// Wird nach dem ersten erfolgreichen Swipe in UserDefaults persistiert,
    /// damit der „wischen"-Hint danach dauerhaft ausgeblendet bleibt.
    /// Migrations-Key v2: nach Layout-Umbau einmalig neu zeigen.
    @Published var hasSeenSwipeHint: Bool = UserDefaults.standard.bool(forKey: "FRDEVocabMVP.flashcards.hasSeenSwipeHint.v2")

    func markSwipeHintSeen() {
        guard !hasSeenSwipeHint else { return }
        hasSeenSwipeHint = true
        UserDefaults.standard.set(true, forKey: "FRDEVocabMVP.flashcards.hasSeenSwipeHint.v2")
    }

    var shouldEvaluateAfterStop = false
    var wasSpeakerSpeaking = false
    var pendingFeedbackTask: DispatchWorkItem?
    var flashcardHistory: [HistoryEntry] = []

    var currentFlashCard: FlashCard? {
        displayedFlashCard
    }

    var canRestorePreviousFlashcard: Bool {
        !flashcardHistory.isEmpty
    }

    deinit {
        pendingFeedbackTask?.cancel()
    }
}
