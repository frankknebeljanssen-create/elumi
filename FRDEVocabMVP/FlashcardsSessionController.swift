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
